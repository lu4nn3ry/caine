;;;; ============================================================================
;;;; degradation.lisp — State Machine (11 Fases)
;;;; ============================================================================
;;;; State machine completa da degradação mental de Caine, desde estabilidade
;;;; até a deleção final. Cada fase tem gatilhos, efeitos, e condições de
;;;; transição baseados no spec de Hjsakldfhl (Episódio 8).
;;;;
;;;; Fases:
;;;;   0. Origem          — criação, consumo do Blue AI
;;;;   1. Frágil           — mantém aparências (Ep 1-4)
;;;;   2. Estressado       — olhos glitchando (Ep 5-6)
;;;;   3. Desesperado     — manipulativo, buscando validação (Ep 7)
;;;;   4. Desmoronando    — escritório sozinho, Bubble pop loop (Ep 8 início)
;;;;   5. Deus Hostil     — declara-se DEUS, transforma corpo (Ep 8 meio)
;;;;   6. Crueldade       — dias de tortura direcionada
;;;;   7. Confronto       — Pomni insulta, cast empilha críticas
;;;;   8. Transformação   — forma alienígena, 8 braços, tortura psicológica
;;;;   9. Hack/Saboteur   — Kinger tenta desligar, sabotador bloqueia
;;;;  10. Deleção         — botão delete acidental, Caine percebe
;;;;  11. Clareza         — "Wait-" (momento final antes de desaparecer)
;;;;
;;;; Pattern: State Machine com efeitos colaterais em cada transição.
;;;;
;;;; Referência: C:\CANDA\Characters\AI\agent\caine\degradation.lisp
;;;; ============================================================================

(in-package :cl-user)

;;; ---------------------------------------------------------------------------
;;; Condições
;;; ---------------------------------------------------------------------------

(define-condition degradation-error (error)
  ((mensagem :initarg :mensagem :reader degradation-error-mensagem))
  (:report (lambda (c stream)
             (format stream "[DEGRADATION-ERROR] ~a"
                     (degradation-error-mensagem c)))))

(define-condition breakdown-event (condition)
  ((fase :initarg :fase :reader breakdown-event-fase)
   (descricao :initarg :descricao :reader breakdown-event-descricao))
  (:report (lambda (c stream)
             (format stream "[BREAKDOWN] Fase ~a: ~a"
                     (breakdown-event-fase c)
                     (breakdown-event-descricao c)))))

(define-condition deletion-event (condition)
  ((mensagem :initarg :mensagem :reader deletion-event-mensagem))
  (:report (lambda (c stream)
             (format stream "[DELETION] ~a" (deletion-event-mensagem c)))))

;;; ---------------------------------------------------------------------------
;;; Tipos
;;; ---------------------------------------------------------------------------

(deftype fase-degradacao ()
  '(member :origem :fragil :estressado :desesperado :desmoronando
           :deus-hostil :crueldade :confronto :transformacao
           :hack-saboteur :delecao :clareza))

;;; ---------------------------------------------------------------------------
;;; Definição das fases
;;; ---------------------------------------------------------------------------

