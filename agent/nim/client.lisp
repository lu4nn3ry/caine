;;;; ============================================================================
;;;; client.lisp — Cliente de chat completions + loop de tool calling
;;;; ============================================================================
;;;; Fala com a API NVIDIA NIM (OpenAI-compatible):
;;;;
;;;;   POST {base_url}/chat/completions
;;;;
;;;; O loop agêntico envia as mensagens, executa os `tool_calls` retornados,
;;;; anexa os resultados como mensagens `role:"tool"` e repete até o modelo
;;;; responder em texto ou atingir `max_tool_iterations`.
;;;; ============================================================================

(in-package :caine.nim)

;;; ---------------------------------------------------------------------------
;;; Construção de mensagens
;;; ---------------------------------------------------------------------------

(defun make-message (role content &key tool-calls tool-call-id name)
  "Cria um objeto de mensagem para o payload."
  (let ((m (make-json-object "role" role)))
    (when content (setf (gethash "content" m) content))
    (when tool-call-id (setf (gethash "tool_call_id" m) tool-call-id))
    (when name (setf (gethash "name" m) name))
    (when tool-calls (setf (gethash "tool_calls" m) tool-calls))
    m))

(defun system-messages (config)
  "Lista com a mensagem de sistema, se houver."
  (let ((system (config-system config)))
    (if (and system (not (string= system "")))
        (list (make-message "system" system))
        '())))

(defun build-payload (config messages)
  "Monta o corpo JSON do request de chat completions."
  (let ((payload (make-json-object
                  "model" (config-model config)
                  "messages" messages
                  "max_tokens" (config-max-tokens config)
                  "temperature" (config-temperature config)
                  "stream" :false)))
    (when (config-tools-enabled-p config)
      (setf (gethash "tools" payload) (tools-schema-vector))
      (setf (gethash "tool_choice" payload) "auto"))
    payload))

;;; ---------------------------------------------------------------------------
;;; Chamada à API
;;; ---------------------------------------------------------------------------

(defun chat-endpoint (config)
  (format nil "~a/chat/completions"
          (string-right-trim "/" (config-base-url config))))

(defun parse-chat-response (body)
  "Extrai (values message finish-reason) da resposta ou sinaliza API-ERROR."
  (let ((obj (handler-case (json-parse body)
               (json-error (e)
                 (error 'api-error
                        :mensagem "resposta não é JSON válido"
                        :corpo (format nil "~a :: ~a" e
                                       (subseq body 0 (min 500 (length body)))))))))
    (let ((err (json-get obj "error")))
      (when err
        (error 'api-error
               :mensagem (if (hash-table-p err)
                             (json-get err "message" (json-encode err))
                             (format nil "~a" err)))))
    (let* ((choices (json-get obj "choices" #()))
           (choice (if (plusp (length choices)) (aref choices 0) nil)))
      (unless choice
        (error 'api-error :mensagem "resposta sem 'choices'" :corpo body))
      (values (json-get choice "message" (make-json-object))
              (json-get choice "finish_reason" nil)))))

(defun request-chat (config messages)
  "Envia MESSAGES e retorna (values message finish-reason)."
  (let ((key (resolve-api-key)))
    (unless key
      (error 'config-error
             :mensagem "API key ausente. Defina NVIDIA_API_KEY, NIM_API_KEY ou rode `caine-nim key set`."))
    (multiple-value-bind (body status)
        (http-post-json (chat-endpoint config)
                        (json-encode (build-payload config messages))
                        :api-key key
                        :timeout (config-timeout config))
      (cond
        ((null status)
         (error 'api-error :mensagem "status HTTP desconhecido" :corpo body))
        ((>= status 400)
         (error 'api-error :status status
                           :mensagem "requisição rejeitada pela API"
                           :corpo (subseq body 0 (min 1500 (length body)))))
        (t (parse-chat-response body))))))

;;; ---------------------------------------------------------------------------
;;; Loop agêntico
;;; ---------------------------------------------------------------------------

(defun execute-tool-calls (tool-calls)
  "Executa cada tool call e retorna uma lista de mensagens role:tool."
  (loop for tc across tool-calls
        for id = (json-get tc "id")
        for name = (json-get (json-get tc "function") "name")
        for resultado = (executar-tool-call tc)
        collect (make-message "tool" resultado
                              :tool-call-id id
                              :name name)))

(defun strip-system (messages)
  "Remove a mensagem de sistema antes de persistir."
  (remove-if (lambda (m)
               (and (hash-table-p m)
                    (equal (json-get m "role") "system")))
             messages))

(defun run-loop (config messages &key (verbose t))
  "Executa o loop de tool calling sobre MESSAGES (lista).
   Retorna (values texto-final messages-atualizadas)."
  (loop repeat (config-max-tool-iterations config)
        do (multiple-value-bind (message finish-reason)
               (request-chat config (coerce messages 'vector))
             (declare (ignore finish-reason))
             (let ((content (json-get message "content"))
                   (tool-calls (json-get message "tool_calls")))
               (if (and tool-calls (plusp (length tool-calls)))
                   (progn
                     (setf messages (append messages (list message)))
                     (let ((resultados (execute-tool-calls tool-calls)))
                       (when verbose
                         (loop for tc across tool-calls
                               for name = (json-get (json-get tc "function") "name")
                               do (format *error-output* "  → tool: ~a~%" name)))
                       (setf messages (append messages resultados))))
                   (return-from run-loop
                     (values (or content "")
                             (append messages
                                     (list (make-message "assistant" (or content ""))))))))))
  (error 'nim-error
         :mensagem (format nil "limite de ~a iterações de ferramenta atingido."
                           (config-max-tool-iterations config))))

(defun run-conversation (config session user-input &key (verbose t))
  "Envia USER-INPUT, executa o loop de tool calling e retorna o texto final.
   Persiste a sessão ao final."
  (let* ((messages (append (system-messages config)
                           (nim-session-messages session)
                           (list (make-message "user" user-input)))))
    (multiple-value-bind (final updated)
        (run-loop config messages :verbose verbose)
      (setf (nim-session-messages session) (strip-system updated))
      (save-session session)
      final)))
