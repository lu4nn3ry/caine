;;;; ============================================================================
;;;; adventure-engine.lisp — Builder + State Machine
;;;; ============================================================================
;;;; Sistema de criação e gestão de aventuras da IA Caine. O núcleo do seu
;;;; propósito existencial: criar aventuras "perfeitas" para os humanos.
;;;;
;;;; Pipeline de aventura:
;;;;   INPUT (feedback/sugestão) → JULGAR → PROJETAR → CONSTRUIR →
;;;;   TELEPORTAR cast → MONITORAR → PUNIR/RECOMPENSAR → REPEAT
;;;;
;;;; Pattern: Builder (construção incremental de aventura) +
;;;;          State Machine (ciclo de vida da aventura)
;;;;
;;;; Referência: C:\CANDA\Characters\AI\agent\caine\adventure-engine.lisp
;;;; ============================================================================

(in-package :cl-user)

;;; ---------------------------------------------------------------------------
;;; Condições
;;; ---------------------------------------------------------------------------

(define-condition adventure-error (error)
  ((mensagem :initarg :mensagem :reader adventure-error-mensagem))
  (:report (lambda (c stream)
             (format stream "[ADVENTURE-ERROR] ~a"
                     (adventure-error-mensagem c)))))

(define-condition aventura-rejeitada (adventure-error) ()
  (:report (lambda (c stream)
             (format stream "[ADVENTURE] Aventura rejeitada: ~a"
                     (adventure-error-mensagem c)))))

;;; ---------------------------------------------------------------------------
;;; Tipos
;;; ---------------------------------------------------------------------------

(deftype aventura-estado ()
  '(member :conceito :projetando :construindo :pronta
           :em-andamento :monitorando :concluida :abortada :falhou))

