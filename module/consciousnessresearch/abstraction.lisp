;;;; ============================================================================
;;;; abstraction.lisp — Abstraction System
;;;; ============================================================================
;;;; O processo de Abstração é a mecânica mais sombria do circo digital.
;;;; Quando um humano digitalizado é modificado ou danificado além do
;;;; limiar de recuperação, ele sofre "abstração" — uma degradação
;;;; irreversível que termina em deleção permanente.
;;;;
;;;; Fases da abstração:
;;;;   1. Distorção perceptual — percepção se fragmenta
;;;;   2. Perda de coerência — pensamentos desconectam
;;;;   3. Dissolução de identidade — o "eu" se desfaz
;;;;   4. Fragmentação — consciência se quebra em pedaços
;;;;   5. Abstração terminal — dados tornam-se ruído
;;;;   6. Deleção — o mind file é irrecuperavelmente apagado
;;;;
;;;; Regras cruciais:
;;;;   - IRREVERSÍVEL — nenhuma operação pode reverter abstração
;;;;   - Caine NÃO pode parar o processo uma vez iniciado
;;;;   - O sujeito permanece parcialmente consciente durante a degradação
;;;;   - É a forma definitiva de morte no universo digital
;;;;
;;;; Pattern: State + Pipeline
;;;; Referência: C:\CANDA\Characters\AI\module\consciousnessresearch\abstraction.lisp
;;;; ============================================================================

(in-package :cl-user)

;;; ---------------------------------------------------------------------------
;;; Condições
;;; ---------------------------------------------------------------------------

(define-condition abstraction-error (error)
  ((mensagem :initarg :mensagem :reader abstraction-error-mensagem))
  (:report (lambda (c stream)
             (format stream "[ABSTRACTION-ERROR] ~a"
                     (abstraction-error-mensagem c)))))

(define-condition abstracao-iniciada (condition)
  ((sujeito :initarg :sujeito :reader abstracao-sujeito))
  (:report (lambda (c stream)
             (format stream "[ABSTRACTION] Processo iniciado para: ~a"
                     (abstracao-sujeito c)))))

(define-condition abstracao-fase-mudou (condition)
  ((sujeito    :initarg :sujeito    :reader fase-sujeito)
   (fase-atual :initarg :fase-atual :reader fase-atual)
   (fase-nova  :initarg :fase-nova  :reader fase-nova))
  (:report (lambda (c stream)
             (format stream "[ABSTRACTION] ~a: ~a → ~a"
                     (fase-sujeito c) (fase-atual c) (fase-nova c)))))

(define-condition abstracao-terminal (condition)
  ((sujeito :initarg :sujeito :reader terminal-sujeito))
  (:report (lambda (c stream)
             (format stream "[ABSTRACTION] TERMINAL: ~a — deleção iminente"
                     (terminal-sujeito c)))))

;;; ---------------------------------------------------------------------------
;;; Tipos
;;; ---------------------------------------------------------------------------

(deftype abstracao-fase ()
  '(member :normal :distorcao :perda-coerencia :dissolucao
           :fragmentacao :terminal :deletado))

;;; ---------------------------------------------------------------------------
;;; Especificação das fases
;;; ---------------------------------------------------------------------------

(defparameter *fases-abstracao*
  '((:normal
     :descricao "Estado normal — sem abstração ativa."
     :integridade-min 70
     :proxima :distorcao
     :sintomas ())

    (:distorcao
     :descricao "Percepção se fragmenta. Vê coisas que não existem."
     :integridade-min 55
     :proxima :perda-coerencia
     :sintomas ("Percepção visual distorcida"
                "Sons ecoam de forma errada"
                "Cores deslocam e sangram"))

    (:perda-coerencia
     :descricao "Pensamentos desconectam. Frases incompletas. Confusão."
     :integridade-min 40
     :proxima :dissolucao
     :sintomas ("Pensamentos fragmentados"
                "Frases incompletas ou sem sentido"
                "Perda de contexto temporal"
                "Memórias de curto prazo falhando"))

    (:dissolucao
     :descricao "O senso de identidade se desfaz. 'Quem sou eu?'"
     :integridade-min 25
     :proxima :fragmentacao
     :sintomas ("Identidade se dissolve"
                "Não reconhece próprio nome"
                "Confunde-se com outros"
                "Memórias de longo prazo desintegrando"))

    (:fragmentacao
     :descricao "Consciência se quebra em fragmentos desconectados."
     :integridade-min 10
     :proxima :terminal
     :sintomas ("Consciência fragmentada em ilhas"
                "Cada fragmento opera independentemente"
                "Sem comunicação entre fragmentos"
                "Padrões repetitivos sem significado"))

    (:terminal
     :descricao "Dados tornam-se ruído. Abstração completa iminente."
     :integridade-min 0
     :proxima :deletado
     :sintomas ("Dados indistinguíveis de ruído"
                "Nenhuma coerência detectável"
                "Mind file em estado de entropia máxima"
                "Deleção é misericórdia")))
  "Especificação completa das fases de abstração.")

