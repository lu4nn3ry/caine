;;;; ============================================================================
;;;; config.lisp — API key, configuração e persistência
;;;; ============================================================================
;;;; Layout em disco (padrão ~/.caine/nim/, sobrescrito por CAINE_NIM_HOME):
;;;;
;;;;   config.json        configuração (base_url, model, temperature, ...)
;;;;   key                API key da NVIDIA (chmod 600)
;;;;   last-session       id da última sessão usada
;;;;   sessions/<id>.json histórico de conversa persistido
;;;;
;;;; Ordem de resolução da API key:
;;;;   1. NVIDIA_API_KEY (env)
;;;;   2. NIM_API_KEY    (env)
;;;;   3. arquivo ~/.caine/nim/key
;;;; ============================================================================

(in-package :caine.nim)

;;; ---------------------------------------------------------------------------
;;; Caminhos
;;; ---------------------------------------------------------------------------

(defun caine-nim-home ()
  "Diretório de estado do caine-nim."
  (uiop:ensure-directory-pathname
   (or (uiop:getenv "CAINE_NIM_HOME")
       (namestring (merge-pathnames ".caine/nim/" (user-homedir-pathname))))))

(defun config-path () (merge-pathnames "config.json" (caine-nim-home)))
(defun key-path () (merge-pathnames "key" (caine-nim-home)))
(defun sessions-dir () (merge-pathnames "sessions/" (caine-nim-home)))
(defun last-session-path () (merge-pathnames "last-session" (caine-nim-home)))

(defun ensure-home ()
  "Garante que os diretórios de estado existem."
  (ensure-directories-exist (caine-nim-home))
  (ensure-directories-exist (sessions-dir))
  (caine-nim-home))

;;; ---------------------------------------------------------------------------
;;; I/O de arquivos
;;; ---------------------------------------------------------------------------

(defun file->string (path)
  "Lê PATH como UTF-8. Retorna NIL se não existir."
  (when (probe-file path)
    (uiop:read-file-string path :external-format :utf-8)))

(defun string->file (path text)
  "Escreve TEXT em PATH (UTF-8), criando diretórios."
  (ensure-directories-exist path)
  (with-open-file (out path
                       :direction :output
                       :if-exists :supersede
                       :if-does-not-exist :create
                       :external-format :utf-8)
    (write-string text out))
  path)

;;; ---------------------------------------------------------------------------
;;; Configuração
;;; ---------------------------------------------------------------------------

(defparameter *default-system-prompt*
  "Você é Caine, um editor e produtor de música profissional. Ajuda a compor, arranjar, mixar, masterizar e editar áudio em nível de nota com precisão de estúdio. Responda em português, de forma direta, técnica e prática.")

(defun default-config-table ()
  "Configuração padrão."
  (make-json-object
   "base_url" "https://integrate.api.nvidia.com/v1"
   "model" "meta/llama-3.3-70b-instruct"
   "system" *default-system-prompt*
   "max_tokens" 4096
   "temperature" 0.6
   "timeout" 180
   "max_tool_iterations" 8
   "tools_enabled" t
   "allow_shell" t))

(defun load-config ()
  "Carrega config.json, mesclando com os padrões."
  (let ((defaults (default-config-table)))
    (let ((raw (file->string (config-path))))
      (when raw
        (handler-case
            (let ((parsed (json-parse raw)))
              (when (hash-table-p parsed)
                (maphash (lambda (k v) (setf (gethash k defaults) v)) parsed)))
          (json-error () nil))))
    defaults))

(defun save-config (config)
  "Persiste CONFIG em config.json."
  (string->file (config-path) (json-encode config)))

(defun config-bool (config key default)
  "Lê um booleano JSON com fallback DEFAULT."
  (multiple-value-bind (v present) (gethash key config)
    (cond ((not present) default)
          ((eq v t) t)
          ((eq v :false) nil)
          ((null v) default)
          (t (not (null v))))))

(defun config-base-url (config)
  (json-get config "base_url" "https://integrate.api.nvidia.com/v1"))
(defun config-model (config)
  (json-get config "model" "meta/llama-3.3-70b-instruct"))
(defun config-system (config)
  (json-get config "system" *default-system-prompt*))
(defun config-max-tokens (config) (json-get config "max_tokens" 4096))
(defun config-temperature (config) (json-get config "temperature" 0.6))
(defun config-timeout (config) (json-get config "timeout" 180))
(defun config-max-tool-iterations (config)
  (json-get config "max_tool_iterations" 8))
(defun config-tools-enabled-p (config)
  (config-bool config "tools_enabled" t))
(defun config-allow-shell-p (config)
  (config-bool config "allow_shell" t))

;;; ---------------------------------------------------------------------------
;;; API key
;;; ---------------------------------------------------------------------------