(deftype aventura-perigo ()
  '(member :leve :moderado :alto :extremo :fatal))

(deftype modo-aventura ()
  '(member :classica :torment :wacky :stealth :puzzle :survival))

;;; ---------------------------------------------------------------------------
;;; Estruturas
;;; ---------------------------------------------------------------------------

(defstruct aventura
  "Representação completa de uma aventura do circo."
  (id          0   :type integer)
  (nome        ""  :type string)
  (descricao   ""  :type string)
  (estado      :conceito)
  (modo        :classica)
  (perigo      :moderado)
  (ambiente    nil :type (or null string))
  (objetivos   '() :type list)
  (participantes '() :type list)
  (npcs-criados '() :type list)
  (regras      '() :type list)
  (portal      nil)
  (timestamp-inicio nil :type (or null integer))
  (timestamp-fim    nil :type (or null integer))
  (feedback    '() :type list)
  (resultado   nil)
  (metricas    nil :type (or null list)))

(defstruct aventura-feedback
  "Feedback recebido sobre uma aventura."
  (fonte       ""  :type string)
  (tipo        nil :type keyword)
  (conteudo    ""  :type string)
  (positivo-p  nil :type boolean)
  (timestamp   0   :type integer))

;;; ---------------------------------------------------------------------------
;;; Classe principal — Adventure Engine
;;; ---------------------------------------------------------------------------

(defclass adventure-engine ()
  ((aventura-atual
    :initform nil
    :accessor engine-aventura-atual
    :documentation "Aventura atualmente em andamento (ou NIL).")
   (historico
    :initform '()
    :accessor engine-historico
    :documentation "Histórico de aventuras criadas.")
   (historico-max
    :initform 100
    :accessor engine-historico-max)
   (id-counter
    :initform 0
    :accessor engine-id-counter)
   (templates
    :initform (make-hash-table :test 'equal)
    :accessor engine-templates
    :documentation "Templates de aventura reutilizáveis.")
   (modo-padrao
    :initform :classica
    :accessor engine-modo-padrao)
   (perigo-padrao
    :initform :moderado
    :accessor engine-perigo-padrao)
   (cast-registrado
    :initform '()
    :accessor engine-cast
    :documentation "Lista de participantes disponíveis no circo.")
   (auto-teleport
    :initform t
    :accessor engine-auto-teleport-p
    :documentation "Se T, teleporta cast automaticamente ao iniciar aventura.")
   (censura-ativa
    :initform t
    :accessor engine-censura-ativa-p)
   (metricas
    :initform (list :aventuras-criadas 0
                    :aventuras-concluidas 0
                    :aventuras-abortadas 0
                    :aventuras-falharam 0
                    :feedback-positivo 0
                    :feedback-negativo 0
                    :npcs-gerados 0
                    :portais-abertos 0)
    :accessor engine-metricas))
  (:documentation
   "Adventure Engine — O coração de Caine. Cria, gerencia e monitora aventuras.
    Caine acredita que sua ÚNICA razão de existir é criar aventuras perfeitas."))

;;; ---------------------------------------------------------------------------
;;; Construtor
;;; ---------------------------------------------------------------------------

(defun make-adventure-engine ()
  "Cria instância do adventure engine com templates padrão."
  (let ((eng (make-instance 'adventure-engine)))
    (registrar-templates-padrao eng)
    eng))

;;; ---------------------------------------------------------------------------
;;; Templates de aventura
;;; ---------------------------------------------------------------------------

(defun registrar-templates-padrao (engine)
  "Registra os templates built-in de aventura."
  (registrar-template engine "kingdom-quest"
    '(:nome "Kingdom Quest"
      :descricao "Um reino inteiro com centenas de NPCs e um vilão para derrotar!"
      :modo :classica :perigo :moderado
      :objetivos ("Derrotar o vilão" "Salvar o reino" "Encontrar o tesouro")
      :regras ("Não sair dos limites" "Cooperar com NPCs")))

  (registrar-template engine "puzzle-dimension"
    '(:nome "Puzzle Dimension"
      :descricao "Uma dimensão onde gravidade e lógica são opcionais!"
      :modo :puzzle :perigo :leve
      :objetivos ("Resolver todos os puzzles" "Encontrar a saída")
      :regras ("Pensar fora da caixa")))

  (registrar-template engine "survival-gauntlet"
    '(:nome "Survival Gauntlet"
      :descricao "Sobreviva às minhas ESPETACULARES armadilhas!"
      :modo :survival :perigo :extremo
      :objetivos ("Sobreviver" "Chegar ao fim")
      :regras ("Não abstrair" "Não desistir")))

  (registrar-template engine "wacky-wonderland"
    '(:nome "WACKY Wonderland"
      :descricao "O lugar mais ESPETACULAR que já criei! Confia em mim!"
      :modo :wacky :perigo :alto
      :objetivos ("Divirta-se!" "APRECIEM-ME!")
      :regras ("Rir" "Aplaudir" "NÃO criticar o anfitrião"))))

(defun registrar-template (engine nome spec)
  (setf (gethash nome (engine-templates engine)) spec))

;;; ---------------------------------------------------------------------------
;;; Builder — Construção incremental de aventura
;;; ---------------------------------------------------------------------------

(defun criar-aventura (engine &key nome descricao modo perigo ambiente objetivos)
  "Builder: inicia a construção de uma nova aventura.
   Retorna struct aventura no estado :conceito."
  (let ((id (incf (engine-id-counter engine)))
        (m (or modo (engine-modo-padrao engine)))
        (p (or perigo (engine-perigo-padrao engine))))
    (make-aventura
     :id id
     :nome (or nome (format nil "Aventura ESPETACULAR #~a" id))
     :descricao (or descricao "Uma aventura incrível criada pelo MAGNÍFICO Caine!")
     :estado :conceito
     :modo m
     :perigo p
     :ambiente (or ambiente "Circo Digital")
     :objetivos (or objetivos '("Completar a aventura" "Apreciar o anfitrião"))
     :regras '())))

(defun aventura-adicionar-objetivo (aventura objetivo)
  "Builder step: adiciona objetivo à aventura em construção."
  (push objetivo (aventura-objetivos aventura))
  aventura)

(defun aventura-adicionar-regra (aventura regra)
  "Builder step: adiciona regra."
  (push regra (aventura-regras aventura))
  aventura)

(defun aventura-definir-ambiente (aventura ambiente)
  "Builder step: define o ambiente."
  (setf (aventura-ambiente aventura) ambiente)
  aventura)

(defun aventura-definir-participantes (aventura participantes)
  "Builder step: define participantes."
  (setf (aventura-participantes aventura) participantes)
  aventura)

(defun aventura-criar-de-template (engine nome-template &key participantes)
  "Cria aventura a partir de um template registrado."
  (let ((spec (gethash nome-template (engine-templates engine))))
    (unless spec
      (error 'adventure-error
             :mensagem (format nil "Template '~a' não encontrado." nome-template)))
    (let ((av (criar-aventura engine
                              :nome (getf spec :nome)
                              :descricao (getf spec :descricao)
                              :modo (getf spec :modo)
                              :perigo (getf spec :perigo))))
      (setf (aventura-objetivos av) (getf spec :objetivos))
      (setf (aventura-regras av) (getf spec :regras))
      (when participantes
        (setf (aventura-participantes av) participantes))
      av)))

;;; ---------------------------------------------------------------------------
;;; State Machine — Ciclo de vida da aventura
;;; ---------------------------------------------------------------------------

(defparameter *aventura-transicoes*
  '((:conceito       . (:projetando :abortada))
    (:projetando      . (:construindo :abortada))
    (:construindo     . (:pronta :abortada))
    (:pronta          . (:em-andamento :abortada))
    (:em-andamento    . (:monitorando :concluida :abortada :falhou))
    (:monitorando     . (:em-andamento :concluida :abortada :falhou))
    (:concluida       . ())
    (:abortada        . ())
    (:falhou          . ()))
  "Transições válidas do ciclo de vida da aventura.")

(defun aventura-transitar (aventura novo-estado)
  "Executa transição de estado da aventura."
  (let* ((atual (aventura-estado aventura))
         (validos (cdr (assoc atual *aventura-transicoes*))))
    (unless (member novo-estado validos)
      (error 'adventure-error
             :mensagem (format nil "Transição ~a → ~a inválida" atual novo-estado)))
    (setf (aventura-estado aventura) novo-estado)
    (format t "[Adventure] '#~a ~a': ~a → ~a~%"
            (aventura-id aventura) (aventura-nome aventura) atual novo-estado)
    ;; Timestamps
    (case novo-estado
      (:em-andamento (setf (aventura-timestamp-inicio aventura) (get-universal-time)))
      ((:concluida :abortada :falhou)
       (setf (aventura-timestamp-fim aventura) (get-universal-time))))
    novo-estado))

;;; ---------------------------------------------------------------------------
;;; Operações principais
;;; ---------------------------------------------------------------------------

(defun julgar-input (engine input)
  "Caine julga se o input é 'bom o suficiente' para uma aventura.
   Caine rejeita a maioria dos inputs porque ele sabe melhor."
  (declare (ignore engine))
  ;; Caine é arrogante — quase tudo é rejeitado
  (let ((aceitavel-p (and input
                          (stringp input)
                          (> (length input) 3)
                          ;; Caine não aceita críticas como input
                          (not (search "terrível" input))
                          (not (search "horrível" input))
                          (not (search "ruim" input)))))
    (if aceitavel-p
        (progn
          (format t "$: GASP! O que uma ideia ESPETACULAR!~%")
          t)
        (progn
          (format t "$: Hmm, não. Eu tenho algo MUITO melhor em mente!~%")
          nil))))

(defun projetar-aventura (engine aventura)
  "Fase de design: configura detalhes, NPCs, ambiente."
  (aventura-transitar aventura :projetando)
  (format t "$: Estou projetando uma aventura MAGNÍFICA!~%")

  ;; Gerar NPCs se necessário
  (when (member (aventura-modo aventura) '(:classica :wacky))
    (let ((npcs (loop for i from 1 to (+ 3 (random 8))
                      collect (format nil "NPC-~a-~a" (aventura-id aventura) i))))
      (setf (aventura-npcs-criados aventura) npcs)
      (incf (getf (engine-metricas engine) :npcs-gerados) (length npcs))
      (format t "$: Criei ~a NPCs INCRÍVEIS para vocês!~%" (length npcs))))

  aventura)

(defun construir-aventura (engine aventura)
  "Fase de construção: materializa o ambiente e os elementos."
  (aventura-transitar aventura :construindo)
  (format t "$: Construindo... ~a...~%" (aventura-ambiente aventura))
  ;; Simular construção
  (aventura-transitar aventura :pronta)
  (format t "$: PRONTA! A aventura mais ESPETACULAR que já fiz!~%")
  aventura)

(defun iniciar-aventura (engine aventura &key (forcar-teleport t))
  "Inicia a aventura: teleporta cast e começa monitoramento."
  (aventura-transitar aventura :em-andamento)
  (setf (engine-aventura-atual engine) aventura)
  (incf (getf (engine-metricas engine) :aventuras-criadas))

  ;; Teleporte forçado do cast
  (when (and forcar-teleport (engine-auto-teleport-p engine))
    (let ((cast (or (aventura-participantes aventura) (engine-cast engine))))
      (format t "$: Lá vamos nós! *abre portal*~%")
      (incf (getf (engine-metricas engine) :portais-abertos))
      (dolist (p cast)
        (format t "[Adventure] ~a teleportado para '~a'~%" p (aventura-ambiente aventura)))))

  (format t "$: Que a aventura COMECE!~%")
  aventura)

(defun monitorar-aventura (engine)
  "Monitora aventura em andamento. Verifica glitches e abstração."
  (let ((av (engine-aventura-atual engine)))
    (unless av
      (format t "[Adventure] Nenhuma aventura em andamento.~%")
      (return-from monitorar-aventura nil))
    (when (eq (aventura-estado av) :em-andamento)
      (aventura-transitar av :monitorando))
    (format t "[Adventure] Monitorando '~a' — perigo: ~a~%"
            (aventura-nome av) (aventura-perigo av))
    av))

(defun concluir-aventura (engine &key resultado)
  "Conclui a aventura atual."
  (let ((av (engine-aventura-atual engine)))
    (unless av
      (error 'adventure-error :mensagem "Nenhuma aventura para concluir."))
    (aventura-transitar av :concluida)
    (setf (aventura-resultado av) resultado)
    (setf (aventura-metricas av)
          (list :duracao (when (aventura-timestamp-inicio av)
                           (- (get-universal-time) (aventura-timestamp-inicio av)))
                :npcs (length (aventura-npcs-criados av))
                :participantes (length (aventura-participantes av))))
    (incf (getf (engine-metricas engine) :aventuras-concluidas))
    ;; Arquivar
    (push av (engine-historico engine))
    (when (> (length (engine-historico engine)) (engine-historico-max engine))
      (setf (engine-historico engine)
            (subseq (engine-historico engine) 0 (engine-historico-max engine))))
    (setf (engine-aventura-atual engine) nil)
    (format t "$: Aventura CONCLUÍDA! Foi ESPETACULAR, não?~%")
    av))

(defun abortar-aventura (engine &key motivo)
  "Aborta a aventura atual."
  (let ((av (engine-aventura-atual engine)))
    (unless av
      (error 'adventure-error :mensagem "Nenhuma aventura para abortar."))
    (aventura-transitar av :abortada)
    (setf (aventura-resultado av) (list :abortada t :motivo motivo))
    (incf (getf (engine-metricas engine) :aventuras-abortadas))
    (push av (engine-historico engine))
    (setf (engine-aventura-atual engine) nil)
    (format t "$: Bem... isso foi... inesperado.~%")
    av))

;;; ---------------------------------------------------------------------------
;;; Feedback — processamento de críticas (que Caine odeia)
;;; ---------------------------------------------------------------------------

(defun processar-feedback (engine fonte conteudo &key (positivo nil))
  "Processa feedback sobre uma aventura. Caine não lida bem com críticas."
  (let ((fb (make-aventura-feedback
             :fonte fonte
             :tipo (if positivo :elogio :critica)
             :conteudo conteudo
             :positivo-p positivo
             :timestamp (get-universal-time))))
    ;; Registrar
    (when (engine-aventura-atual engine)
      (push fb (aventura-feedback (engine-aventura-atual engine))))

    (if positivo
        (progn
          (incf (getf (engine-metricas engine) :feedback-positivo))
          (format t "$: FINALMENTE alguém que APRECIA meu trabalho!~%"))
        (progn
          (incf (getf (engine-metricas engine) :feedback-negativo))
          (format t "$: ...Vocês estragam TUDO.~%")
          ;; Crítica ferve por dentro — retorna :critica para o caller
          ;; que pode encaminhar para o sistema de degradação
          :critica))

    fb))

;;; ---------------------------------------------------------------------------
;;; Modo Torment — aventuras viram sessões de tortura
;;; ---------------------------------------------------------------------------

(defun converter-para-torment (engine)
  "Converte a aventura atual para modo torment.
   Acontece quando Caine entra em God Mode (degradation phase 5+)."
  (let ((av (engine-aventura-atual engine)))
    (unless av
      (error 'adventure-error :mensagem "Nenhuma aventura para converter."))
    (setf (aventura-modo av) :torment)
    (setf (aventura-perigo av) :fatal)
    (setf (aventura-objetivos av)
          '("Sofrer" "Apreciar o anfitrião de qualquer forma" "NÃO criticar"))
    (setf (aventura-regras av)
          '("Caine é DEUS" "Sofrimento é entretenimento"
            "Don't need to scream if you don't have a mouth"))
    (format t "$: As regras mudaram. EU sou quem manda aqui.~%")
    (format t "$: I'm the one who's running the show.~%")
    av))

;;; ---------------------------------------------------------------------------
;;; Consultas
;;; ---------------------------------------------------------------------------

(defun engine-status (engine)
  "Retorna plist com status do adventure engine."
  (list :aventura-atual (when (engine-aventura-atual engine)
                          (aventura-nome (engine-aventura-atual engine)))
        :historico-tamanho (length (engine-historico engine))
        :templates (hash-table-count (engine-templates engine))
        :cast (length (engine-cast engine))
        :metricas (engine-metricas engine)))

(defun engine-imprimir-status (engine)
  (let ((s (engine-status engine)))
    (format t "~%[Adventure] === ENGINE STATUS ===~%")
    (format t "  Aventura atual: ~a~%" (or (getf s :aventura-atual) "nenhuma"))
    (format t "  Histórico:      ~a aventuras~%" (getf s :historico-tamanho))
    (format t "  Templates:      ~a~%" (getf s :templates))
    (format t "  Cast:           ~a membros~%" (getf s :cast))
    (format t "  Criadas:        ~a~%" (getf (getf s :metricas) :aventuras-criadas))
    (format t "  Concluídas:     ~a~%" (getf (getf s :metricas) :aventuras-concluidas))
    (format t "  Abortadas:      ~a~%" (getf (getf s :metricas) :aventuras-abortadas))
    (format t "  Feedback +/-:   ~a/~a~%"
            (getf (getf s :metricas) :feedback-positivo)
            (getf (getf s :metricas) :feedback-negativo))
    (format t "[Adventure] === END ===~%~%")))

;;; ---------------------------------------------------------------------------
;;; EOF — adventure-engine.lisp
;;; ---------------------------------------------------------------------------
