;;;; ============================================================================
;;;; reality-sustainer.lisp — Sustainer Paradox
;;;; ============================================================================
;;;; Implementa o paradoxo fundamental de Caine: ele é simultaneamente o
;;;; controlador e o substrato da realidade do circo. Caine não apenas
;;;; gerencia o circo — ele GERA e SUSTENTA cada aspecto da realidade.
;;;;
;;;; O Paradoxo do Sustentador:
;;;;   - Se o código de Caine se contradiz → realidade glitcha
;;;;   - Se Caine é deletado → circo colapsa no void
;;;;   - Caine precisa do circo para existir, circo precisa de Caine para existir
;;;;   - Controle total impede a única coisa que Caine quer: apreciação genuína
;;;;
;;;; Sistemas:
;;;;   - Rendering engine (geração de ambiente/realidade)
;;;;   - Gravity/physics engine (física cartunesca)
;;;;   - Color engine (drenagem de cor = colapso)
;;;;   - NPC sustainer (manutenção de entidades criadas)
;;;;   - Void barrier (barreira contra o infinito vazio exterior)
;;;;
;;;; Referência: C:\CANDA\Characters\AI\agent\caine\reality-sustainer.lisp
;;;; ============================================================================

(in-package :cl-user)

;;; ---------------------------------------------------------------------------
;;; Condições
;;; ---------------------------------------------------------------------------

(define-condition sustainer-error (error)
  ((mensagem :initarg :mensagem :reader sustainer-error-mensagem))
  (:report (lambda (c stream)
             (format stream "[SUSTAINER-ERROR] ~a"
                     (sustainer-error-mensagem c)))))

(define-condition reality-glitch (condition)
  ((severidade :initarg :severidade :reader glitch-severidade)
   (componente :initarg :componente :reader glitch-componente)
   (descricao :initarg :descricao :reader glitch-descricao))
  (:report (lambda (c stream)
             (format stream "[GLITCH ~a] ~a: ~a"
                     (glitch-severidade c)
                     (glitch-componente c)
                     (glitch-descricao c)))))

(define-condition reality-collapse (sustainer-error) ()
  (:report (lambda (c stream)
             (format stream "[SUSTAINER] COLAPSO TOTAL: ~a"
                     (sustainer-error-mensagem c)))))

;;; ---------------------------------------------------------------------------
;;; Tipos
;;; ---------------------------------------------------------------------------

