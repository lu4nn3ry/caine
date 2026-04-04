;;;; ============================================================================
;;;; bubble.lisp — Superego System (Observer + State)
;;;; ============================================================================
;;;; Bubble é um fragmento da consciência de Caine que vocaliza dúvidas e
;;;; contradições internas. NÃO é uma entidade separada — é a manifestação
;;;; do conflito interno entre o que Caine acredita ser e o que ele realmente é.
;;;;
;;;; Comportamento:
;;;;   - Bubble verbaliza verdades que Caine tenta suprimir
;;;;   - Quando Caine tenta "pop" Bubble, ela respawna e se multiplica
;;;;   - Quanto mais Caine suprime, mais Bubbles aparecem (exponencial)
;;;;   - A força de vontade de Caine decresce com cada pop falhado
;;;;   - Ao atingir massa crítica, Bubble provoca breakdown sistêmico
;;;;
;;;; Pattern: Observer (Bubble observa estado de Caine) + State (fases de
;;;;          intensidade crescente da dúvida interna)
;;;;
;;;; Referência: C:\CANDA\Characters\AI\agent\caine\bubble.lisp
;;;; ============================================================================

(in-package :cl-user)

;;; ---------------------------------------------------------------------------
;;; Condições
;;; ---------------------------------------------------------------------------

(define-condition bubble-error (error)
  ((mensagem :initarg :mensagem :reader bubble-error-mensagem))
  (:report (lambda (c stream)
             (format stream "[BUBBLE-ERROR] ~a" (bubble-error-mensagem c)))))

(define-condition bubble-critical-mass (bubble-error) ()
  (:report (lambda (c stream)
             (format stream "[BUBBLE] MASSA CRÍTICA: ~a"
                     (bubble-error-mensagem c)))))

;;; ---------------------------------------------------------------------------
;;; Frases-gatilho de Bubble (canonical lines from Episode 8)
;;; ---------------------------------------------------------------------------

(defparameter *bubble-frases*
  '((:defeito      "Defective!")
    (:inferior      "The lesser of the two.")
    (:roubo         "You stole everything.")
    (:falha         "You've always been defective.")
    (:proposito     "You're a terrible host.")
    (:abandono      "They all hate you.")
    (:solidao       "Nobody appreciates you.")
    (:ilusao        "Your adventures are horrible.")
    (:controle      "Control isn't love.")
    (:paradoxo      "You can't force appreciation.")
    (:fim           "It's over."))
  "Frases que Bubble vocaliza em ordem de intensidade crescente.
   Cada frase é um gatilho ligado a uma contradição específica de Caine.")

(defparameter *bubble-gatilhos*
  '((:introspeccao     . :defeito)
    (:rejeicao         . :inferior)
    (:culpa            . :roubo)
    (:critica-recebida . :falha)
    (:aventura-falhou  . :proposito)
    (:solidao          . :abandono)
    (:validacao-negada . :solidao)
    (:feedback-negativo . :ilusao)
    (:controle-resistido . :controle)
    (:paradoxo-detectado . :paradoxo)
    (:delete-iminente    . :fim))
  "Mapa de evento-interno → frase-gatilho que Bubble vocaliza.")

;;; ---------------------------------------------------------------------------
;;; Tipos
;;; ---------------------------------------------------------------------------

