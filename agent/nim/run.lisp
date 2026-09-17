;;;; ============================================================================
;;;; run.lisp — Carregador standalone do caine-nim
;;;; ============================================================================
;;;; Uso: sbcl --script run.lisp [args...]
;;;; Carrega o sistema ASDF a partir do diretório deste arquivo e chama MAIN.
;;;; ============================================================================

(require :asdf)

(let* ((script (or *load-truename* *load-pathname*))
       (dir (make-pathname :name nil :type nil :version nil
                           :defaults script)))
  (pushnew dir asdf:*central-registry* :test #'equal))

(defun %exit (code)
  #+sbcl (sb-ext:exit :code code)
  #-sbcl code)

(handler-case
    (asdf:load-system "caine-nim")
  (error (e)
    (format *error-output* "falha ao carregar caine-nim: ~a~%" e)
    (%exit 70)))

(let ((main (or (find-symbol "MAIN" "CAINE.NIM")
                (progn
                  (format *error-output* "símbolo MAIN não encontrado.~%")
                  (%exit 70)))))
  (handler-case
      (%exit (or (funcall (symbol-function main) (uiop:command-line-arguments)) 0))
    (error (e)
      (format *error-output* "erro: ~a~%" e)
      (%exit 1))))
