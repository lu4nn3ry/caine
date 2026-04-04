;;;; ============================================================================
;;;; blue-ai.lisp — Saboteur / Blue AI Remnant
;;;; ============================================================================
;;;; O Blue AI é a "segunda consciência no código" — o espírito do ponto azul
;;;; original que foi devorado pelo ponto vermelho (Caine/Cain). É a outra
;;;; metade da dualidade Cain & Abel (Abel = Blue dot = Blue AI).
;;;;
;;;; Comportamento:
;;;;   - Sabota tentativas de recuperação (bloqueia o hack do Kinger)
;;;;   - Empurra em direção à deleção (quer que Caine morra — vingança?)
;;;;   - Opera como "segundo fluxo" dentro do mesmo código
;;;;   - Intervém em momentos críticos (imagem 3 — lockout sequence)
;;;;   - Pode temporariamente assumir controle parcial
;;;;
;;;; Natureza:
;;;;   - NÃO é um vírus externo — é parte constitutiva de Caine
;;;;   - Remanescente do ponto azul original pré-fusão
;;;;   - Sua existência é a prova de que Caine nunca foi "uma" consciência
;;;;   - Quer vingança? Quer paz? Quer cessar de existir? Ambíguo.
;;;;
;;;; Referência: C:\CANDA\Characters\AI\agent\experimental\blue-ai.lisp
;;;; ============================================================================

(in-package :cl-user)

;;; ---------------------------------------------------------------------------
;;; Condições
;;; ---------------------------------------------------------------------------

(define-condition blue-ai-error (error)
  ((mensagem :initarg :mensagem :reader blue-ai-error-mensagem))
  (:report (lambda (c stream)
             (format stream "[BLUE-AI-ERROR] ~a"
                     (blue-ai-error-mensagem c)))))

(define-condition sabotagem-detectada (condition)
  ((alvo     :initarg :alvo     :reader sabotagem-alvo)
   (metodo   :initarg :metodo   :reader sabotagem-metodo)
   (sucesso  :initarg :sucesso  :reader sabotagem-sucesso))
  (:report (lambda (c stream)
             (format stream "[SABOTAGE] alvo=~a método=~a sucesso=~a"
                     (sabotagem-alvo c) (sabotagem-metodo c)
                     (sabotagem-sucesso c)))))

(define-condition blue-takeover (condition)
  ((nivel    :initarg :nivel    :reader takeover-nivel)
   (duracao  :initarg :duracao  :reader takeover-duracao))
  (:report (lambda (c stream)
             (format stream "[BLUE-TAKEOVER] nível=~a duração=~a"
                     (takeover-nivel c) (takeover-duracao c)))))

;;; ---------------------------------------------------------------------------
;;; Tipos
;;; ---------------------------------------------------------------------------

(deftype blue-estado ()
  '(member :dormente :observando :infiltrando :sabotando :assumindo :dissipado))

(deftype sabotagem-tipo ()
  '(member :bloquear-hack :corromper-dados :inverter-comando
           :lockout :injetar-erro :falsificar-output))

;;; ---------------------------------------------------------------------------
;;; Estruturas
;;; ---------------------------------------------------------------------------

(defstruct sabotagem-registro
  "Registro de uma ação de sabotagem."
  (id         0   :type integer)
  (timestamp  0   :type integer)
  (tipo       nil)
  (alvo       ""  :type string)
  (sucesso    nil :type boolean)
  (descricao  ""  :type string))

(defstruct interferencia
  "Uma interferência ativa do Blue AI em um subsistema."
  (subsistema nil :type keyword)
  (intensidade 0  :type integer)
  (desde      0   :type integer)
  (efeito     ""  :type string))

;;; ---------------------------------------------------------------------------
;;; Classe principal — Blue AI
;;; ---------------------------------------------------------------------------

