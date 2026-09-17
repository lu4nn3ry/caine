;;;; ============================================================================
;;;; framework.lisp — Micro-framework de testes unitários para o Caine
;;;; ============================================================================
;;;; Não depende de Quicklisp nem FiveAM; funciona offline em qualquer SBCL.
;;;; ============================================================================

(defpackage :caine.test-framework
  (:use :cl)
  (:export
   #:*tests*
   #:*passes*
   #:*failures*
   #:deftest
   #:assert-true
   #:assert-false
   #:assert-equal
   #:assert-string=
   #:assert-error
   #:run-all-tests
   #:reset-tests))

(in-package :caine.test-framework)

(defvar *tests* '() "Lista de funções de teste registradas (em ordem).")
(defvar *passes* 0 "Contador de asserções bem-sucedidas.")
(defvar *failures* 0 "Contador de falhas.")
(defvar *current-test* nil "Nome do teste em execução.")

(defun reset-tests ()
  (setf *tests* '()
        *passes* 0
        *failures* 0
        *current-test* nil))

(defmacro deftest (name &body body)
  "Define e registra uma função de teste."
  `(progn
     (defun ,name ()
       (let ((*current-test* ',name))
         (format t "  [TEST] ~a... " ',name)
         (force-output)
         (handler-case
             (progn
               ,@body
               (format t "OK~%"))
           (error (e)
             (incf *failures*)
             (format t "FAIL!~%    Erro inesperado: ~a~%" e)
             (sb-debug:print-backtrace :count 12)))))
     (unless (member ',name *tests*)
       (setf *tests* (append *tests* (list ',name))))
     ',name))

(defun fail-assertion (msg expected actual)
  (incf *failures*)
  (format t "~%    [FALHA em ~a] ~a~%      Esperado: ~s~%      Obtido:   ~s~%"
          *current-test* msg expected actual))

(defmacro assert-true (expr &optional (msg "Expressão deveria ser verdadeira"))
  (let ((val (gensym "VAL")))
    `(let ((,val ,expr))
       (if ,val
           (incf *passes*)
           (fail-assertion ,msg t ,val)))))

(defmacro assert-false (expr &optional (msg "Expressão deveria ser falsa"))
  (let ((val (gensym "VAL")))
    `(let ((,val ,expr))
       (if (not ,val)
           (incf *passes*)
           (fail-assertion ,msg nil ,val)))))

(defmacro assert-equal (expected actual &key (test '#'equal) (msg "Valores diferem"))
  (let ((exp (gensym "EXP"))
        (act (gensym "ACT")))
    `(let ((,exp ,expected)
           (,act ,actual))
       (if (funcall ,test ,exp ,act)
           (incf *passes*)
           (fail-assertion ,msg ,exp ,act)))))

(defmacro assert-string= (expected actual &optional (msg "Strings diferem"))
  `(assert-equal ,expected ,actual :test #'string= :msg ,msg))

(defmacro assert-error (expr &optional (msg "Deveria ter sinalizado erro"))
  `(let ((errou nil))
     (handler-case ,expr
       (error () (setf errou t)))
     (if errou
         (incf *passes*)
         (fail-assertion ,msg "ERROR" "nenhum erro sinalizado"))))

(defun run-all-tests ()
  "Executa todos os testes registrados e retorna T se todos passaram."
  (setf *passes* 0
        *failures* 0)
  (format t "~%==================================================~%")
  (format t "  Executando Suíte de Testes Caine (~d testes)~%" (length *tests*))
  (format t "==================================================~%")
  (dolist (test-fn *tests*)
    (funcall test-fn))
  (format t "--------------------------------------------------~%")
  (format t "  Resultado: ~d asserções OK, ~d falhas~%" *passes* *failures*)
  (format t "==================================================~%~%")
  (zerop *failures*))