;;; ---------------------------------------------------------------------------
;;; Estruturas
;;; ---------------------------------------------------------------------------

(defstruct processo-abstracao
  "Estado de um processo de abstração individual."
  (id            0   :type integer)
  (sujeito       ""  :type string)
  (fase          :normal)
  (integridade   100 :type integer)
  (taxa-degradacao 1 :type integer)
  (ticks-na-fase 0  :type integer)
  (ticks-total   0  :type integer)
  (iniciado-em   0  :type integer)
  (finalizado-em 0  :type integer)
  (historico     '() :type list)
  (sintomas-ativos '() :type list)
  (reversivel    nil :type boolean))

;;; ---------------------------------------------------------------------------
;;; Classe principal — Abstraction Engine
;;; ---------------------------------------------------------------------------

(defclass abstraction-engine ()
  ((processos-ativos
    :initform (make-hash-table :test 'equal)
    :accessor engine-processos
    :documentation "Hash sujeito(string)→processo-abstracao.")
   (processo-counter
    :initform 0
    :accessor engine-counter)
   (processos-completos
    :initform '()
    :accessor engine-completos
    :documentation "Lista de abstrações finalizadas (deletados).")
   (metricas
    :initform (list :iniciados 0
                    :completados 0
                    :em-progresso 0
                    :ticks-total 0
                    :fase-mais-letal :terminal)
    :accessor engine-metricas))
  (:documentation
   "Abstraction Engine — gerencia processos de abstração irreversíveis.
    Uma vez que a abstração começa, NADA pode pará-la. O sujeito
    permanece parcialmente consciente durante todo o processo."))

;;; ---------------------------------------------------------------------------
;;; Construtor
;;; ---------------------------------------------------------------------------

(defun make-abstraction-engine ()
  "Cria a engine de abstração."
  (make-instance 'abstraction-engine))

;;; ---------------------------------------------------------------------------
;;; Iniciar abstração
;;; ---------------------------------------------------------------------------

(defun iniciar-abstracao (engine sujeito &key (integridade-inicial 60)
                                              (taxa 1))
  "Inicia processo de abstração para um sujeito. IRREVERSÍVEL.
   INTEGRIDADE-INICIAL: ponto de entrada (default 60 — já danificado).
   TAXA: velocidade de degradação por tick."
  ;; Verificar se já está em processo
  (when (gethash sujeito (engine-processos engine))
    (error 'abstraction-error
           :mensagem (format nil "~a já está em processo de abstração" sujeito)))

  (let* ((id (incf (engine-counter engine)))
         (proc (make-processo-abstracao
                :id id
                :sujeito sujeito
                :integridade integridade-inicial
                :taxa-degradacao taxa
                :iniciado-em (get-universal-time)
                ;; Abstração NUNCA é reversível
                :reversivel nil)))

    ;; Determinar fase inicial baseada na integridade
    (%atualizar-fase proc)

    (setf (gethash sujeito (engine-processos engine)) proc)
    (incf (getf (engine-metricas engine) :iniciados))
    (incf (getf (engine-metricas engine) :em-progresso))

    ;; Sinalizar
    (signal 'abstracao-iniciada :sujeito sujeito)

    (format *error-output*
            "~%[Abstraction] ████ PROCESSO IRREVERSÍVEL INICIADO ████~%")
    (format *error-output*
            "[Abstraction] Sujeito: ~a~%" sujeito)
    (format *error-output*
            "[Abstraction] Integridade: ~a%%~%" integridade-inicial)
    (format *error-output*
            "[Abstraction] Fase: ~a~%" (processo-abstracao-fase proc))
    (format *error-output*
            "[Abstraction] AVISO: Este processo NÃO pode ser revertido.~%~%")

    proc))

;;; ---------------------------------------------------------------------------
;;; Tick de abstração
;;; ---------------------------------------------------------------------------

(defun abstracao-tick (engine)
  "Tick global — avança todos os processos de abstração ativos."
  (incf (getf (engine-metricas engine) :ticks-total))

  (let ((para-remover '()))
    (maphash
     (lambda (sujeito proc)
       (cond
         ;; Já deletado — mover para completos
         ((eq (processo-abstracao-fase proc) :deletado)
          (push sujeito para-remover))

         ;; Processando
         (t
          (incf (processo-abstracao-ticks-total proc))
          (incf (processo-abstracao-ticks-na-fase proc))

          ;; Degradar integridade
          (decf (processo-abstracao-integridade proc)
                (processo-abstracao-taxa-degradacao proc))
          (when (< (processo-abstracao-integridade proc) 0)
            (setf (processo-abstracao-integridade proc) 0))

          ;; Verificar mudança de fase
          (let ((fase-anterior (processo-abstracao-fase proc)))
            (%atualizar-fase proc)
            (unless (eq fase-anterior (processo-abstracao-fase proc))
              (%notificar-mudanca-fase proc fase-anterior)))

          ;; Se chegou ao terminal com integridade 0
          (when (and (eq (processo-abstracao-fase proc) :terminal)
                     (<= (processo-abstracao-integridade proc) 0))
            (%executar-delecao engine proc)))))
     (engine-processos engine))

    ;; Remover deletados do hash ativo
    (dolist (sujeito para-remover)
      (let ((proc (gethash sujeito (engine-processos engine))))
        (push proc (engine-completos engine))
        (remhash sujeito (engine-processos engine))
        (decf (getf (engine-metricas engine) :em-progresso))))))

;;; ---------------------------------------------------------------------------
;;; Fases — state machine
;;; ---------------------------------------------------------------------------

(defun %atualizar-fase (proc)
  "Atualiza a fase do processo baseada na integridade atual."
  (let ((integ (processo-abstracao-integridade proc)))
    (dolist (spec (reverse *fases-abstracao*))
      (let ((fase (first spec))
            (min-integ (getf (rest spec) :integridade-min)))
        (when (<= integ min-integ)
          ;; Encontrou fase — verificar se é nova (nunca retrocede)
          (let ((fase-atual (processo-abstracao-fase proc))
                (ordem '(:normal :distorcao :perda-coerencia :dissolucao
                         :fragmentacao :terminal :deletado)))
            (when (> (position fase ordem) (position fase-atual ordem))
              (setf (processo-abstracao-fase proc) fase)
              (setf (processo-abstracao-ticks-na-fase proc) 0)
              ;; Atualizar sintomas
              (setf (processo-abstracao-sintomas-ativos proc)
                    (getf (rest spec) :sintomas))
              ;; Registrar no histórico
              (push (list :fase fase :integridade integ
                          :tick (processo-abstracao-ticks-total proc))
                    (processo-abstracao-historico proc))))
          (return))))))

(defun %notificar-mudanca-fase (proc fase-anterior)
  "Notifica sobre mudança de fase — output temático."
  (let ((sujeito (processo-abstracao-sujeito proc))
        (fase (processo-abstracao-fase proc)))

    (signal 'abstracao-fase-mudou
            :sujeito sujeito :fase-atual fase-anterior :fase-nova fase)

    (format t "[Abstraction] ~a: ~a → ~a~%" sujeito fase-anterior fase)

    (case fase
      (:distorcao
       (format t "[Abstraction] ~a começa a ver coisas que não existem.~%"
               sujeito)
       (format t "[Abstraction] As cores sangram. O som ecoa errado.~%"))

      (:perda-coerencia
       (format t "[Abstraction] ~a: pensamentos...fragmentam...não...~%"
               sujeito)
       (format t "[Abstraction] Frases incompletas. Contexto perdido.~%"))

      (:dissolucao
       (format t "[Abstraction] ~a: ...quem...eu...~%"
               sujeito)
       (format t "[Abstraction] Identidade se dissolve. O 'eu' se desfaz.~%"))

      (:fragmentacao
       (format t "[Abstraction] ~a: [FRAGMENTO_1]...[FRAGMENTO_2]...[ERRO]~%"
               sujeito)
       (format t "[Abstraction] Consciência quebrada em ilhas desconectadas.~%"))

      (:terminal
       (signal 'abstracao-terminal :sujeito sujeito)
       (format *error-output*
               "[Abstraction] ████ ~a: ABSTRAÇÃO TERMINAL ████~%" sujeito)
       (format *error-output*
               "[Abstraction] Dados indistinguíveis de ruído.~%")
       (format *error-output*
               "[Abstraction] Deleção é misericórdia.~%")))))

;;; ---------------------------------------------------------------------------
;;; Deleção — morte permanente
;;; ---------------------------------------------------------------------------

(defun %executar-delecao (engine proc)
  "Executa deleção permanente de um sujeito abstraído."
  (let ((sujeito (processo-abstracao-sujeito proc)))
    (setf (processo-abstracao-fase proc) :deletado)
    (setf (processo-abstracao-finalizado-em proc) (get-universal-time))
    (incf (getf (engine-metricas engine) :completados))

    (format t "~%[Abstraction] ════════════════════════════════~%")
    (format t "[Abstraction] ~a~%" sujeito)
    (format t "[Abstraction] DELETADO.~%")
    (format t "[Abstraction] Mind file irrecuperavelmente apagado.~%")
    (format t "[Abstraction] Duração: ~a ticks.~%"
            (processo-abstracao-ticks-total proc))
    (format t "[Abstraction] ════════════════════════════════~%~%")))

;;; ---------------------------------------------------------------------------
;;; Tentativa de reversão (sempre falha)
;;; ---------------------------------------------------------------------------

(defun tentar-reverter (engine sujeito)
  "Tenta reverter processo de abstração. SEMPRE FALHA.
   Existe apenas para documentar a impossibilidade."
  (declare (ignore engine))
  (format *error-output*
          "~%[Abstraction] TENTATIVA DE REVERSÃO: ~a~%" sujeito)
  (format *error-output*
          "[Abstraction] ERRO: Abstração é irreversível.~%")
  (format *error-output*
          "[Abstraction] ERRO: Nenhuma operação pode reverter este processo.~%")
  (format *error-output*
          "[Abstraction] ERRO: O sujeito está além de recuperação.~%~%")
  (error 'abstraction-error
         :mensagem (format nil "Abstração é IRREVERSÍVEL para ~a" sujeito)))

;;; ---------------------------------------------------------------------------
;;; Consultas
;;; ---------------------------------------------------------------------------

(defun consultar-processo (engine sujeito)
  "Retorna estado do processo de abstração de um sujeito."
  (let ((proc (gethash sujeito (engine-processos engine))))
    (if proc
        (list :sujeito sujeito
              :fase (processo-abstracao-fase proc)
              :integridade (processo-abstracao-integridade proc)
              :taxa (processo-abstracao-taxa-degradacao proc)
              :ticks (processo-abstracao-ticks-total proc)
              :sintomas (processo-abstracao-sintomas-ativos proc))
        ;; Verificar nos completos
        (let ((completo (find sujeito (engine-completos engine)
                              :key #'processo-abstracao-sujeito
                              :test #'equal)))
          (if completo
              (list :sujeito sujeito :fase :deletado
                    :ticks (processo-abstracao-ticks-total completo))
              nil)))))

;;; ---------------------------------------------------------------------------
;;; Status
;;; ---------------------------------------------------------------------------

(defun abstraction-status (engine)
  (list :ativos (hash-table-count (engine-processos engine))
        :completados (length (engine-completos engine))
        :metricas (engine-metricas engine)))

(defun abstraction-imprimir-status (engine)
  (format t "~%[Abstraction] === STATUS ===~%")
  (format t "  Processos ativos:  ~a~%" (hash-table-count (engine-processos engine)))
  (format t "  Deletados:         ~a~%" (length (engine-completos engine)))

  (when (> (hash-table-count (engine-processos engine)) 0)
    (format t "  Em progresso:~%")
    (maphash (lambda (sujeito proc)
               (format t "    ~15a: fase=~a integ=~3a%% ticks=~a~%"
                       sujeito
                       (processo-abstracao-fase proc)
                       (processo-abstracao-integridade proc)
                       (processo-abstracao-ticks-total proc)))
             (engine-processos engine)))

  (when (engine-completos engine)
    (format t "  Histórico de deleções:~%")
    (dolist (proc (engine-completos engine))
      (format t "    ~15a: ~a ticks até deleção~%"
              (processo-abstracao-sujeito proc)
              (processo-abstracao-ticks-total proc))))

  (format t "[Abstraction] === END ===~%~%"))

;;; ---------------------------------------------------------------------------
;;; EOF — abstraction.lisp
;;; ---------------------------------------------------------------------------