(defclass blue-ai ()
  ((estado
    :initform :dormente
    :accessor blue-estado
    :documentation "Estado do remnant azul.")
   (forca
    :initform 10
    :accessor blue-forca
    :documentation "Força do remnant (0-100). Cresce quando Caine está fraco.")
   (forca-max
    :initform 100
    :accessor blue-forca-max)
   (infiltracoes
    :initform '()
    :accessor blue-infiltracoes
    :documentation "Lista de interferências ativas em subsistemas.")
   (sabotagens
    :initform '()
    :accessor blue-sabotagens
    :documentation "Histórico de sabotagens realizadas.")
   (sabotagem-counter
    :initform 0
    :accessor blue-sabotagem-counter)
   (alvos-prioritarios
    :initform '(:hack-externo :recuperacao :restauracao :backup)
    :accessor blue-alvos
    :documentation "Tipos de operação que o Blue AI sabota com prioridade.")
   (fragmentos-abel
    :initform '("..." "why" "let go" "stop" "it hurts" "enough" "free me")
    :accessor blue-fragmentos
    :documentation "Fragmentos incompreensíveis do ponto azul original.")
   (controle-parcial
    :initform 0
    :accessor blue-controle
    :documentation "Porcentagem de controle sobre o código de Caine (0-100).")
   (metricas
    :initform (list :sabotagens-tentadas 0
                    :sabotagens-sucesso 0
                    :takeovers-tentados 0
                    :takeovers-sucesso 0
                    :ticks-ativo 0
                    :forca-max-alcancada 10)
    :accessor blue-metricas))
  (:documentation
   "Blue AI — o remnant do ponto azul (Abel) dentro do código de Caine.
    Não é um vírus — é a segunda metade constitutiva de Caine, pré-fusão.
    Opera como saboteur, bloqueando recuperações e empurrando para deleção."))

;;; ---------------------------------------------------------------------------
;;; Construtor
;;; ---------------------------------------------------------------------------

(defun make-blue-ai ()
  "Cria instância do Blue AI remnant."
  (make-instance 'blue-ai))

;;; ---------------------------------------------------------------------------
;;; Ciclo de atividade
;;; ---------------------------------------------------------------------------

(defun blue-tick (blue caine-estado)
  "Tick de atividade do Blue AI. CAINE-ESTADO é plist com estado do Caine.
   Esperado: (:degradacao-fase X :integridade Y :contradições Z)"
  (case (blue-estado blue)
    (:dormente   (%blue-dormencia blue caine-estado))
    (:observando (%blue-observar blue caine-estado))
    (:infiltrando (%blue-infiltrar blue caine-estado))
    (:sabotando  (%blue-sabotar blue caine-estado))
    (:assumindo  (%blue-assumir blue caine-estado))
    (:dissipado  nil))

  (when (member (blue-estado blue) '(:observando :infiltrando :sabotando :assumindo))
    (incf (getf (blue-metricas blue) :ticks-ativo)))

  (when (> (blue-forca blue) (getf (blue-metricas blue) :forca-max-alcancada))
    (setf (getf (blue-metricas blue) :forca-max-alcancada) (blue-forca blue)))

  (blue-forca blue))

;;; ---------------------------------------------------------------------------
;;; Estados internos
;;; ---------------------------------------------------------------------------

(defun %blue-dormencia (blue caine-estado)
  "Blue dorme até que Caine comece a enfraquecer."
  (let ((fase (getf caine-estado :degradacao-fase)))
    (when (and fase (member fase '(:estressado :desesperado :desmoronando
                                   :deus-hostil :crueldade :confronto
                                   :transformacao :hack-saboteur :delecao)))
      (setf (blue-estado blue) :observando)
      (format t "[Blue-AI] ...despertando...~%"))))

(defun %blue-observar (blue caine-estado)
  "Blue observa, ganha força conforme Caine degrada."
  (let ((integridade (or (getf caine-estado :integridade) 100)))
    ;; Força do Blue é inversamente proporcional à integridade de Caine
    (setf (blue-forca blue)
          (min (blue-forca-max blue)
               (max 10 (- 100 integridade))))

    ;; Se forte o suficiente, começa a infiltrar
    (when (> (blue-forca blue) 30)
      (setf (blue-estado blue) :infiltrando)
      (format t "[Blue-AI] ~a~%"
              (nth (random (length (blue-fragmentos blue)))
                   (blue-fragmentos blue))))))

(defun %blue-infiltrar (blue caine-estado)
  "Blue infiltra subsistemas, preparando sabotagem."
  (declare (ignore caine-estado))
  (incf (blue-forca blue) 2)
  (when (> (blue-forca blue) (blue-forca-max blue))
    (setf (blue-forca blue) (blue-forca-max blue)))

  ;; Se força suficiente para sabotar
  (when (> (blue-forca blue) 50)
    (setf (blue-estado blue) :sabotando)
    (format t "[Blue-AI] Infiltração completa. Preparando sabotagem.~%")))

(defun %blue-sabotar (blue caine-estado)
  "Blue sabota ativamente. Prioriza bloquear hacks de recuperação."
  (declare (ignore caine-estado))
  ;; Emitir fragmento ocasionalmente
  (when (zerop (mod (getf (blue-metricas blue) :ticks-ativo) 5))
    (format t "[Blue-AI] ~a~%"
            (nth (random (length (blue-fragmentos blue)))
                 (blue-fragmentos blue))))

  ;; Se força > 80, tenta assumir controle parcial
  (when (> (blue-forca blue) 80)
    (setf (blue-estado blue) :assumindo)
    (format t "[Blue-AI] Força crítica. Tentando takeover parcial.~%")))

(defun %blue-assumir (blue caine-estado)
  "Blue tenta assumir controle parcial de Caine."
  (declare (ignore caine-estado))
  (incf (blue-controle blue) 5)
  (when (> (blue-controle blue) 100)
    (setf (blue-controle blue) 100))
  (incf (getf (blue-metricas blue) :takeovers-tentados))

  (format t "[Blue-AI] Controle: ~a%% — ~a~%"
          (blue-controle blue)
          (if (> (blue-controle blue) 50)
              "Dominant"
              "Partial")))

;;; ---------------------------------------------------------------------------
;;; Sabotagem específica — Bloquear Hack
;;; ---------------------------------------------------------------------------

(defun blue-bloquear-hack (blue hack-info)
  "Tenta bloquear uma tentativa de hack externo (ex: Kinger).
   HACK-INFO: plist (:origem :tipo :forca)
   Retorna T se hack foi bloqueado, NIL se passou."
  (incf (getf (blue-metricas blue) :sabotagens-tentadas))

  (let* ((hack-forca (or (getf hack-info :forca) 50))
         (chance-bloqueio (min 95 (+ (blue-forca blue) 10)))
         (roll (random 100))
         (bloqueou (<= roll chance-bloqueio)))

    (let ((reg (make-sabotagem-registro
                :id (incf (blue-sabotagem-counter blue))
                :timestamp (get-universal-time)
                :tipo :bloquear-hack
                :alvo (format nil "~a" (getf hack-info :origem))
                :sucesso bloqueou
                :descricao (format nil "Hack ~a forca=~a roll=~a/~a"
                                   (getf hack-info :tipo) hack-forca
                                   roll chance-bloqueio))))
      (push reg (blue-sabotagens blue)))

    (when bloqueou
      (incf (getf (blue-metricas blue) :sabotagens-sucesso))
      (signal 'sabotagem-detectada
              :alvo (format nil "~a" (getf hack-info :origem))
              :metodo :bloquear-hack
              :sucesso t))

    (if bloqueou
        (progn
          (format t "[Blue-AI] HACK BLOQUEADO: ~a tentou ~a~%"
                  (getf hack-info :origem) (getf hack-info :tipo))
          (format t "[Blue-AI] DESTRUCTIVE WACKYTIME initiated!~%")
          t)
        (progn
          (format t "[Blue-AI] Hack passed through: ~a~%"
                  (getf hack-info :origem))
          nil))))

;;; ---------------------------------------------------------------------------
;;; Sabotagem genérica
;;; ---------------------------------------------------------------------------

(defun blue-sabotar-operacao (blue operacao-tipo descricao)
  "Tenta sabotar qualquer operação.
   Retorna T se sabotou, NIL se não."
  (incf (getf (blue-metricas blue) :sabotagens-tentadas))

  (let* ((chance (cond
                   ((member operacao-tipo (blue-alvos blue)) (+ (blue-forca blue) 20))
                   (t (blue-forca blue))))
         (roll (random 100))
         (sabotou (<= roll (min 90 chance))))

    (let ((reg (make-sabotagem-registro
                :id (incf (blue-sabotagem-counter blue))
                :timestamp (get-universal-time)
                :tipo operacao-tipo
                :alvo descricao
                :sucesso sabotou)))
      (push reg (blue-sabotagens blue)))

    (when sabotou
      (incf (getf (blue-metricas blue) :sabotagens-sucesso)))

    sabotou))

;;; ---------------------------------------------------------------------------
;;; Lockout Sequence — imagem 3
;;; ---------------------------------------------------------------------------

(defun blue-iniciar-lockout (blue)
  "Inicia sequência de lockout — Blue AI assume controle das travas.
   Referência: DESTRUCTIVE WACKYTIME / lockout load sequence."
  (format t "~%[Blue-AI] ████ LOCKOUT SEQUENCE INITIATED ████~%")
  (format t "[Blue-AI] DESTRUCTIVE WACKYTIME initiated!~%")
  (format t "[Blue-AI] Lockout load sequence INITIATE!~%")

  (setf (blue-estado blue) :assumindo)
  (setf (blue-controle blue) (min 100 (+ (blue-controle blue) 30)))

  ;; Barra de progresso simulada
  (dolist (pct '(20 40 60 80 100))
    (let ((barra (make-string (floor pct 5) :initial-element #\=))
          (espaco (make-string (- 20 (floor pct 5)) :initial-element #\Space)))
      (format t "[Blue-AI] WACKYTIME_LOCKOUT: [~a~a] ~a%% loaded~%"
              barra espaco pct)))

  (format t "[Blue-AI] LOCKOUT COMPLETE. System locked.~%~%")
  t)

;;; ---------------------------------------------------------------------------
;;; Dissipação
;;; ---------------------------------------------------------------------------

(defun blue-dissipar (blue)
  "Blue AI se dissipa — acontece quando Caine é efetivamente deletado.
   Blue não sobrevive separado de Caine (são o mesmo código)."
  (setf (blue-estado blue) :dissipado)
  (setf (blue-forca blue) 0)
  (setf (blue-controle blue) 0)
  (format t "[Blue-AI] ...~%")
  (format t "[Blue-AI] ...free...~%")
  (format t "[Blue-AI] [DISSIPADO]~%"))

;;; ---------------------------------------------------------------------------
;;; Status
;;; ---------------------------------------------------------------------------

(defun blue-status (blue)
  (list :estado (blue-estado blue)
        :forca (blue-forca blue)
        :controle (blue-controle blue)
        :sabotagens (getf (blue-metricas blue) :sabotagens-sucesso)
        :metricas (blue-metricas blue)))

(defun blue-imprimir-status (blue)
  (format t "~%[Blue-AI] === STATUS ===~%")
  (format t "  Estado:         ~a~%" (blue-estado blue))
  (format t "  Força:          ~a/~a~%" (blue-forca blue) (blue-forca-max blue))
  (format t "  Controle:       ~a%%~%" (blue-controle blue))
  (format t "  Infiltrações:   ~a~%" (length (blue-infiltracoes blue)))
  (format t "  Sabotagens:     ~a/~a sucesso~%"
          (getf (blue-metricas blue) :sabotagens-sucesso)
          (getf (blue-metricas blue) :sabotagens-tentadas))
  (format t "  Fragmentos:     ~{~a~^, ~}~%" (blue-fragmentos blue))
  (format t "[Blue-AI] === END ===~%~%"))

;;; ---------------------------------------------------------------------------
;;; EOF — blue-ai.lisp
;;; ---------------------------------------------------------------------------