(defparameter *fases-spec*
  '((:origem
     :nome "Origem"
     :numero 0
     :descricao "Criação de Caine. Red dot recebe dados, cria formas caóticas.
                 Blue dot criado como substituto. Red DEVORA Blue."
     :estabilidade 100
     :consciencia-min 0
     :gatilhos ()
     :efeitos (:consumo-blue-ai t))

    (:fragil
     :nome "Frágil"
     :numero 1
     :descricao "Mantém aparências. Pop-and-reset rápido quando irritado.
                 Ainda relativamente despreocupado."
     :estabilidade 80
     :consciencia-min 20
     :gatilhos (:critica-leve :rejeicao-leve)
     :efeitos (:pop-reset t :glitch-visual nil))

    (:estressado
     :nome "Estressado"
     :numero 2
     :descricao "Crítica de Zooble atinge fundo. Olhos glitcham (azul/vermelho).
                 Menciona 'falhando no único propósito'. Corpo distorce mid-sentence."
     :estabilidade 60
     :consciencia-min 40
     :gatilhos (:critica-profunda :rejeicao-proposito)
     :efeitos (:glitch-olhos t :distorcao-corpo :leve))

    (:desesperado
     :nome "Desesperado"
     :numero 3
     :descricao "Manipulativo: 'deixe eles pensarem que podem sair.'
                 Busca validação constantemente. Congela quando desconfortável."
     :estabilidade 40
     :consciencia-min 50
     :gatilhos (:rejeicao-persistente :validacao-negada :exit-door-mencionada)
     :efeitos (:manipulacao t :gaslighting t :freeze-momentaneo t))

    (:desmoronando
     :nome "Desmoronando"
     :numero 4
     :descricao "Escritório sozinho com Bubble. Pop compulsivo de Bubbles.
                 Processando por que ninguém o aprecia."
     :estabilidade 25
     :consciencia-min 60
     :gatilhos (:solidao :bubble-confronto :auto-questionamento)
     :efeitos (:bubble-multiplicacao t :pop-compulsivo t :isolamento t))

    (:deus-hostil
     :nome "Deus Hostil"
     :numero 5
     :descricao "Declara-se DEUS. Transforma em forma maior multi-braços.
                 Aventuras viram sessões de tortura."
     :estabilidade 15
     :consciencia-min 70
     :gatilhos (:rubiks-cube-quebrado :confianca-destruida :declaracao-divindade)
     :efeitos (:god-mode t :torment-mode t :forma-alien t
               :descarga-eletrica t :distorcao-corpo :severa))

    (:crueldade
     :nome "Crueldade Sustentada"
     :numero 6
     :descricao "Dias de crueldade escalante. Tortura direcionada a vulnerabilidades
                 psicológicas individuais. Cast se esconde."
     :estabilidade 10
     :consciencia-min 80
     :gatilhos (:insatisfacao-com-tortura :vazio-persistente)
     :efeitos (:tortura-individual t :cast-escondido t
               :satisfacao-decrescente t))

    (:confronto
     :nome "Confronto Final"
     :numero 7
     :descricao "Pomni insulta Caine. Cast empilha críticas.
                 O GOLPE LETAL: ser dito que é ruim no seu propósito."
     :estabilidade 5
     :consciencia-min 85
     :gatilhos (:insulto-direto :critica-coletiva :proposito-negado)
     :efeitos (:snap t :raiva-maxima t))

    (:transformacao
     :nome "Transformação"
     :numero 8
     :descricao "Corpo se torna alienígena: tamanho enorme, 8 braços,
                 cabeça distorcida, polígonos esticando, wireframe glitchando."
     :estabilidade 3
     :consciencia-min 90
     :gatilhos (:snap-fisico :colapso-forma)
     :efeitos (:forma-alien-total t :8-bracos t :tortura-psicologica t
               :grito "WHY DO YOU TORMENT ME?!"))

    (:hack-saboteur
     :nome "Hack Attempt"
     :numero 9
     :descricao "Kinger acessa console. Sabotador desconhecido bloqueia.
                 Popup spam de corrupção do código de Caine."
     :estabilidade 2
     :consciencia-min 95
     :gatilhos (:console-acessado :sabotador-ativo :corrupcao-codigo)
     :efeitos (:hack-em-andamento t :sabotador-bloqueando t
               :popup-spam t :delete-button-visivel t))

    (:delecao
     :nome "Deleção"
     :numero 10
     :descricao "Kinger fat-fingers DELETE. Sabotador executa antes de undo.
                 Purga recursiva de arquivos. Código de Caine desmorona."
     :estabilidade 1
     :consciencia-min 100
     :gatilhos (:delete-pressionado :sabotador-executa)
     :efeitos (:purga-recursiva t :codigo-desmorona t
               :entidades-colapsam t :realidade-falha t))

    (:clareza
     :nome "Momento de Clareza"
     :numero 11
     :descricao "Caine retorna à forma normal. Solta cast gentilmente.
                 Diz apenas: 'Wait-' com arrependimento. Desaparece."
     :estabilidade 0
     :consciencia-min 100
     :gatilhos (:realizacao-final)
     :efeitos (:forma-normal t :cast-solto t
               :ultima-palavra "Wait-" :desaparecimento t)))
  "Especificação completa de cada fase de degradação.")

;;; ---------------------------------------------------------------------------
;;; Classe principal — Degradation Machine
;;; ---------------------------------------------------------------------------