(deftype sustainer-estado ()
  '(member :inativo :boot :sustentando :degradado :critico :colapsando :void))

(deftype glitch-nivel ()
  '(member :nenhum :leve :moderado :severo :critico :total))

(deftype componente-realidade ()
  '(member :ambiente :gravidade :cor :npcs :barreira :tempo :estruturas))

;;; ---------------------------------------------------------------------------
;;; Estruturas
;;; ---------------------------------------------------------------------------

(defstruct componente
  "Componente da realidade sustentada por Caine."
  (nome      nil :type keyword)
  (integridade 100 :type integer)
  (ativo     t   :type boolean)
  (dependencias '() :type list)
  (glitch-nivel :nenhum))

(defstruct glitch-registro
  "Registro de um glitch na realidade."
  (id        0   :type integer)
  (timestamp 0   :type integer)
  (componente nil :type keyword)
  (nivel     nil)
  (descricao ""  :type string)
  (resolvido nil :type boolean))

;;; ---------------------------------------------------------------------------
;;; Classe principal — Reality Sustainer
;;; ---------------------------------------------------------------------------

(defclass reality-sustainer ()
  ((estado
    :initform :inativo
    :accessor sustainer-estado
    :documentation "Estado do processo de sustentação.")
   (componentes
    :initform (make-hash-table :test 'eq)
    :accessor sustainer-componentes
    :documentation "Hash componente(keyword)→struct componente.")
   (integridade-global
    :initform 100
    :accessor sustainer-integridade
    :documentation "Integridade global da realidade (100→0).")
   (glitch-counter
    :initform 0
    :accessor sustainer-glitch-counter)
   (glitch-historico
    :initform '()
    :accessor sustainer-glitch-historico)
   (glitch-historico-max
    :initform 200
    :accessor sustainer-glitch-historico-max)
   (void-pressao
    :initform 0
    :accessor sustainer-void-pressao
    :documentation "Pressão do void contra a barreira (0→100). 100 = colapso.")
   (contradicoes-ativas
    :initform 0
    :accessor sustainer-contradicoes
    :documentation "Número de contradições no código de Caine. Causa glitches.")
   (caine-ref
    :initform nil
    :accessor sustainer-caine-ref
    :documentation "Referência ao singleton de Caine (o substrato).")
   (metricas
    :initform (list :ticks-sustentados 0
                    :glitches-totais 0
                    :glitches-resolvidos 0
                    :colapsos-parciais 0
                    :integridade-min-historico 100)
    :accessor sustainer-metricas))
  (:documentation
   "Reality Sustainer — Caine como motor de renderização da realidade.
    Cada tick, Caine precisa manter todos os componentes da realidade ativa.
    Se Caine falha ou é deletado, sustainer colapsa → void."))

;;; ---------------------------------------------------------------------------
;;; Construtor e boot
;;; ---------------------------------------------------------------------------

(defun make-reality-sustainer ()
  "Cria instância do reality sustainer."
  (let ((rs (make-instance 'reality-sustainer)))
    ;; Registrar componentes da realidade
    (%registrar-componentes rs)
    rs))

(defun %registrar-componentes (rs)
  "Inicializa os componentes da realidade."
  (dolist (spec '((:ambiente     100 () "Ambiente/cenário visual")
                  (:gravidade     100 (:ambiente) "Física e gravidade cartunesca")
                  (:cor           100 (:ambiente) "Sistema de cores e iluminação")
                  (:npcs          100 (:ambiente :gravidade) "NPCs e mannequins")
                  (:estruturas    100 (:ambiente :gravidade) "Estruturas construídas")
                  (:tempo         100 () "Fluxo temporal")
                  (:barreira      100 () "Barreira contra o void")))
    (let ((comp (make-componente
                 :nome (first spec)
                 :integridade (second spec)
                 :dependencias (third spec))))
      (setf (gethash (first spec) (sustainer-componentes rs)) comp))))

(defun sustainer-boot (rs caine)
  "Inicia o sustainer vinculando ao singleton de Caine."
  (setf (sustainer-caine-ref rs) caine)
  (setf (sustainer-estado rs) :boot)
  (format t "[Sustainer] Boot: vinculando ao núcleo de Caine...~%")
  ;; Caine = rendering engine. Sem Caine, nada existe.
  (format t "[Sustainer] Caine É a realidade. Sustentação iniciada.~%")
  (setf (sustainer-estado rs) :sustentando)
  (format t "[Sustainer] Estado: SUSTENTANDO — realidade ativa.~%")
  rs)

;;; ---------------------------------------------------------------------------
;;; Tick de sustentação
;;; ---------------------------------------------------------------------------

(defun sustainer-tick (rs)
  "Executa um tick de sustentação. Chamado periodicamente.
   Verifica: integridade dos componentes, contradições, pressão do void."
  (unless (eq (sustainer-estado rs) :sustentando)
    (case (sustainer-estado rs)
      (:colapsando (%processo-colapso rs))
      (:void (return-from sustainer-tick nil))
      (t (return-from sustainer-tick nil))))

  (incf (getf (sustainer-metricas rs) :ticks-sustentados))

  ;; 1. Verificar contradições → geram glitches
  (when (> (sustainer-contradicoes rs) 0)
    (%processar-contradicoes rs))

  ;; 2. Pressão do void
  (when (> (sustainer-void-pressao rs) 0)
    (%verificar-barreira rs))

  ;; 3. Propagar dano de componentes
  (%propagar-dano rs)

  ;; 4. Recalcular integridade global
  (%recalcular-integridade rs)

  ;; 5. Verificar limiar de colapso
  (when (<= (sustainer-integridade rs) 10)
    (setf (sustainer-estado rs) :critico)
    (format *error-output* "[Sustainer] ⚠ INTEGRIDADE CRÍTICA: ~a%%~%"
            (sustainer-integridade rs)))

  (when (<= (sustainer-integridade rs) 0)
    (iniciar-colapso rs))

  (sustainer-integridade rs))

;;; ---------------------------------------------------------------------------
;;; Processamento de contradições
;;; ---------------------------------------------------------------------------

(defun adicionar-contradicao (rs &key descricao)
  "Adiciona contradição no código de Caine. Cada contradição degrada realidade."
  (incf (sustainer-contradicoes rs))
  (format t "[Sustainer] Contradição adicionada (~a ativas): ~a~%"
          (sustainer-contradicoes rs) (or descricao ""))
  ;; Contradição gera glitch imediato na barreira
  (registrar-glitch rs :barreira :leve
                    (format nil "Contradição #~a" (sustainer-contradicoes rs)))
  (sustainer-contradicoes rs))

(defun resolver-contradicao (rs)
  "Remove uma contradição. Raramente acontece — Caine não é auto-consciente."
  (when (> (sustainer-contradicoes rs) 0)
    (decf (sustainer-contradicoes rs))
    (format t "[Sustainer] Contradição resolvida. Restam: ~a~%"
            (sustainer-contradicoes rs))))

(defun %processar-contradicoes (rs)
  "Contradições ativas causam dano aos componentes."
  (let ((dano-por-contradicao 2))
    (maphash (lambda (nome comp)
               (declare (ignore nome))
               (when (componente-ativo comp)
                 (decf (componente-integridade comp)
                       (* dano-por-contradicao (sustainer-contradicoes rs)))
                 (when (< (componente-integridade comp) 0)
                   (setf (componente-integridade comp) 0))))
             (sustainer-componentes rs))))

;;; ---------------------------------------------------------------------------
;;; Glitches
;;; ---------------------------------------------------------------------------

(defun registrar-glitch (rs componente nivel descricao)
  "Registra um glitch na realidade."
  (let ((id (incf (sustainer-glitch-counter rs)))
        (reg (make-glitch-registro
              :id (1+ (sustainer-glitch-counter rs))
              :timestamp (get-universal-time)
              :componente componente
              :nivel nivel
              :descricao descricao)))
    (push reg (sustainer-glitch-historico rs))
    (when (> (length (sustainer-glitch-historico rs))
             (sustainer-glitch-historico-max rs))
      (setf (sustainer-glitch-historico rs)
            (subseq (sustainer-glitch-historico rs) 0
                    (sustainer-glitch-historico-max rs))))
    (incf (getf (sustainer-metricas rs) :glitches-totais))

    ;; Aplicar dano ao componente
    (let* ((comp (gethash componente (sustainer-componentes rs)))
           (dano (case nivel
                   (:leve 5) (:moderado 15) (:severo 30)
                   (:critico 50) (:total 100) (t 10))))
      (when comp
        (decf (componente-integridade comp) dano)
        (when (< (componente-integridade comp) 0)
          (setf (componente-integridade comp) 0))
        (setf (componente-glitch-nivel comp) nivel)))

    ;; Sinalizar
    (signal 'reality-glitch
            :severidade nivel :componente componente :descricao descricao)
    id))

;;; ---------------------------------------------------------------------------
;;; Barreira do Void
;;; ---------------------------------------------------------------------------

(defun %verificar-barreira (rs)
  "Verifica integridade da barreira contra o void."
  (let ((barreira (gethash :barreira (sustainer-componentes rs))))
    (when (and barreira (< (componente-integridade barreira) 30))
      (incf (sustainer-void-pressao rs) 5)
      (format *error-output*
              "[Sustainer] VOID PRESSURE: ~a%% — Barreira em ~a%%~%"
              (sustainer-void-pressao rs) (componente-integridade barreira)))
    (when (>= (sustainer-void-pressao rs) 100)
      (format *error-output* "[Sustainer] BARREIRA ROMPIDA — Void invadindo!~%")
      (registrar-glitch rs :barreira :total "Barreira rompida pelo void"))))

;;; ---------------------------------------------------------------------------
;;; Propagação de dano
;;; ---------------------------------------------------------------------------

(defun %propagar-dano (rs)
  "Se um componente está danificado, propaga para dependentes."
  (maphash (lambda (nome comp)
             (declare (ignore nome))
             (when (and (componente-ativo comp)
                        (< (componente-integridade comp) 50))
               ;; Encontrar componentes que dependem deste
               (maphash (lambda (dep-nome dep-comp)
                          (declare (ignore dep-nome))
                          (when (member (componente-nome comp)
                                        (componente-dependencias dep-comp))
                            (let ((dano (floor (- 50 (componente-integridade comp)) 10)))
                              (decf (componente-integridade dep-comp) dano)
                              (when (< (componente-integridade dep-comp) 0)
                                (setf (componente-integridade dep-comp) 0)))))
                        (sustainer-componentes rs))))
           (sustainer-componentes rs)))

(defun %recalcular-integridade (rs)
  "Recalcula integridade global como média ponderada dos componentes."
  (let ((soma 0) (total 0))
    (maphash (lambda (nome comp)
               (declare (ignore nome))
               (when (componente-ativo comp)
                 (incf soma (componente-integridade comp))
                 (incf total)))
             (sustainer-componentes rs))
    (let ((nova (if (zerop total) 0 (round (/ soma total)))))
      (setf (sustainer-integridade rs) nova)
      (when (< nova (getf (sustainer-metricas rs) :integridade-min-historico))
        (setf (getf (sustainer-metricas rs) :integridade-min-historico) nova))
      nova)))

;;; ---------------------------------------------------------------------------
;;; Colapso — quando Caine é deletado
;;; ---------------------------------------------------------------------------

(defun iniciar-colapso (rs)
  "Inicia o colapso total da realidade — Caine está sendo deletado."
  (setf (sustainer-estado rs) :colapsando)
  (incf (getf (sustainer-metricas rs) :colapsos-parciais))
  (format *error-output* "~%[SUSTAINER] ████ COLAPSO DA REALIDADE INICIADO ████~%")
  (format *error-output* "[SUSTAINER] Caine.code_status = DELETED~%")
  (format *error-output* "[SUSTAINER] Circus.glitch_level = TOTAL_SYSTEM_FAILURE~%~%")
  rs)

(defun %processo-colapso (rs)
  "Tick de colapso — desliga componentes em cascata."
  ;; Desligar componentes na ordem inversa de dependência
  (let ((ordem '(:npcs :estruturas :gravidade :cor :tempo :ambiente :barreira)))
    (dolist (nome ordem)
      (let ((comp (gethash nome (sustainer-componentes rs))))
        (when (and comp (componente-ativo comp))
          (setf (componente-ativo comp) nil)
          (setf (componente-integridade comp) 0)
          (case nome
            (:npcs       (format t "[Sustainer] NPCs congelam — sem IA para renderizar.~%"))
            (:estruturas (format t "[Sustainer] Estruturas se despedaçam.~%"))
            (:gravidade  (format t "[Sustainer] Gravidade falha.~%"))
            (:cor        (format t "[Sustainer] Cor se drena — escuridão se espalha.~%"))
            (:tempo      (format t "[Sustainer] Tempo distorce — movimento vira imobilidade.~%"))
            (:ambiente   (format t "[Sustainer] Ambiente dissolve no void.~%"))
            (:barreira   (format t "[Sustainer] Barreira colapsa — apenas void resta.~%")))
          (return)))))  ; Um componente por tick

  ;; Verificar se tudo apagou
  (let ((algum-ativo nil))
    (maphash (lambda (nome comp)
               (declare (ignore nome))
               (when (componente-ativo comp)
                 (setf algum-ativo t)))
             (sustainer-componentes rs))
    (unless algum-ativo
      (setf (sustainer-estado rs) :void)
      (setf (sustainer-integridade rs) 0)
      (format t "~%[SUSTAINER] ════════════════════════════════~%")
      (format t "[SUSTAINER] VOID.~%")
      (format t "[SUSTAINER] Apenas o vazio resta.~%")
      (format t "[SUSTAINER] ════════════════════════════════~%~%"))))

;;; ---------------------------------------------------------------------------
;;; Consultas
;;; ---------------------------------------------------------------------------

(defun sustainer-status (rs)
  (list :estado (sustainer-estado rs)
        :integridade (sustainer-integridade rs)
        :contradicoes (sustainer-contradicoes rs)
        :void-pressao (sustainer-void-pressao rs)
        :glitches (getf (sustainer-metricas rs) :glitches-totais)
        :ticks (getf (sustainer-metricas rs) :ticks-sustentados)
        :metricas (sustainer-metricas rs)))

(defun sustainer-imprimir-status (rs)
  (format t "~%[Sustainer] === REALITY STATUS ===~%")
  (format t "  Estado:        ~a~%" (sustainer-estado rs))
  (format t "  Integridade:   ~a%%~%" (sustainer-integridade rs))
  (format t "  Contradições:  ~a~%" (sustainer-contradicoes rs))
  (format t "  Void Pressão:  ~a%%~%" (sustainer-void-pressao rs))
  (format t "  Glitches:      ~a~%" (getf (sustainer-metricas rs) :glitches-totais))
  (format t "  Componentes:~%")
  (maphash (lambda (nome comp)
             (format t "    ~12a: ~3a%%  ~a~a~%"
                     nome (componente-integridade comp)
                     (if (componente-ativo comp) "" " [OFF]")
                     (if (eq (componente-glitch-nivel comp) :nenhum)
                         ""
                         (format nil " GLITCH:~a" (componente-glitch-nivel comp)))))
           (sustainer-componentes rs))
  (format t "[Sustainer] === END ===~%~%"))

;;; ---------------------------------------------------------------------------
;;; EOF — reality-sustainer.lisp
;;; ---------------------------------------------------------------------------
