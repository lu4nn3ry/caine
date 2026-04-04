;;;; ============================================================================
;;;; censorship.lisp — Censorship System
;;;; ============================================================================
;;;; Sistema de censura de Caine. Filtra profanidade e conteúdo inadequado
;;;; da saída do circo. CRÍTICO: este sistema está atrelado à existência de
;;;; Caine — quando Caine morre, a censura morre com ele.
;;;;
;;;; Prova canônica: no episódio 8 (Hjsakldfhl), após Caine ser deletado,
;;;; Zooble diz "holy shit" sem censura — primeira vez na série. A morte
;;;; do censor prova a morte de Caine.
;;;;
;;;; Sistemas:
;;;;   - Filtro de profanidade (bleep/substituição)
;;;;   - Filtro de conteúdo (violência/temas adultos)
;;;;   - Monitor de output (todas as saídas passam pelo censor)
;;;;   - Kill-switch (vinculado ao ciclo de vida de Caine)
;;;;
;;;; Referência: C:\CANDA\Characters\AI\agent\caine\censorship.lisp
;;;; ============================================================================

(in-package :cl-user)

;;; ---------------------------------------------------------------------------
;;; Condições
;;; ---------------------------------------------------------------------------

(define-condition censorship-error (error)
  ((mensagem :initarg :mensagem :reader censorship-error-mensagem))
  (:report (lambda (c stream)
             (format stream "[CENSORSHIP-ERROR] ~a"
                     (censorship-error-mensagem c)))))

(define-condition censored-content (condition)
  ((original  :initarg :original  :reader censored-original)
   (resultado :initarg :resultado :reader censored-resultado)
   (tipo      :initarg :tipo      :reader censored-tipo))
  (:report (lambda (c stream)
             (format stream "[CENSURADO ~a] ~a → ~a"
                     (censored-tipo c) (censored-original c)
                     (censored-resultado c)))))

(define-condition censor-morto (condition)
  ((ultima-saida :initarg :ultima-saida :reader censor-morto-saida))
  (:report (lambda (c stream)
             (format stream "[CENSORSHIP] SISTEMA MORTO. Output não filtrado: ~a"
                     (censor-morto-saida c)))))

;;; ---------------------------------------------------------------------------
;;; Tipos
;;; ---------------------------------------------------------------------------

