;;;; ============================================================================
;;;; package.lisp — Pacote e hierarquia de condições do caine-nim
;;;; ============================================================================

(in-package :cl-user)

(defpackage :caine.nim
  (:use :cl)
  (:export
   ;; entry point
   #:main
   #:run-once
   #:run-repl
   ;; config
   #:load-config
   #:save-config
   #:caine-nim-home
   #:config-base-url
   #:config-model
   #:config-system
   #:config-max-tokens
   #:config-temperature
   #:config-timeout
   #:config-max-tool-iterations
   #:config-tools-enabled-p
   #:config-allow-shell-p
   ;; key
   #:resolve-api-key
   #:save-api-key
   #:clear-api-key
   #:api-key-mask
   #:key-present-p
   ;; sessions
   #:new-session
   #:load-session
   #:save-session
   #:list-sessions
   #:delete-session
   #:session-id
   #:session-messages
   #:session-model
   ;; tools
   #:registrar-tool
   #:listar-tools
   #:registrar-tools-builtin
   #:nim-tool
   #:nim-tool-nome
   #:nim-tool-descricao
   #:nim-tool-parametros
   #:nim-tool-handler
   ;; json
   #:json-encode
   #:json-parse
   #:json-get
   #:json-put
   #:make-json-object
   ;; conditions
   #:nim-error
   #:json-error
   #:http-error
   #:api-error
   #:config-error))

(in-package :caine.nim)

;;; ---------------------------------------------------------------------------
;;; Condições (error hierarchy)
;;; ---------------------------------------------------------------------------

(define-condition nim-error (error)
  ((mensagem :initarg :mensagem :reader nim-error-mensagem))
  (:documentation "Erro base do caine-nim.")
  (:report (lambda (c stream)
             (format stream "[caine-nim] ~a" (nim-error-mensagem c)))))

(define-condition json-error (nim-error) ()
  (:documentation "Falha de parsing/serialização JSON.")
  (:report (lambda (c stream)
             (format stream "[caine-nim/json] ~a" (nim-error-mensagem c)))))

(define-condition http-error (nim-error)
  ((status :initarg :status :initform nil :reader http-error-status))
  (:documentation "Falha de transporte HTTP.")
  (:report (lambda (c stream)
             (format stream "[caine-nim/http] ~@[HTTP ~a: ~]~a"
                     (http-error-status c) (nim-error-mensagem c)))))

(define-condition api-error (nim-error)
  ((status :initarg :status :initform nil :reader api-error-status)
   (corpo :initarg :corpo :initform nil :reader api-error-corpo))
  (:documentation "Erro retornado pela API NVIDIA NIM.")
  (:report (lambda (c stream)
             (format stream "[caine-nim/api] ~@[HTTP ~a: ~]~a~@[~%~a~]"
                     (api-error-status c) (nim-error-mensagem c)
                     (api-error-corpo c)))))

(define-condition config-error (nim-error) ()
  (:documentation "Configuração ausente ou inválida.")
  (:report (lambda (c stream)
             (format stream "[caine-nim/config] ~a" (nim-error-mensagem c)))))
