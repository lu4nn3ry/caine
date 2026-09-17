;;;; ============================================================================
;;;; tools.lisp — Registro de ferramentas e tool calling
;;;; ============================================================================
;;;; Cada ferramenta tem nome, descrição, JSON Schema dos parâmetros e um
;;;; handler (lambda (args) → string). O formato do schema segue o protocolo
;;;; OpenAI `tools` aceito pela API NVIDIA NIM:
;;;;
;;;;   {"type":"function",
;;;;    "function":{"name":..., "description":..., "parameters":{...}}}
;;;;
;;;; Ferramentas built-in: read_file, write_file, list_dir, run_shell, http_get,
;;;; now. O shell pode ser desabilitado via config `allow_shell`.
;;;; ============================================================================

(in-package :caine.nim)

;;; ---------------------------------------------------------------------------
;;; Estrutura e registro
;;; ---------------------------------------------------------------------------

(defstruct nim-tool
  (nome "" :type string)
  (descricao "" :type string)
  (parametros nil)
  (handler nil))

(defvar *tools* (make-hash-table :test 'equal)
  "Registro nome→NIM-TOOL das ferramentas disponíveis.")

(defun limpar-tools ()
  "Remove todas as ferramentas registradas."
  (clrhash *tools*))

(defun registrar-tool (nome &key (descricao "") parametros handler)
  "Registra (ou substitui) uma ferramenta."
  (let ((tool (make-nim-tool :nome nome
                             :descricao descricao
                             :parametros parametros
                             :handler handler)))
    (setf (gethash nome *tools*) tool)
    tool))

(defun obter-tool (nome)
  (gethash nome *tools*))

(defun listar-tools ()
  "Ferramentas registradas, ordenadas por nome."
  (let ((acc '()))
    (maphash (lambda (k v) (declare (ignore k)) (push v acc)) *tools*)
    (sort acc #'string< :key #'nim-tool-nome)))

(defun tool->schema (tool)
  "Converte NIM-TOOL no schema de função do protocolo OpenAI."
  (make-json-object
   "type" "function"
   "function" (make-json-object
               "name" (nim-tool-nome tool)
               "description" (nim-tool-descricao tool)
               "parameters" (or (nim-tool-parametros tool)
                                (make-json-object
                                 "type" "object"
                                 "properties" (make-json-object))))))

(defun tools-schema-vector ()
  "Vetor com o schema de todas as ferramentas, para o campo `tools`."
  (let ((v (make-array 0 :adjustable t :fill-pointer 0)))
    (maphash (lambda (k tool)
               (declare (ignore k))
               (vector-push-extend (tool->schema tool) v))
             *tools*)
    (coerce v 'vector)))

;;; ---------------------------------------------------------------------------
;;; Helpers de schema
;;; ---------------------------------------------------------------------------

(defun params-schema (properties &optional required)
  "Monta um JSON Schema de objeto com PROPERTIES (hash) e REQUIRED (lista)."
  (make-json-object
   "type" "object"
   "properties" properties
   "required" (coerce (or required '()) 'vector)))

(defun string-prop (description)
  (make-json-object "type" "string" "description" description))

;;; ---------------------------------------------------------------------------
;;; Ferramentas built-in
;;; ---------------------------------------------------------------------------

(defun caine-voice-bin ()
  "Caminho do launcher caine-voice (override por CAINE_VOICE_BIN)."
  (or (uiop:getenv "CAINE_VOICE_BIN")
      (ignore-errors
        (namestring
         (asdf:system-relative-pathname "caine-nim" "../voice/caine-voice")))))

(defun registrar-tools-builtin (&key (allow-shell t))
  "Registra o conjunto padrão de ferramentas.
   ALLOW-SHELL controla a exposição de RUN_SHELL."
  (limpar-tools)

  (registrar-tool "caine_voice"
    :descricao "Aciona as ferramentas de voz e o pipeline de música do Caine (subcomandos: list, doctor, stems, convert, tts, mix, master, make, cover). Ex.: args=\"list\" ou args=\"make --inst x.mp3 --vocal y.wav --out faixa.wav\"."
    :parametros (params-schema
                 (make-json-object
                  "args" (string-prop "Argumentos para o caine-voice (sem o nome do programa)"))
                 '("args"))
    :handler (lambda (args)
               (let ((argline (json-get args "args"))
                     (bin (caine-voice-bin)))
                 (cond
                   ((null argline) "Erro: 'args' ausente.")
                   ((or (null bin) (not (probe-file bin)))
                    "Erro: caine-voice não encontrado (defina CAINE_VOICE_BIN).")
                   (t (multiple-value-bind (out err code)
                          (uiop:run-program
                           (list "/bin/sh" "-c"
                                 (format nil "exec ~s ~a" bin argline))
                           :output :string :error-output :string
                           :ignore-error-status t)
                        (format nil "exit_code: ~a~%stdout:~%~a~%stderr:~%~a"
                                code (or out "") (or err ""))))))))

  (registrar-tool "write_lyrics"
    :descricao "Gera uma letra estruturada (.lyrics) para uma música. Suporta personas de artista (caine, bubble, ragatha, scratch) e estilos variados. Se a API key NIM estiver configurada, gera via LLM com a persona injetada no system prompt; caso contrário, usa template local."
    :parametros (params-schema
                 (make-json-object
                  "theme" (string-prop "Tema ou assunto central da música")
                  "artist" (string-prop "Artista/persona opcional: 'caine', 'bubble', 'ragatha', 'scratch'")
                  "style" (string-prop "Estilo musical opcional: pop, rock, rap, balada, eletronica, mpb, forro")
                  "out_path" (string-prop "Caminho opcional para salvar o arquivo .lyrics"))
                 '("theme"))
    :handler (lambda (args)
               (let* ((theme (json-get args "theme"))
                      (artist (json-get args "artist"))
                      (style (or (json-get args "style") "pop"))
                      (out (or (json-get args "out_path")
                               (format nil "out/lyrics/~a-~a.lyrics"
                                       (or artist "default")
                                       (get-universal-time))))
                      (bin (caine-voice-bin))
                      (key (resolve-api-key)))
                 (cond
                   ((null theme) "Erro: 'theme' ausente.")
                   ((and key (plusp (length key)))
                    ;; Geração via NIM com a persona injetada
                    (handler-case
                        (let* ((sys-prompt
                                 (if (and artist (plusp (length artist)) bin (probe-file bin))
                                     (multiple-value-bind (p-out _e _c)
                                         (uiop:run-program
                                          (list "/bin/sh" "-c"
                                                (format nil "exec ~s artists prompt --artist ~s --theme ~s --style ~s"
                                                        bin artist theme style))
                                          :output :string :ignore-error-status t)
                                       (declare (ignore _e _c))
                                       (if (and p-out (plusp (length p-out)))
                                           (string-trim '(#\Space #\Newline #\Return) p-out)
                                           "Você é um compositor musical. Escreva letras no formato canônico .lyrics."))
                                     "Você é um compositor musical. Escreva letras estruturadas no formato canônico .lyrics com [Verse], [Chorus], etc."))
                               (cfg (load-config))
                               (msgs (list
                                      (make-message "system" sys-prompt)
                                      (make-message "user"
                                                    (format nil "Escreva uma canção completa no formato .lyrics sobre o tema '~a' no estilo '~a'."
                                                            theme style)))))
                          (setf (gethash "tools_enabled" (config-table cfg)) nil)
                          (multiple-value-bind (resp finish)
                              (request-chat cfg msgs)
                            (declare (ignore finish))
                            (let ((content (json-get resp "content")))
                              (if (and content (plusp (length content)))
                                  (progn
                                    (ensure-directories-exist out)
                                    (write-file-string out content)
                                    (format nil "Letra gerada com sucesso via NIM (~a) em ~a~%~a"
                                            (or artist "geral") out content))
                                  "Erro: modelo não retornou conteúdo."))))
                      (error (e)
                        ;; Fallback local se a chamada à API falhar
                        (if (and bin (probe-file bin))
                            (let ((cmd (if (and artist (plusp (length artist)))
                                           (format nil "artists write --artist ~s --theme ~s --out ~s"
                                                   artist theme out)
                                           (format nil "lyrics write --theme ~s --style ~s --out ~s"
                                                   theme style out))))
                              (multiple-value-bind (out-str err-str code)
                                  (uiop:run-program
                                   (list "/bin/sh" "-c" (format nil "exec ~s ~a" bin cmd))
                                   :output :string :error-output :string
                                   :ignore-error-status t)
                                (if (zerop code)
                                    (format nil "Aviso: NIM falhou (~a), fallback local usado.~%Letra salva em ~a~%~a"
                                            e out (or out-str ""))
                                    (format nil "Erro no NIM (~a) e no fallback local: ~a" e err-str))))
                            (format nil "Erro ao chamar NIM: ~a" e)))))
                   ((or (null bin) (not (probe-file bin)))
                    "Erro: caine-voice não encontrado (defina CAINE_VOICE_BIN).")
                   (t
                    ;; Fallback template local sem API key
                    (let ((cmd (if (and artist (plusp (length artist)))
                                   (format nil "artists write --artist ~s --theme ~s --out ~s"
                                           artist theme out)
                                   (format nil "lyrics write --theme ~s --style ~s --out ~s"
                                           theme style out))))
                      (multiple-value-bind (out-str err-str code)
                          (uiop:run-program
                           (list "/bin/sh" "-c"
                                 (format nil "exec ~s ~a" bin cmd))
                           :output :string :error-output :string
                           :ignore-error-status t)
                        (if (zerop code)
                            (format nil "Letra gerada via template local em ~a~%~a" out (or out-str ""))
                            (format nil "Erro ao gerar letra (code ~a):~%~a" code (or err-str out-str ""))))))))))

  (registrar-tool "edit_lyrics"
    :descricao "Edita uma letra de música existente (.lyrics) aplicando instruções ou refinamento."
    :parametros (params-schema
                 (make-json-object
                  "in_path" (string-prop "Caminho do arquivo .lyrics de entrada")
                  "instruction" (string-prop "Instrução de edição (ex: 'mais curta', 'mais direta', 'refrão duas vezes')")
                  "out_path" (string-prop "Caminho opcional de saída (sobrescreve in_path se omitido)"))
                 '("in_path" "instruction"))
    :handler (lambda (args)
               (let* ((in-path (json-get args "in_path"))
                      (instruction (json-get args "instruction"))
                      (out-path (or (json-get args "out_path") in-path))
                      (bin (caine-voice-bin)))
                 (cond
                   ((null in-path) "Erro: 'in_path' ausente.")
                   ((null instruction) "Erro: 'instruction' ausente.")
                   ((or (null bin) (not (probe-file bin)))
                    "Erro: caine-voice não encontrado (defina CAINE_VOICE_BIN).")
                   (t
                    (let ((cmd (format nil "lyrics edit --in ~s --out ~s --edit ~s"
                                       in-path out-path instruction)))
                      (multiple-value-bind (out-str err-str code)
                          (uiop:run-program
                           (list "/bin/sh" "-c"
                                 (format nil "exec ~s ~a" bin cmd))
                           :output :string :error-output :string
                           :ignore-error-status t)
                        (if (zerop code)
                            (format nil "Letra editada salva em ~a" out-path)
                            (format nil "Erro ao editar letra (code ~a):~%~a" code (or err-str out-str ""))))))))))

  (registrar-tool "read_file"
    :descricao "Lê e retorna o conteúdo de um arquivo de texto."
    :parametros (params-schema
                 (make-json-object "path" (string-prop "Caminho do arquivo"))
                 '("path"))
    :handler (lambda (args)
               (let ((path (json-get args "path")))
                 (cond
                   ((null path) "Erro: 'path' ausente.")
                   ((probe-file path)
                    (handler-case
                        (uiop:read-file-string path :external-format :utf-8)
                      (error (e) (format nil "Erro ao ler ~a: ~a" path e))))
                   (t (format nil "Arquivo não encontrado: ~a" path))))))

  (registrar-tool "write_file"
    :descricao "Escreve (ou sobrescreve) um arquivo de texto com o conteúdo dado."
    :parametros (params-schema
                 (make-json-object
                  "path" (string-prop "Caminho de destino")
                  "content" (string-prop "Conteúdo a escrever"))
                 '("path" "content"))
    :handler (lambda (args)
               (let ((path (json-get args "path"))
                     (content (or (json-get args "content") "")))
                 (cond
                   ((null path) "Erro: 'path' ausente.")
                   (t (handler-case
                          (progn
                            (ensure-directories-exist path)
                            (with-open-file (out path
                                                 :direction :output
                                                 :if-exists :supersede
                                                 :if-does-not-exist :create
                                                 :external-format :utf-8)
                              (write-string content out))
                            (format nil "OK: ~a caracteres escritos em ~a"
                                    (length content) path))
                        (error (e) (format nil "Erro ao escrever ~a: ~a" path e))))))))

  (registrar-tool "list_dir"
    :descricao "Lista arquivos e diretórios de um caminho."
    :parametros (params-schema
                 (make-json-object
                  "path" (string-prop "Diretório (padrão: diretório atual)")))
    :handler (lambda (args)
               (let ((path (or (json-get args "path") ".")))
                 (handler-case
                     (let ((dir (uiop:ensure-directory-pathname path)))
                       (if (probe-file dir)
                           (let ((entries (directory (merge-pathnames "*" dir))))
                             (if entries
                                 (format nil "~{~a~^~%~}"
                                         (mapcar #'namestring entries))
                                 "(vazio)"))
                           (format nil "Diretório não encontrado: ~a" path)))
                   (error (e) (format nil "Erro ao listar ~a: ~a" path e))))))

  (registrar-tool "http_get"
    :descricao "Faz um GET HTTP em uma URL e retorna status e corpo (truncado)."
    :parametros (params-schema
                 (make-json-object "url" (string-prop "URL completa (https://...)"))
                 '("url"))
    :handler (lambda (args)
               (let ((url (json-get args "url")))
                 (cond
                   ((null url) "Erro: 'url' ausente.")
                   (t (handler-case
                          (multiple-value-bind (body status) (http-get url)
                            (format nil "HTTP ~a~%~a"
                                    status
                                    (subseq body 0 (min 4000 (length body)))))
                        (error (e) (format nil "Erro HTTP: ~a" e))))))))

  (registrar-tool "now"
    :descricao "Retorna a data e hora atuais do sistema."
    :parametros (params-schema (make-json-object))
    :handler (lambda (args)
               (declare (ignore args))
               (multiple-value-bind (s m h d mo y) (get-decoded-time)
                 (format nil "~4,'0d-~2,'0d-~2,'0d ~2,'0d:~2,'0d:~2,'0d"
                         y mo d h m s))))

  (when allow-shell
    (registrar-tool "run_shell"
      :descricao "Executa um comando de shell (/bin/sh -c) e retorna exit code, stdout e stderr."
      :parametros (params-schema
                   (make-json-object
                    "command" (string-prop "Comando a executar via /bin/sh -c"))
                   '("command"))
      :handler (lambda (args)
                 (let ((cmd (json-get args "command")))
                   (cond
                     ((or (null cmd) (zerop (length cmd))) "Erro: 'command' ausente.")
                     (t (multiple-value-bind (out err code)
                            (uiop:run-program (list "/bin/sh" "-c" cmd)
                                              :output :string
                                              :error-output :string
                                              :ignore-error-status t)
                          (format nil "exit_code: ~a~%stdout:~%~a~%stderr:~%~a"
                                  code (or out "") (or err ""))))))))))

;;; ---------------------------------------------------------------------------
;;; Execução de um tool call vindo do modelo
;;; ---------------------------------------------------------------------------

(defun executar-tool-call (tool-call)
  "Executa um item de `tool_calls` da resposta e retorna a string de resultado."
  (let* ((function (json-get tool-call "function"))
         (name (json-get function "name"))
         (args-json (json-get function "arguments"))
         (tool (and name (obter-tool name))))
    (cond
      ((null tool)
       (format nil "Erro: ferramenta '~a' não registrada." name))
      (t (handler-case
             (let ((args (if (and (stringp args-json) (plusp (length args-json)))
                             (json-parse args-json)
                             (make-hash-table :test 'equal))))
               (let ((result (funcall (nim-tool-handler tool) args)))
                 (if (stringp result) result (format nil "~a" result))))
           (error (e)
             (format nil "Erro ao executar '~a': ~a" name e)))))))
