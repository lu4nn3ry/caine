;;;; ============================================================================
;;;; http.lisp — Cliente HTTP via curl (uiop:run-program)
;;;; ============================================================================
;;;; Encapsula chamadas HTTP sem depender de bibliotecas externas de rede.
;;;; O curl é invocado diretamente (argv, sem shell), evitando injeção.
;;;; ============================================================================

(in-package :caine.nim)

(defvar *curl* "curl"
  "Executável curl usado para as requisições.")

(defun http-request (url &key (method "GET") headers body (timeout 180))
  "Executa uma requisição HTTP via curl.
   Retorna (values corpo status-code).
   Sinaliza HTTP-ERROR se o curl falhar no transporte."
  (let* ((args (list *curl* "-sS" "-X" method
                     "--max-time" (princ-to-string timeout)
                     "-w" (format nil "~%__CAINE_STATUS__%{http_code}")))
         (args (append args
                       (loop for (k . v) in headers
                             append (list "-H" (format nil "~a: ~a" k v)))))
         (args (append args
                       (when body (list "--data-binary" body))
                       (list url))))
    (multiple-value-bind (stdout stderr code)
        (uiop:run-program args
                          :output :string
                          :error-output :string
                          :ignore-error-status t)
      (when (or (null code) (/= code 0))
        (error 'http-error
               :status code
               :mensagem (format nil "curl falhou (exit ~a): ~a"
                                 code
                                 (string-trim '(#\Newline #\Space)
                                              (or stderr "")))))
      (let* ((marker "__CAINE_STATUS__")
             (pos (search marker stdout :from-end t)))
        (if pos
            (values (string-right-trim '(#\Newline) (subseq stdout 0 pos))
                    (parse-integer (subseq stdout (+ pos (length marker)))
                                   :junk-allowed t))
            (values stdout nil))))))

(defun http-headers (api-key)
  "Monta a alist de headers comuns, incluindo Authorization se API-KEY."
  (let ((headers (list (cons "Content-Type" "application/json")
                       (cons "Accept" "application/json"))))
    (when api-key
      (push (cons "Authorization" (format nil "Bearer ~a" api-key)) headers))
    headers))

(defun http-post-json (url payload &key api-key (timeout 180))
  "POST de PAYLOAD (string JSON) em URL."
  (http-request url
                :method "POST"
                :headers (http-headers api-key)
                :body payload
                :timeout timeout))

(defun http-get (url &key api-key (timeout 60))
  "GET em URL."
  (http-request url
                :method "GET"
                :headers (http-headers api-key)
                :timeout timeout))
