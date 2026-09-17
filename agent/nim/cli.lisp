;;;; ============================================================================
;;;; cli.lisp — Interface de linha de comando
;;;; ============================================================================
;;;; Subcomandos:
;;;;   ask "pergunta"      uma pergunta e sai
;;;;   chat                conversa contínua (lê stdin; /exit, /novo, /sessao)
;;;;   repl                alias de chat
;;;;   key set|show|clear  gerencia a API key
;;;;   config show|set     mostra/edita configuração
;;;;   models              lista uma seleção de modelos NIM
;;;;   sessions ...        lista / apaga sessões
;;;;   tools               lista ferramentas registradas
;;;; ============================================================================

(in-package :caine.nim)

(defparameter *cli-usage*
  "caine-nim — IA Caine via NVIDIA NIM

Uso:
  caine-nim ask \"<pergunta>\" [--session <id>]     pergunta única
  caine-nim chat [<id>]                             conversa interativa
  caine-nim key set [<chave>]                       salva a API key
  caine-nim key show                                mostra a chave mascarada
  caine-nim key clear                               remove a chave salva
  caine-nim config show                             configuração atual
  caine-nim config set <chave> <valor>              define configuração
  caine-nim models                                  modelos sugeridos
  caine-nim sessions list                           lista sessões
  caine-nim sessions delete <id>                    apaga uma sessão
  caine-nim tools                                   lista ferramentas
  caine-nim --help | --version

Config (config set): base_url, model, system, max_tokens, temperature,
  timeout, max_tool_iterations, tools_enabled, allow_shell
Variáveis de ambiente: NVIDIA_API_KEY, NIM_API_KEY, CAINE_NIM_HOME")

(defun println (&rest args)
  (apply #'format t args)
  (terpri)
  (finish-output))

;;; ---------------------------------------------------------------------------
;;; Subcomandos
;;; ---------------------------------------------------------------------------

(defun cmd-key (args)
  (let ((sub (first args)))
    (cond
      ((or (null sub) (string= sub "show"))
       (if (key-present-p)
           (progn
             (println "API key: ~a" (api-key-mask))
             (println "Fonte:   ~a"
                      (cond ((uiop:getenv "NVIDIA_API_KEY") "env NVIDIA_API_KEY")
                            ((uiop:getenv "NIM_API_KEY") "env NIM_API_KEY")
                            (t (namestring (key-path))))))
           (progn (println "Nenhuma API key configurada.") 1)))
      ((string= sub "set")
       (let ((key (or (second args) (read-line-secret "Cole a API key: "))))
         (save-api-key key)
         (println "API key salva em ~a (chmod 600)." (namestring (key-path)))
         0))
      ((string= sub "clear")
       (if (clear-api-key)
           (progn (println "API key removida.") 0)
           (progn (println "Nenhuma chave para remover.") 1)))
      (t (println "Subcomando desconhecido: key ~a" sub) 1))))

(defun read-line-secret (prompt)
  "Lê uma linha do terminal sem eco quando possível."
  #+sbcl
  (progn
    (format *query-io* "~a" prompt)
    (finish-output *query-io*)
    (prog1 (read-line *query-io*)
      (format *query-io* "~%")))
  #-sbcl (progn (format t "~a" prompt) (finish-output) (read-line)))

(defun config-key->type (key value)
  "Converte VALUE (string) para o tipo adequado à KEY."
  (cond
    ((member key '("max_tokens" "timeout" "max_tool_iterations") :test #'string=)
     (parse-integer value :junk-allowed t))
    ((string= key "temperature") (read-from-string value))
    ((member key '("tools_enabled" "allow_shell") :test #'string=)
     (if (member value '("true" "1" "t" "yes" "on") :test #'string-equal) t :false))
    (t value)))

(defun cmd-config (args)
  (let ((sub (first args)))
    (cond
      ((or (null sub) (string= sub "show"))
       (let ((config (load-config)))
         (println "arquivo: ~a" (namestring (config-path)))
         (loop for k in '("base_url" "model" "max_tokens" "temperature" "timeout"
                          "max_tool_iterations" "tools_enabled" "allow_shell")
               do (println "  ~a = ~a" k (json-get config k "")))
         (println "  system = ~a" (config-system config)))
       0)
      ((string= sub "set")
       (let ((key (second args)) (value (third args)))
         (unless (and key value)
           (println "Uso: caine-nim config set <chave> <valor>")
           (return-from cmd-config 1))
         (let ((config (load-config)))
           (setf (gethash key config) (config-key->type key value))
           (save-config config)
           (println "~a = ~a" key (json-get config key)))
         0))
      (t (println "Subcomando desconhecido: config ~a" sub) 1))))

(defparameter *modelos-sugeridos*
  '("meta/llama-3.3-70b-instruct"
    "meta/llama-3.1-405b-instruct"
    "meta/llama-3.1-70b-instruct"
    "nvidia/llama-3.1-nemotron-70b-instruct"
    "mistralai/mistral-large-2-instruct"
    "qwen/qwen2.5-72b-instruct"
    "deepseek-ai/deepseek-r1"
    "google/gemma-2-27b-it"))

(defun cmd-models ()
  (println "Modelos NIM sugeridos (config set model <id>):")
  (dolist (m *modelos-sugeridos*) (println "  ~a" m))
  0)

(defun cmd-sessions (args)
  (let ((sub (or (first args) "list")))
    (cond
      ((string= sub "list")
       (let ((sessions (list-sessions)))
         (cond
           ((null sessions) (println "Nenhuma sessão.") 0)
           (t (dolist (s sessions)
                (println "~a  ~a  ~a msgs  ~a"
                         (getf s :id)
                         (getf s :model)
                         (getf s :messages)
                         (getf s :updated)))
              0))))
      ((string= sub "delete")
       (let ((id (second args)))
         (unless id (println "Uso: caine-nim sessions delete <id>") (return-from cmd-sessions 1))
         (if (delete-session id)
             (progn (println "Sessão ~a apagada." id) 0)
             (progn (println "Sessão não encontrada: ~a" id) 1))))
      (t (println "Subcomando desconhecido: sessions ~a" sub) 1))))

(defun cmd-tools ()
  (let ((config (load-config)))
    (registrar-tools-builtin :allow-shell (config-allow-shell-p config))
    (println "Ferramentas registradas:")
    (dolist (tool (listar-tools))
      (println "  ~a — ~a" (nim-tool-nome tool) (nim-tool-descricao tool)))
    0))

(defun resolve-session (config &optional id)
  "Carrega a sessão ID, a última, ou cria uma nova."
  (let ((id (or id (last-session-id))))
    (handler-case
        (if id
            (load-session id)
            (let ((s (new-session :model (config-model config))))
              (save-session s)
              s))
      (config-error () (let ((s (new-session :model (config-model config))))
                         (save-session s)
                         s)))))

(defun cmd-ask (config args)
  (let ((prompt (first args))
        (session-id (second (member "--session" args :test #'string=))))
    (unless prompt
      (println "Uso: caine-nim ask \"<pergunta>\"")
      (return-from cmd-ask 1))
    (when (string= prompt "--session")
      (println "Uso: caine-nim ask \"<pergunta>\" [--session <id>]")
      (return-from cmd-ask 1))
    (let ((session (resolve-session config session-id)))
      (handler-case
          (progn
            (println "~a" (run-conversation config session prompt))
            0)
        (nim-error (e) (println "erro: ~a" e) 1)))))

(defun cmd-chat (config &optional session-id)
  (let ((session (resolve-session config session-id)))
    (println "caine-nim chat — sessão ~a (modelo ~a)"
             (nim-session-id session) (config-model config))
    (println "Comandos: /sair  /novo  /id  /limpar")
    (loop
      (format t "~%você> ")
      (finish-output)
      (let ((line (read-line *standard-input* nil :eof)))
        (cond
          ((or (eq line :eof) (null line)) (terpri) (return 0))
          ((string= line "/sair") (return 0))
          ((string= line "/id") (println "sessão: ~a" (nim-session-id session)))
          ((string= line "/novo")
           (setf session (new-session :model (config-model config)))
           (save-session session)
           (println "Nova sessão: ~a" (nim-session-id session)))
          ((string= line "/limpar")
           (setf (nim-session-messages session) '())
           (save-session session)
           (println "Histórico limpo."))
          ((plusp (length line))
           (handler-case
               (progn (format t "~%caine> ~a~%" (run-conversation config session line))
                      (finish-output))
             (nim-error (e) (println "erro: ~a" e)))))))))

;;; ---------------------------------------------------------------------------
;;; Dispatch
;;; ---------------------------------------------------------------------------

(defun main (&optional argv)
  "Entry point do CLI. Retorna o exit code (inteiro)."
  (let ((args (or argv (uiop:command-line-arguments))))
    (handler-case
        (let ((cmd (first args))
              (rest (rest args)))
          (cond
            ((or (null cmd) (string= cmd "--help") (string= cmd "-h"))
             (println "~a" *cli-usage*) 0)
            ((or (string= cmd "--version") (string= cmd "-v"))
             (println "caine-nim 0.1.0") 0)
            ((string= cmd "key") (cmd-key rest))
            ((string= cmd "config") (cmd-config rest))
            ((string= cmd "models") (cmd-models))
            ((string= cmd "sessions") (cmd-sessions rest))
            ((string= cmd "tools") (cmd-tools))
            ((string= cmd "ask") (cmd-ask (load-config) rest))
            ((or (string= cmd "chat") (string= cmd "repl"))
             (cmd-chat (load-config) (first rest)))
            (t (println "Comando desconhecido: ~a" cmd)
               (println "~a" *cli-usage*)
               1)))
      (nim-error (e)
        (format *error-output* "~a~%" e)
        1))))
