;;;; ============================================================================
;;;; run-tests.lisp — Executor mestre da suíte de testes do Caine
;;;; ============================================================================
;;;; Executar com:
;;;;   sbcl --script tests/run-tests.lisp
;;;;   wsl sbcl --script tests/run-tests.lisp
;;;; ============================================================================

(in-package :cl-user)

(require :asdf)

(defparameter *base-dir*
  (let ((dir (uiop:pathname-directory-pathname
              (or *load-truename* *compile-file-truename* (uiop:getcwd)))))
    (if (string-equal (car (last (pathname-directory dir))) "tests")
        (uiop:pathname-parent-directory-pathname dir)
        dir)))

(format t "Carregando componentes do Caine a partir de ~a...~%" *base-dir*)

;; 1. Subsistema Voice
(load (merge-pathnames "agent/voice/package.lisp" *base-dir*))
(load (merge-pathnames "agent/voice/config.lisp" *base-dir*))
(load (merge-pathnames "agent/voice/audio.lisp" *base-dir*))
(load (merge-pathnames "agent/voice/midi.lisp" *base-dir*))
(load (merge-pathnames "agent/voice/lyrics.lisp" *base-dir*))
(load (merge-pathnames "agent/voice/artists.lisp" *base-dir*))

;; 2. Módulo Mock
(load (merge-pathnames "mock/melody.lisp" *base-dir*))

;; 3. Framework e Testes
(load (merge-pathnames "tests/framework.lisp" *base-dir*))
(load (merge-pathnames "tests/test-lyrics.lisp" *base-dir*))
(load (merge-pathnames "tests/test-midi.lisp" *base-dir*))
(load (merge-pathnames "tests/test-artists.lisp" *base-dir*))

;; 4. Gerar arquivos mock em mock/
(caine.mock:gerar-arquivos-mock (merge-pathnames "mock/" *base-dir*))

;; 5. Executar suíte
(let ((sucesso (caine.test-framework:run-all-tests)))
  (uiop:quit (if sucesso 0 1)))