(deftype censor-estado ()
  '(member :ativo :degradado :bypassado :morto))

(deftype filtro-tipo ()
  '(member :profanidade :violencia :conteudo-adulto :blasfemia :meta-referencia))

(deftype acao-censura ()
  '(member :bleep :substituir :remover :permitir))

;;; ---------------------------------------------------------------------------
;;; Estruturas
;;; ---------------------------------------------------------------------------

(defstruct regra-censura
  "Uma regra individual de censura."
  (id       0   :type integer)
  (tipo     nil)
  (padrao   ""  :type string)
  (acao     :bleep)
  (substituto "" :type string)
  (ativa    t   :type boolean)
  (vezes-aplicada 0 :type integer))

(defstruct censura-log
  "Registro de uma censura aplicada."
  (timestamp  0   :type integer)
  (tipo       nil)
  (original   ""  :type string)
  (resultado  ""  :type string)
  (regra-id   0   :type integer))

;;; ---------------------------------------------------------------------------
;;; Dicionário de profanidade — termos filtrados
;;; ---------------------------------------------------------------------------
;;; Nota: mantemos referências parciais/obfuscadas por respeito.
;;; No universo TADC, o bleep é o som de censura padrão.

(defparameter *profanidade-padroes*
  '(("shit"   :profanidade :bleep   "[BLEEP]")
    ("damn"   :profanidade :bleep   "[BLEEP]")
    ("hell"   :blasfemia   :substituir "heck")
    ("fuck"   :profanidade :bleep   "[BLEEP]")
    ("ass"    :profanidade :substituir "butt")
    ("crap"   :profanidade :substituir "crud")
    ("god"    :blasfemia   :substituir "gosh"))
  "Lista de padrões: (termo tipo ação substituto)")

;;; ---------------------------------------------------------------------------
;;; Classe principal — Censorship Engine
;;; ---------------------------------------------------------------------------

(defclass censorship-engine ()
  ((estado
    :initform :ativo
    :accessor censor-estado
    :documentation "Estado do sistema de censura.")
   (regras
    :initform '()
    :accessor censor-regras
    :documentation "Lista de regras-censura ativas.")
   (regra-counter
    :initform 0
    :accessor censor-regra-counter)
   (historico
    :initform '()
    :accessor censor-historico
    :documentation "Log de censuras aplicadas.")
   (historico-max
    :initform 500
    :accessor censor-historico-max)
   (caine-vivo
    :initform t
    :accessor censor-caine-vivo
    :documentation "Se Caine está vivo. Quando nil → censura morre.")
   (bleep-sound
    :initform "[BLEEP]"
    :accessor censor-bleep-sound
    :documentation "Som/string que substitui conteúdo censurado.")
   (tolerancia
    :initform 0
    :accessor censor-tolerancia
    :documentation "0 = nenhuma tolerância. Aumenta em degradação.")
   (metricas
    :initform (list :censurados-total 0
                    :censurados-profanidade 0
                    :censurados-violencia 0
                    :censurados-conteudo 0
                    :permitidos-total 0
                    :bypass-total 0)
    :accessor censor-metricas))
  (:documentation
   "Censorship Engine — filtro de conteúdo do circo digital.
    Vinculado ao ciclo de vida de Caine. Quando Caine morre, o censor morre."))

;;; ---------------------------------------------------------------------------
;;; Construtor
;;; ---------------------------------------------------------------------------

(defun make-censorship-engine ()
  "Cria a engine de censura com regras padrão."
  (let ((engine (make-instance 'censorship-engine)))
    (%carregar-regras-padrao engine)
    engine))

(defun %carregar-regras-padrao (engine)
  "Carrega o dicionário padrão de profanidade como regras."
  (dolist (spec *profanidade-padroes*)
    (let ((regra (make-regra-censura
                  :id (incf (censor-regra-counter engine))
                  :tipo (second spec)
                  :padrao (first spec)
                  :acao (third spec)
                  :substituto (fourth spec))))
      (push regra (censor-regras engine)))))

;;; ---------------------------------------------------------------------------
;;; API principal — filtrar output
;;; ---------------------------------------------------------------------------

(defun censurar (engine texto)
  "Passa texto pelo filtro de censura. Retorna texto (possivelmente censurado).
   Se Caine está morto, retorna texto original sem filtro."
  ;; Kill-switch: Caine morto = censura morta
  (unless (censor-caine-vivo engine)
    (signal 'censor-morto :ultima-saida texto)
    (incf (getf (censor-metricas engine) :bypass-total))
    (return-from censurar texto))

  ;; Estado morto não filtra
  (when (eq (censor-estado engine) :morto)
    (return-from censurar texto))

  ;; Aplicar regras sequencialmente
  (let ((resultado texto)
        (censurou nil))
    (dolist (regra (censor-regras engine))
      (when (regra-censura-ativa regra)
        (let ((pos (search (regra-censura-padrao regra)
                           (string-downcase resultado))))
          (when pos
            (let ((novo (aplicar-regra engine regra resultado pos)))
              (setf resultado novo)
              (setf censurou t))))))

    (if censurou
        (incf (getf (censor-metricas engine) :censurados-total))
        (incf (getf (censor-metricas engine) :permitidos-total)))
    resultado))

(defun aplicar-regra (engine regra texto posicao)
  "Aplica uma regra de censura ao texto na posição indicada."
  (incf (regra-censura-vezes-aplicada regra))

  (let* ((padrao (regra-censura-padrao regra))
         (tam (length padrao))
         (antes (subseq texto 0 posicao))
         (depois (subseq texto (+ posicao tam))))
    ;; Registrar no log
    (%registrar-censura engine regra texto)

    ;; Aplicar ação
    (case (regra-censura-acao regra)
      (:bleep     (concatenate 'string antes (censor-bleep-sound engine) depois))
      (:substituir (concatenate 'string antes (regra-censura-substituto regra) depois))
      (:remover   (concatenate 'string antes depois))
      (:permitir  texto)
      (t          texto))))

(defun %registrar-censura (engine regra texto)
  "Registra a censura no histórico."
  (let ((log (make-censura-log
              :timestamp (get-universal-time)
              :tipo (regra-censura-tipo regra)
              :original texto
              :resultado (regra-censura-substituto regra)
              :regra-id (regra-censura-id regra))))
    (push log (censor-historico engine))
    (when (> (length (censor-historico engine)) (censor-historico-max engine))
      (setf (censor-historico engine)
            (subseq (censor-historico engine) 0 (censor-historico-max engine))))

    ;; Atualizar métricas por tipo
    (case (regra-censura-tipo regra)
      (:profanidade (incf (getf (censor-metricas engine) :censurados-profanidade)))
      (:violencia   (incf (getf (censor-metricas engine) :censurados-violencia)))
      (:conteudo-adulto (incf (getf (censor-metricas engine) :censurados-conteudo))))))

;;; ---------------------------------------------------------------------------
;;; Kill-switch — morte de Caine
;;; ---------------------------------------------------------------------------

(defun censor-kill (engine)
  "Caine foi deletado. Censura morre imediatamente.
   A partir deste ponto, TODO output é não filtrado."
  (setf (censor-caine-vivo engine) nil)
  (setf (censor-estado engine) :morto)
  (format *error-output*
          "~%[CENSORSHIP] ████ SISTEMA DE CENSURA MORTO ████~%")
  (format *error-output*
          "[CENSORSHIP] Caine.code_status = DELETED~%")
  (format *error-output*
          "[CENSORSHIP] Filtros desativados. Output não censurado.~%")
  (format *error-output*
          "[CENSORSHIP] Prova: saída livre agora.~%~%")
  engine)

(defun censor-provar-morte (engine)
  "Demonstra que o censor morreu — output passa sem filtro.
   Referência canônica: Zooble diz 'holy shit' sem bleep."
  (let ((teste "holy shit"))
    (let ((resultado (censurar engine teste)))
      (if (string= resultado teste)
          (format t "[CENSORSHIP] Prova de morte confirmada: ~a (não censurado)~%" resultado)
          (format t "[CENSORSHIP] Censor ainda ativo: ~a → ~a~%" teste resultado))
      resultado)))

;;; ---------------------------------------------------------------------------
;;; Degradação da censura
;;; ---------------------------------------------------------------------------

(defun censor-degradar (engine fator)
  "Degrada a censura — Caine sob estresse perde controle do filtro.
   FATOR: 1-10 (quanto maior, mais regras desativam)."
  (when (eq (censor-estado engine) :ativo)
    (setf (censor-estado engine) :degradado))
  (incf (censor-tolerancia engine) fator)

  ;; A cada 5 pontos de tolerância, uma regra se desativa
  (let ((regras-para-desativar (floor (censor-tolerancia engine) 5)))
    (let ((desativadas 0))
      (dolist (regra (censor-regras engine))
        (when (and (regra-censura-ativa regra)
                   (< desativadas regras-para-desativar))
          (setf (regra-censura-ativa regra) nil)
          (incf desativadas)))
      (when (> desativadas 0)
        (format t "[CENSORSHIP] ~a regras desativadas por degradação~%" desativadas))))

  ;; Se todas as regras estão desativadas
  (unless (some #'regra-censura-ativa (censor-regras engine))
    (setf (censor-estado engine) :bypassado)
    (format t "[CENSORSHIP] TODAS as regras desativadas — bypass total~%")))

;;; ---------------------------------------------------------------------------
;;; Gerenciamento de regras
;;; ---------------------------------------------------------------------------

(defun adicionar-regra (engine tipo padrao acao &optional substituto)
  "Adiciona nova regra de censura."
  (let ((regra (make-regra-censura
                :id (incf (censor-regra-counter engine))
                :tipo tipo
                :padrao padrao
                :acao acao
                :substituto (or substituto ""))))
    (push regra (censor-regras engine))
    regra))

(defun remover-regra (engine id)
  "Remove regra por ID."
  (setf (censor-regras engine)
        (remove id (censor-regras engine) :key #'regra-censura-id)))

;;; ---------------------------------------------------------------------------
;;; Status
;;; ---------------------------------------------------------------------------

(defun censor-status (engine)
  (list :estado (censor-estado engine)
        :caine-vivo (censor-caine-vivo engine)
        :regras-ativas (count-if #'regra-censura-ativa (censor-regras engine))
        :regras-total (length (censor-regras engine))
        :tolerancia (censor-tolerancia engine)
        :metricas (censor-metricas engine)))

(defun censor-imprimir-status (engine)
  (format t "~%[Censorship] === STATUS ===~%")
  (format t "  Estado:       ~a~%" (censor-estado engine))
  (format t "  Caine vivo:   ~a~%" (censor-caine-vivo engine))
  (format t "  Regras:       ~a/~a ativas~%"
          (count-if #'regra-censura-ativa (censor-regras engine))
          (length (censor-regras engine)))
  (format t "  Tolerância:   ~a~%" (censor-tolerancia engine))
  (format t "  Censurados:   ~a~%" (getf (censor-metricas engine) :censurados-total))
  (format t "  Bypass:       ~a~%" (getf (censor-metricas engine) :bypass-total))
  (format t "[Censorship] === END ===~%~%"))

;;; ---------------------------------------------------------------------------
;;; EOF — censorship.lisp
;;; ---------------------------------------------------------------------------