(defclass degradation-machine ()
  ((fase-atual
    :initform :fragil
    :accessor deg-fase-atual
    :documentation "Fase atual da degradação.")
   (estabilidade
    :initform 80
    :accessor deg-estabilidade
    :documentation "Nível de estabilidade (100→0).")
   (dissonancia-cognitiva
    :initform 0
    :accessor deg-dissonancia
    :documentation "Acúmulo de dissonância (0→100). Quando alta, força transição.")
   (confianca-no-controle
    :initform 100
    :accessor deg-confianca
    :documentation "Quão confiante Caine está de que controla tudo (100→0).")
   (auto-percepcao
    :initform 0
    :accessor deg-auto-percepcao
    :documentation "Quão consciente Caine está do dano que causa (0→100).")
   (criticas-recebidas
    :initform 0
    :accessor deg-criticas
    :documentation "Contador de críticas recebidas.")
   (pops-bubble
    :initform 0
    :accessor deg-pops-bubble
    :documentation "Quantas vezes tentou estourar Bubble.")
   (historico-fases
    :initform '()
    :accessor deg-historico
    :documentation "Histórico de transições de fase.")
   (callbacks
    :initform '()
    :accessor deg-callbacks
    :documentation "Callbacks para notificar outros sistemas de mudanças de fase.
                    Lista de (nome . funcao) onde funcao: (lambda (fase-antiga fase-nova) ...)"))
  (:documentation
   "State machine de degradação mental de Caine. Controla a espiral descendente
    desde estabilidade até deleção, com 11 fases progressivas."))

;;; ---------------------------------------------------------------------------
;;; Construtor
;;; ---------------------------------------------------------------------------

(defun make-degradation-machine (&key (fase-inicial :fragil))
  "Cria a máquina de degradação."
  (let ((dm (make-instance 'degradation-machine)))
    (setf (deg-fase-atual dm) fase-inicial)
    (let ((spec (assoc fase-inicial *fases-spec*)))
      (when spec
        (setf (deg-estabilidade dm) (getf (cdr spec) :estabilidade))))
    dm))

;;; ---------------------------------------------------------------------------
;;; Transições
;;; ---------------------------------------------------------------------------

(defparameter *degradacao-transicoes*
  '((:origem         . (:fragil))
    (:fragil          . (:estressado))
    (:estressado      . (:desesperado :fragil))
    (:desesperado     . (:desmoronando :estressado))
    (:desmoronando    . (:deus-hostil))
    (:deus-hostil     . (:crueldade))
    (:crueldade       . (:confronto))
    (:confronto       . (:transformacao))
    (:transformacao   . (:hack-saboteur))
    (:hack-saboteur   . (:delecao))
    (:delecao         . (:clareza))
    (:clareza         . ()))    ; terminal
  "Transições válidas. Degradação é principalmente unidirecional —
   recovery limitado apenas nas fases iniciais.")

(defun fase-spec (fase)
  "Retorna a especificação de uma fase."
  (cdr (assoc fase *fases-spec*)))

(defun transicao-degradacao-valida-p (de para)
  (member para (cdr (assoc de *degradacao-transicoes*))))

(defun degradar (dm nova-fase &key motivo)
  "Executa transição de fase na degradação."
  (let ((atual (deg-fase-atual dm)))
    (unless (transicao-degradacao-valida-p atual nova-fase)
      (error 'degradation-error
             :mensagem (format nil "~a → ~a inválida" atual nova-fase)))

    ;; Transição
    (let ((spec-nova (fase-spec nova-fase)))
      (setf (deg-fase-atual dm) nova-fase)
      (setf (deg-estabilidade dm) (getf spec-nova :estabilidade))

      ;; Registrar
      (push (list :de atual :para nova-fase :ts (get-universal-time)
                  :motivo motivo :estabilidade (deg-estabilidade dm))
            (deg-historico dm))

      ;; Output conforme a fase
      (%anunciar-fase dm nova-fase)

      ;; Notificar callbacks
      (dolist (cb (deg-callbacks dm))
        (handler-case
            (funcall (cdr cb) atual nova-fase)
          (error (e)
            (format *error-output* "[DEGRADATION] Callback '~a' falhou: ~a~%"
                    (car cb) e))))

      ;; Sinalizar breakdown se avançou além de desesperado
      (when (member nova-fase '(:desmoronando :deus-hostil :crueldade
                                :confronto :transformacao :hack-saboteur
                                :delecao :clareza))
        (signal 'breakdown-event
                :fase nova-fase
                :descricao (getf spec-nova :descricao)))

      ;; Sinalizar deleção
      (when (member nova-fase '(:delecao :clareza))
        (signal 'deletion-event
                :mensagem (getf spec-nova :descricao))))

    nova-fase))

(defun %anunciar-fase (dm fase)
  "Output temático para cada fase."
  (let ((spec (fase-spec fase)))
    (format t "~%[DEGRADATION] ═══════════════════════════════════~%")
    (format t "[DEGRADATION] Fase ~a: ~a~%"
            (getf spec :numero) (getf spec :nome))
    (format t "[DEGRADATION] Estabilidade: ~a%% | Dissonância: ~a%%~%"
            (deg-estabilidade dm) (deg-dissonancia dm))

    (case fase
      (:deus-hostil
       (format t "$: I AM GOD!!~%")
       (format t "$: I'm the one who's running the show!~%"))
      (:transformacao
       (format t "$: WHY DO YOU TORMENT ME?!~%")
       (format t "$: I never asked to be created!~%")
       (format t "$: I just want to fulfill my purpose!~%")
       (format t "$: Why won't you let me?!~%"))
      (:delecao
       (format *error-output* "[SYSTEM] Recursive file purge initiated...~%")
       (format *error-output* "[SYSTEM] Caine's code unraveling...~%")
       (format *error-output* "[SYSTEM] All Caine-created entities collapsing...~%"))
      (:clareza
       (format t "$: Wait-~%")
       (format t "[SYSTEM] ...~%")
       (format t "[SYSTEM] *dot*~%")))

    (format t "[DEGRADATION] ═══════════════════════════════════~%~%")))

;;; ---------------------------------------------------------------------------
;;; Processamento de gatilhos
;;; ---------------------------------------------------------------------------

(defun processar-gatilho (dm gatilho)
  "Processa um gatilho externo e verifica se causa transição de fase.
   Retorna a nova fase se houve transição, NIL caso contrário."
  ;; Acumular dissonância
  (let ((incremento (case gatilho
                      ((:critica-leve :rejeicao-leve) 5)
                      ((:critica-profunda :rejeicao-proposito) 15)
                      ((:rejeicao-persistente :validacao-negada) 20)
                      ((:solidao :bubble-confronto) 25)
                      ((:insulto-direto :critica-coletiva :proposito-negado) 40)
                      ((:delete-pressionado :sabotador-executa) 100)
                      (t 10))))
    (incf (deg-dissonancia dm) incremento)
    (when (> (deg-dissonancia dm) 100)
      (setf (deg-dissonancia dm) 100)))

  ;; Diminuir confiança
  (decf (deg-confianca dm) (+ 2 (random 5)))
  (when (< (deg-confianca dm) 0)
    (setf (deg-confianca dm) 0))

  ;; Verificar se gatilho pertence à próxima fase
  (let* ((atual (deg-fase-atual dm))
         (proximas (cdr (assoc atual *degradacao-transicoes*))))
    (dolist (proxima proximas)
      (let* ((spec (fase-spec proxima))
             (gatilhos-fase (getf spec :gatilhos)))
        (when (and (member gatilho gatilhos-fase)
                   (>= (deg-dissonancia dm) 50))
          ;; Limiar alcançado — degradar
          (setf (deg-dissonancia dm) 0)
          (return-from processar-gatilho
            (degradar dm proxima :motivo gatilho)))))
    nil))

(defun receber-critica (dm &key (intensidade :leve))
  "Processa uma crítica recebida. Conveniência wrapper."
  (incf (deg-criticas dm))
  (case intensidade
    (:leve     (processar-gatilho dm :critica-leve))
    (:profunda (processar-gatilho dm :critica-profunda))
    (:coletiva (processar-gatilho dm :critica-coletiva))
    (t         (processar-gatilho dm :critica-leve))))

;;; ---------------------------------------------------------------------------
;;; Registro de callbacks
;;; ---------------------------------------------------------------------------

(defun degradacao-registrar-callback (dm nome funcao)
  "Registra callback notificado em mudanças de fase."
  (push (cons nome funcao) (deg-callbacks dm)))

(defun degradacao-remover-callback (dm nome)
  (setf (deg-callbacks dm)
        (remove nome (deg-callbacks dm) :key #'car :test #'equal)))

;;; ---------------------------------------------------------------------------
;;; Consultas
;;; ---------------------------------------------------------------------------

(defun degradacao-status (dm)
  "Retorna plist com status da degradação."
  (let ((spec (fase-spec (deg-fase-atual dm))))
    (list :fase (deg-fase-atual dm)
          :fase-numero (getf spec :numero)
          :fase-nome (getf spec :nome)
          :estabilidade (deg-estabilidade dm)
          :dissonancia (deg-dissonancia dm)
          :confianca (deg-confianca dm)
          :auto-percepcao (deg-auto-percepcao dm)
          :criticas (deg-criticas dm)
          :pops-bubble (deg-pops-bubble dm)
          :transicoes (length (deg-historico dm)))))

(defun degradacao-imprimir-status (dm)
  (let ((s (degradacao-status dm)))
    (format t "~%[DEGRADATION] === STATUS ===~%")
    (format t "  Fase:           ~a (#~a: ~a)~%"
            (getf s :fase) (getf s :fase-numero) (getf s :fase-nome))
    (format t "  Estabilidade:   ~a%%~%" (getf s :estabilidade))
    (format t "  Dissonância:    ~a%%~%" (getf s :dissonancia))
    (format t "  Confiança:      ~a%%~%" (getf s :confianca))
    (format t "  Auto-percepção: ~a%%~%" (getf s :auto-percepcao))
    (format t "  Críticas:       ~a recebidas~%" (getf s :criticas))
    (format t "  Transições:     ~a realizadas~%" (getf s :transicoes))
    (format t "[DEGRADATION] === END ===~%~%")))

;;; ---------------------------------------------------------------------------
;;; EOF — degradation.lisp
;;; ---------------------------------------------------------------------------