(defun read-key-file ()
  "Lê a chave do arquivo, ignorando linhas vazias."
  (let ((s (file->string (key-path))))
    (when s
      (let ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) s)))
        (unless (string= trimmed "") trimmed)))))

(defun resolve-api-key ()
  "Resolve a API key na ordem env → env → arquivo."
  (or (let ((v (uiop:getenv "NVIDIA_API_KEY")))
        (and v (plusp (length v)) v))
      (let ((v (uiop:getenv "NIM_API_KEY")))
        (and v (plusp (length v)) v))
      (read-key-file)))

(defun key-present-p () (not (null (resolve-api-key))))

(defun save-api-key (key)
  "Salva a API key com permissão 600."
  (when (or (null key)
            (string= (string-trim '(#\Space #\Tab #\Newline #\Return) key) ""))
    (error 'config-error :mensagem "chave vazia."))
  (ensure-home)
  (let ((clean (string-trim '(#\Space #\Tab #\Newline #\Return) key)))
    (string->file (key-path) clean)
    (ignore-errors
      (uiop:run-program (list "chmod" "600" (namestring (key-path)))
                        :output nil :error-output nil :ignore-error-status t))
    (key-path)))

(defun clear-api-key ()
  "Remove o arquivo de chave. Retorna T se removeu."
  (let ((p (key-path)))
    (when (probe-file p)
      (delete-file p)
      t)))

(defun api-key-mask ()
  "Máscara da chave atual, ex.: `nvapi…abcd`."
  (let ((k (resolve-api-key)))
    (when k
      (if (> (length k) 8)
          (format nil "~a…~a" (subseq k 0 4) (subseq k (- (length k) 4)))
          "****"))))

;;; ---------------------------------------------------------------------------
;;; Sessões (persistência de conversa)
;;; ---------------------------------------------------------------------------

(defstruct (nim-session (:constructor %make-nim-session))
  (id "" :type string)
  (created 0)
  (updated 0)
  (model "" :type string)
  (messages '() :type list))

(defun new-session (&key (model ""))
  "Cria uma sessão nova (não persistida até SAVE-SESSION)."
  (let ((id (format nil "~a-~6,'0x" (get-universal-time) (random #x1000000))))
    (%make-nim-session :id id
                       :created (get-universal-time)
                       :updated (get-universal-time)
                       :model model)))

(defun session-file (id)
  (merge-pathnames (format nil "~a.json" id) (sessions-dir)))

(defun save-session (session)
  "Persiste SESSION e atualiza o ponteiro de última sessão."
  (ensure-home)
  (setf (nim-session-updated session) (get-universal-time))
  (string->file (session-file (nim-session-id session))
                (json-encode
                 (make-json-object
                  "id" (nim-session-id session)
                  "created" (nim-session-created session)
                  "updated" (nim-session-updated session)
                  "model" (nim-session-model session)
                  "messages" (coerce (nim-session-messages session) 'vector))))
  (string->file (last-session-path) (nim-session-id session))
  session)

(defun load-session (id)
  "Carrega uma sessão persistida por ID."
  (let ((raw (file->string (session-file id))))
    (unless raw
      (error 'config-error :mensagem (format nil "sessão '~a' não encontrada." id)))
    (let* ((obj (json-parse raw))
           (msgs (json-get obj "messages")))
      (%make-nim-session
       :id (json-get obj "id" id)
       :created (json-get obj "created" 0)
       :updated (json-get obj "updated" 0)
       :model (json-get obj "model" "")
       :messages (if (vectorp msgs) (coerce msgs 'list) '())))))

(defun list-sessions ()
  "Lista sessões persistidas, mais recentes primeiro."
  (let ((dir (sessions-dir))
        (acc '()))
    (when (probe-file dir)
      (dolist (f (directory (merge-pathnames "*.json" dir)))
        (handler-case
            (let* ((obj (json-parse (uiop:read-file-string f :external-format :utf-8)))
                   (msgs (json-get obj "messages")))
              (push (list :id (json-get obj "id" (pathname-name f))
                          :updated (json-get obj "updated" 0)
                          :model (json-get obj "model" "")
                          :messages (if (vectorp msgs) (length msgs) 0))
                    acc))
          (error () nil))))
    (sort acc #'> :key (lambda (s) (getf s :updated)))))

(defun delete-session (id)
  "Remove a sessão ID. Retorna T se removeu."
  (let ((p (session-file id)))
    (when (probe-file p)
      (delete-file p)
      t)))

(defun last-session-id ()
  "Id da última sessão usada, se houver."
  (let ((s (file->string (last-session-path))))
    (when s
      (let ((trimmed (string-trim '(#\Space #\Newline #\Return #\Tab) s)))
        (unless (string= trimmed "") trimmed)))))