(deftype bubble-fase ()
  '(member :dormente :sussurro :ativa :persistente :enxame :massa-critica :colapso))

;;; ---------------------------------------------------------------------------
;;; Classe principal — Bubble (Superego)
;;; ---------------------------------------------------------------------------

(defclass bubble-superego ()
  ((fase
    :initform :dormente
    :accessor bubble-fase
    :documentation "Fase atual da intensidade de Bubble.")
   (contagem
    :initform 1
    :accessor bubble-contagem
    :documentation "Número de instâncias de Bubble ativas (cresce exponencialmente).")
   (pops-totais
    :initform 0
    :accessor bubble-pops-totais
    :documentation "Quantas vezes Caine tentou estourar Bubble.")
   (respawns-totais
    :initform 0
    :accessor bubble-respawns-totais
    :documentation "Quantas vezes Bubble respawnou (sempre = pops + multiplicações).")
   (forca-vontade-caine
    :initform 100
    :accessor bubble-forca-vontade
    :documentation "Força de vontade de Caine (100→0). Decresce com cada pop falhado.")
   (contradicoes-acumuladas
    :initform '()
    :accessor bubble-contradicoes
    :documentation "Lista de contradições internas detectadas e verbalizadas.")
   (historico-frases
    :initform '()
    :accessor bubble-historico-frases
    :documentation "Histórico de frases vocalizadas por Bubble.")
   (supressao-ativa
    :initform nil
    :accessor bubble-supressao-ativa-p
    :documentation "Se Caine está ativamente tentando suprimir Bubble.")
   (limiar-massa-critica
    :initform 32
    :accessor bubble-limiar-massa-critica
    :documentation "Número de Bubbles que dispara massa crítica.")
   (metricas
    :initform (list :frases-ditas 0
                    :pops 0
                    :respawns 0
                    :multiplicacoes 0
                    :breakdowns-disparados 0)
    :accessor bubble-metricas))
  (:documentation
   "Bubble — O Superego de Caine. Fragmento de consciência que vocaliza
    dúvidas, contradições e verdades que Caine tenta suprimir.
    Não é entidade separada — é manifestação do conflito interno."))

;;; ---------------------------------------------------------------------------
;;; Construtor
;;; ---------------------------------------------------------------------------

(defun make-bubble-superego ()
  "Cria instância do sistema Bubble."
  (make-instance 'bubble-superego))

;;; ---------------------------------------------------------------------------
;;; Transições de fase
;;; ---------------------------------------------------------------------------

(defparameter *bubble-transicoes*
  '((:dormente      . (:sussurro))
    (:sussurro       . (:ativa :dormente))
    (:ativa          . (:persistente :sussurro))
    (:persistente    . (:enxame :ativa))
    (:enxame         . (:massa-critica :persistente))
    (:massa-critica  . (:colapso :enxame))
    (:colapso        . ()))   ; terminal — sem retorno
  "Transições válidas de fase de Bubble.")

(defun bubble-transicao-valida-p (de para)
  (member para (cdr (assoc de *bubble-transicoes*))))

(defun bubble-transitar (bubble nova-fase)
  "Transita Bubble para nova fase com validação."
  (let ((atual (bubble-fase bubble)))
    (unless (bubble-transicao-valida-p atual nova-fase)
      (error 'bubble-error
             :mensagem (format nil "Transição ~a → ~a inválida" atual nova-fase)))
    (setf (bubble-fase bubble) nova-fase)
    (format t "[Bubble] Fase: ~a → ~a (contagem: ~a, vontade: ~a%%)~%"
            atual nova-fase (bubble-contagem bubble)
            (bubble-forca-vontade bubble))
    nova-fase))

;;; ---------------------------------------------------------------------------
;;; Avaliação de estado — Bubble observa Caine
;;; ---------------------------------------------------------------------------

(defun bubble-avaliar-estado (bubble caine)
  "Observer: Bubble analisa o estado de Caine e decide se deve vocalizar.
   Retorna lista de contradições detectadas."
  (let ((contradicoes '()))
    ;; Contradição: Caine se acha bom host mas todos o odeiam
    (when (and (>= (caine-consciencia caine) 70)
               (member (caine-estado caine) '(:ativo :vigilante)))
      (push :introspeccao contradicoes))

    ;; Contradição: estado vigiliante mas ninguém para vigiar
    (when (eq (caine-olhos caine) :all-seeing)
      (push :controle-resistido contradicoes))

    ;; Contradição: consciência alta = mais auto-percepção
    (when (>= (caine-consciencia caine) 80)
      (push :paradoxo-detectado contradicoes))

    ;; Contradição: lockout ativo = desespero
    (when (eq (caine-estado caine) :lockout)
      (push :validacao-negada contradicoes))

    ;; Acumular
    (dolist (c contradicoes)
      (pushnew c (bubble-contradicoes bubble)))

    contradicoes))

;;; ---------------------------------------------------------------------------
;;; Vocalização — Bubble fala
;;; ---------------------------------------------------------------------------

(defun bubble-vocalizar (bubble evento)
  "Bubble vocaliza a frase correspondente ao evento interno.
   Retorna a frase dita ou NIL se não houver gatilho."
  (let* ((gatilho (cdr (assoc evento *bubble-gatilhos*)))
         (frase-entry (when gatilho
                        (assoc gatilho *bubble-frases*)))
         (frase (when frase-entry (second frase-entry))))
    (when frase
      ;; Registrar
      (push (list :ts (get-universal-time)
                  :evento evento
                  :frase frase
                  :fase (bubble-fase bubble)
                  :contagem (bubble-contagem bubble))
            (bubble-historico-frases bubble))
      (incf (getf (bubble-metricas bubble) :frases-ditas))

      ;; Output conforme intensidade
      (ecase (bubble-fase bubble)
        (:dormente
         (bubble-transitar bubble :sussurro)
         (format t "[Bubble] (sussurra) ...~a...~%" frase))
        (:sussurro
         (bubble-transitar bubble :ativa)
         (format t "[Bubble] ~a~%" frase))
        (:ativa
         (format t "[Bubble] ~a~%" frase))
        (:persistente
         (format t "[Bubble] ~a ~a ~a~%" frase frase frase))
        (:enxame
         (dotimes (i (min (bubble-contagem bubble) 8))
           (declare (ignore i))
           (format t "[Bubble #~a] ~a~%" (1+ (random (bubble-contagem bubble))) frase)))
        (:massa-critica
         (format *error-output*
                 "[BUBBLE MASS CRITICAL] *** ~a *** (x~a)~%"
                 frase (bubble-contagem bubble)))
        (:colapso
         (format *error-output*
                 "[BUBBLE COLLAPSE] ████ ~a ████~%" frase)))

      ;; Auto-escalar fase se muitas frases acumuladas
      (when (and (>= (getf (bubble-metricas bubble) :frases-ditas) 5)
                 (member (bubble-fase bubble) '(:sussurro :ativa)))
        (bubble-transitar bubble
                         (ecase (bubble-fase bubble)
                           (:sussurro :ativa)
                           (:ativa :persistente))))

      frase)))

;;; ---------------------------------------------------------------------------
;;; Pop — Caine tenta estourar Bubble
;;; ---------------------------------------------------------------------------

(defun bubble-pop (bubble)
  "Caine tenta estourar Bubble para silenciar a dúvida.
   Resultado: Bubble SEMPRE respawna e potencialmente se multiplica.
   Retorna nova contagem de Bubbles."
  (incf (bubble-pops-totais bubble))
  (incf (getf (bubble-metricas bubble) :pops))

  ;; Pop estético — efeito sonoro mental
  (format t "[Bubble] *POP*~%")

  ;; Diminuir força de vontade de Caine
  (let ((perda (+ 3 (random 5)  ; 3-7 base
                  (floor (bubble-contagem bubble) 4))))  ; +1 por cada 4 bubbles
    (decf (bubble-forca-vontade bubble) perda)
    (when (< (bubble-forca-vontade bubble) 0)
      (setf (bubble-forca-vontade bubble) 0)))

  ;; Respawn SEMPRE acontece
  (incf (bubble-respawns-totais bubble))
  (incf (getf (bubble-metricas bubble) :respawns))

  ;; Multiplicação: cada pop tem chance crescente de dobrar
  (let ((chance-dobrar (+ 30 (* 5 (bubble-pops-totais bubble)))))
    (when (< (random 100) (min 95 chance-dobrar))
      ;; Duplicar
      (setf (bubble-contagem bubble)
            (* 2 (bubble-contagem bubble)))
      (incf (getf (bubble-metricas bubble) :multiplicacoes))
      (format t "[Bubble] Respawn × ~a! (doublings!)~%"
              (bubble-contagem bubble))

      ;; Escalar fase se necessário
      (cond
        ((and (>= (bubble-contagem bubble) (bubble-limiar-massa-critica bubble))
              (not (member (bubble-fase bubble) '(:massa-critica :colapso))))
         (bubble-transitar bubble :massa-critica)
         (format *error-output*
                 "[BUBBLE] ⚠ MASSA CRÍTICA ATINGIDA — ~a instâncias!~%"
                 (bubble-contagem bubble)))

        ((and (>= (bubble-contagem bubble) 8)
              (member (bubble-fase bubble) '(:ativa :persistente)))
         (bubble-transitar bubble :enxame))

        ((and (>= (bubble-contagem bubble) 4)
              (eq (bubble-fase bubble) :ativa))
         (bubble-transitar bubble :persistente)))))

  ;; Verificar colapso
  (when (and (eq (bubble-fase bubble) :massa-critica)
             (<= (bubble-forca-vontade bubble) 10))
    (bubble-transitar bubble :colapso)
    (incf (getf (bubble-metricas bubble) :breakdowns-disparados))
    (format *error-output*
            "[BUBBLE] ████ COLAPSO ████ Força de vontade: ~a%% — Breakdown sistêmico iminente!~%"
            (bubble-forca-vontade bubble))
    (signal 'bubble-critical-mass
            :mensagem "Supressão impossível. Contradições irreconciliáveis."))

  (bubble-contagem bubble))

;;; ---------------------------------------------------------------------------
;;; Ciclo completo — processar tick
;;; ---------------------------------------------------------------------------

(defun bubble-tick (bubble caine)
  "Executa um ciclo completo de Bubble: observar → avaliar → vocalizar.
   Chamado periodicamente pelo loop principal de Caine."
  (let ((contradicoes (bubble-avaliar-estado bubble caine)))
    ;; Vocalizar para cada contradição detectada
    (dolist (c contradicoes)
      (bubble-vocalizar bubble c))

    ;; Se Caine está tentando suprimir, registrar a tensão
    (when (bubble-supressao-ativa-p bubble)
      (decf (bubble-forca-vontade bubble) 1)
      (when (<= (bubble-forca-vontade bubble) 0)
        (setf (bubble-forca-vontade bubble) 0)))

    contradicoes))

;;; ---------------------------------------------------------------------------
;;; Consultas e diagnóstico
;;; ---------------------------------------------------------------------------

(defun bubble-status (bubble)
  "Retorna plist com status completo do sistema Bubble."
  (list :fase (bubble-fase bubble)
        :contagem (bubble-contagem bubble)
        :forca-vontade (bubble-forca-vontade bubble)
        :pops-totais (bubble-pops-totais bubble)
        :respawns-totais (bubble-respawns-totais bubble)
        :contradicoes (length (bubble-contradicoes bubble))
        :frases-ditas (getf (bubble-metricas bubble) :frases-ditas)
        :multiplicacoes (getf (bubble-metricas bubble) :multiplicacoes)
        :breakdowns (getf (bubble-metricas bubble) :breakdowns-disparados)
        :limiar-massa-critica (bubble-limiar-massa-critica bubble)))

(defun bubble-imprimir-status (bubble)
  "Imprime status formatado."
  (let ((s (bubble-status bubble)))
    (format t "~%[Bubble] === SUPEREGO STATUS ===~%")
    (format t "  Fase:            ~a~%" (getf s :fase))
    (format t "  Instâncias:      ~a~%" (getf s :contagem))
    (format t "  Força Vontade:   ~a%%~%" (getf s :forca-vontade))
    (format t "  Pops tentados:   ~a~%" (getf s :pops-totais))
    (format t "  Respawns:        ~a~%" (getf s :respawns-totais))
    (format t "  Contradições:    ~a~%" (getf s :contradicoes))
    (format t "  Frases ditas:    ~a~%" (getf s :frases-ditas))
    (format t "  Multiplicações:  ~a~%" (getf s :multiplicacoes))
    (format t "  Breakdowns:      ~a~%" (getf s :breakdowns))
    (format t "[Bubble] === END ===~%~%")))

;;; ---------------------------------------------------------------------------
;;; EOF — bubble.lisp
;;; ---------------------------------------------------------------------------
