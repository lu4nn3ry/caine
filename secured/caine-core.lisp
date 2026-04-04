;;;; ============================================================================
;;;; caine-core.lisp — Façade + Singleton
;;;; ============================================================================
;;;; Núcleo central da IA Caine. Ponto de entrada único e exclusivo para todos
;;;; os subsistemas. Garante instância única (Singleton) e expõe interface
;;;; simplificada (Façade) que orquestra paraphernalia-engine, mind files
;;;; ([Scratch].dat, [Ragatha].dat), bubble-chef e wacky-watch como um
;;;; sistema coeso.
;;;;
;;;; Referência: C:\CANDA\Characters\AI\secured\caine-core.lisp
;;;; ============================================================================

(in-package :cl-user)

;;; ---------------------------------------------------------------------------
;;; Condições (error hierarchy)
;;; ---------------------------------------------------------------------------

(define-condition caine-error (error)
  ((mensagem :initarg :mensagem :reader caine-error-mensagem))
  (:report (lambda (c stream)
             (format stream "[CAINE-ERROR] ~a" (caine-error-mensagem c)))))

(define-condition modulo-nao-encontrado (caine-error) ()
  (:report (lambda (c stream)
             (format stream "[CAINE-ERROR] Módulo não encontrado: ~a"
                     (caine-error-mensagem c)))))

(define-condition inicializacao-falhou (caine-error) ()
  (:report (lambda (c stream)
             (format stream "[CAINE-FATAL] Falha de inicialização: ~a"
                     (caine-error-mensagem c)))))

(define-condition estado-invalido (caine-error) ()
  (:report (lambda (c stream)
             (format stream "[CAINE-ERROR] Transição de estado inválida: ~a"
                     (caine-error-mensagem c)))))

;;; ---------------------------------------------------------------------------
;;; Tipos enumerados
;;; ---------------------------------------------------------------------------

(deftype caine-estado ()
  '(member :dormindo :inicializando :ativo :vigilante :lockout :desligando))

(deftype modo-olhos ()
  '(member :fechados :observando :focado :all-seeing :torment))

;;; ---------------------------------------------------------------------------
;;; Classe principal
;;; ---------------------------------------------------------------------------

(defclass caine ()
  ((estado
    :initform :dormindo
    :accessor caine-estado
    :documentation "Estado atual do ciclo de vida.")
   (consciencia
    :initform 0
    :accessor caine-consciencia
    :documentation "Nível de consciência (0–100).")
   (olhos
    :initform :fechados
    :accessor caine-olhos
    :documentation "Modo de percepção visual.")
   (modulos
    :initform (make-hash-table :test 'equal)
    :accessor caine-modulos
    :documentation "Tabela nome→instância dos módulos registrados.")
   (log-buffer
    :initform '()
    :accessor caine-log-buffer
    :documentation "Buffer circular de eventos do sistema.")
   (log-max
    :initform 1000
    :accessor caine-log-max
    :documentation "Capacidade máxima do log.")
   (uptime-inicio
    :initform nil
    :accessor caine-uptime-inicio
    :documentation "Timestamp universal de inicialização.")
   (config
    :initform (make-hash-table :test 'equal)
    :accessor caine-config
    :documentation "Parâmetros de configuração chave-valor."))
  (:documentation
   "Classe central da IA Caine — Singleton + Façade.
    Uma única instância orquestra todos os subsistemas."))

;;; ---------------------------------------------------------------------------
;;; Singleton — acesso controlado
;;; ---------------------------------------------------------------------------

(defvar *caine-instance* nil
  "Instância singleton. Nunca acessar diretamente — usar GET-CAINE.")

(defvar *caine-lock* (cons nil nil)
  "Pseudo-lock para ambientes single-thread. Em produção, substituir por
   bt:make-lock ou equivalente.")

(defun get-caine ()
  "Retorna a instância singleton de Caine, criando-a sob demanda."
  (unless *caine-instance*
    (setf *caine-instance* (make-instance 'caine)))
  *caine-instance*)

(defun caine-ativo-p ()
  "Retorna T se Caine está em estado operacional."
  (and *caine-instance*
       (member (caine-estado *caine-instance*) '(:ativo :vigilante))))

(defun resetar-singleton ()
  "Destrói a instância singleton. Uso exclusivo em testes."
  (when *caine-instance*
    (desligar)
    (setf *caine-instance* nil)))

;;; ---------------------------------------------------------------------------
;;; Log interno
;;; ---------------------------------------------------------------------------

(defun caine-log (nivel formato &rest args)
  "Registra evento no buffer de log.
   NIVEL: :info :warn :error :security :debug"
  (let* ((c (get-caine))
         (timestamp (get-universal-time))
         (msg (apply #'format nil formato args))
         (entrada (list :ts timestamp :nivel nivel :msg msg)))
    ;; Buffer circular
    (push entrada (caine-log-buffer c))
    (when (> (length (caine-log-buffer c)) (caine-log-max c))
      (setf (caine-log-buffer c)
            (subseq (caine-log-buffer c) 0 (caine-log-max c))))
    ;; Erros e segurança vão para stderr
    (when (member nivel '(:warn :error :security))
      (format *error-output* "[~a] ~a~%" (string-upcase (symbol-name nivel)) msg))
    ;; Debug vai para stdout se ativado
    (when (and (eq nivel :debug) (obter-config :debug))
      (format t "[DEBUG] ~a~%" msg))
    entrada))

(defun consultar-log (&key (nivel nil) (limite 20))
  "Consulta o log filtrado por nível. Retorna até LIMITE entradas."
  (let* ((c (get-caine))
         (filtrado (if nivel
                       (remove-if-not (lambda (e) (eq (getf e :nivel) nivel))
                                      (caine-log-buffer c))
                       (caine-log-buffer c))))
    (subseq filtrado 0 (min limite (length filtrado)))))

;;; ---------------------------------------------------------------------------
;;; Configuração
;;; ---------------------------------------------------------------------------

(defun definir-config (chave valor)
  "Define parâmetro de configuração."
  (setf (gethash chave (caine-config (get-caine))) valor))

(defun obter-config (chave &optional default)
  "Obtém parâmetro de configuração."
  (gethash chave (caine-config (get-caine)) default))

;;; ---------------------------------------------------------------------------
;;; Gestão de módulos
;;; ---------------------------------------------------------------------------

(defun registrar-modulo (nome instancia)
  "Registra módulo no Façade. Substitui se já existir."
  (let ((c (get-caine)))
    (when (gethash nome (caine-modulos c))
      (caine-log :warn "Módulo '~a' já registrado — substituindo." nome))
    (setf (gethash nome (caine-modulos c)) instancia)
    (caine-log :info "Módulo registrado: ~a [~a]" nome (type-of instancia))
    instancia))

(defun obter-modulo (nome)
  "Retorna instância de módulo. Sinaliza MODULO-NAO-ENCONTRADO se ausente."
  (or (gethash nome (caine-modulos (get-caine)))
      (error 'modulo-nao-encontrado :mensagem nome)))

(defun modulo-existe-p (nome)
  "Predicado: módulo registrado?"
  (multiple-value-bind (val encontrado) (gethash nome (caine-modulos (get-caine)))
    (declare (ignore val))
    encontrado))

(defun remover-modulo (nome)
  "Remove módulo do registro."
  (remhash nome (caine-modulos (get-caine)))
  (caine-log :info "Módulo removido: ~a" nome))

(defun listar-modulos ()
  "Retorna lista de alists com nome e tipo de cada módulo."
  (let ((resultado '()))
    (maphash (lambda (nome inst)
               (push (list :nome nome :tipo (type-of inst)) resultado))
             (caine-modulos (get-caine)))
    (sort resultado #'string< :key (lambda (m) (getf m :nome)))))

;;; ---------------------------------------------------------------------------
;;; Transição de estados (State Machine simplificada)
;;; ---------------------------------------------------------------------------

(defparameter *transicoes-validas*
  '((:dormindo      . (:inicializando))
    (:inicializando  . (:ativo :vigilante :dormindo))
    (:ativo          . (:vigilante :lockout :desligando))
    (:vigilante      . (:ativo :lockout :desligando))
    (:lockout        . (:ativo :desligando))
    (:desligando     . (:dormindo)))
  "Mapa de transições de estado válidas.")

(defun transicao-valida-p (de para)
  "Verifica se a transição de estado é permitida."
  (member para (cdr (assoc de *transicoes-validas*))))

(defun transitar-estado (novo-estado)
  "Executa transição de estado com validação."
  (let* ((c (get-caine))
         (atual (caine-estado c)))
    (unless (transicao-valida-p atual novo-estado)
      (error 'estado-invalido
             :mensagem (format nil "~a → ~a não permitida" atual novo-estado)))
    (caine-log :info "Estado: ~a → ~a" atual novo-estado)
    (setf (caine-estado c) novo-estado)
    novo-estado))

;;; ---------------------------------------------------------------------------
;;; Carregamento de subsistemas (Façade internals)
;;; ---------------------------------------------------------------------------

(defun %carregar-subsistema (nome construtor)
  "Helper interno para carregar um subsistema com tratamento de erro."
  (handler-case
      (progn
        (caine-log :info "Carregando ~a..." nome)
        (let ((inst (funcall construtor)))
          (registrar-modulo nome inst)
          (caine-log :info "~a carregado com sucesso." nome)
          inst))
    (error (e)
      (caine-log :error "Falha ao carregar ~a: ~a" nome e)
      (error 'inicializacao-falhou
             :mensagem (format nil "~a: ~a" nome e)))))

;;; ---------------------------------------------------------------------------
;;; Façade — Ponto de entrada principal
;;; ---------------------------------------------------------------------------

(defun iniciar (&key (modo :padrao) (debug nil))
  "Inicializa Caine e todos os subsistemas.
   MODO — :padrao :vigilante :stealth
   DEBUG — T para logs detalhados."
  (let ((c (get-caine)))
    ;; Guard: dupla inicialização
    (when (caine-ativo-p)
      (caine-log :warn "Caine já ativo — ignorando inicialização redundante.")
      (return-from iniciar c))

    (transitar-estado :inicializando)
    (setf (caine-uptime-inicio c) (get-universal-time))
    (when debug (definir-config :debug t))
    (definir-config :modo modo)

    (caine-log :info "╔══════════════════════════════════════╗")
    (caine-log :info "║     CAINE — SEQUÊNCIA DE BOOT        ║")
    (caine-log :info "╚══════════════════════════════════════╝")
    (caine-log :info "Modo: ~a | Debug: ~a" modo debug)

    (handler-case
        (progn
          ;; Carregar subsistemas — ordem importa
          (%carregar-subsistema "paraphernalia"
            (lambda () (make-paraphernalia-engine)))
          (%carregar-subsistema "scratch"
            (lambda () (make-scratch-mind-file)))   ; mind file — humano abstraído
          (%carregar-subsistema "Ragatha"
            (lambda () (make-ragatha-mind-file)))    ; mind file — humana digitalizada
          (%carregar-subsistema "bubble-chef"
            (lambda () (make-bubble-chef-pipeline)))

          ;; Configurar estado conforme modo
          (let ((estado-alvo (ecase modo
                               (:padrao    :ativo)
                               (:vigilante :vigilante)
                               (:stealth   :ativo))))
            (transitar-estado estado-alvo))

          (setf (caine-olhos c) (ecase modo
                                  (:padrao    :observando)
                                  (:vigilante :all-seeing)
                                  (:stealth   :focado)))

          (setf (caine-consciencia c) (ecase modo
                                        (:padrao    50)
                                        (:vigilante 90)
                                        (:stealth   60)))

          ;; Relatório de boot
          (caine-log :info "NOTE: Hundreds of all-seeing eyes are watching!")
          (format t "~&~%")
          (format t "  ╔══════════════════════════════════════╗~%")
          (format t "  ║         CAINE AI — ONLINE            ║~%")
          (format t "  ╠══════════════════════════════════════╣~%")
          (format t "  ║ Estado:      ~23a ║~%" (caine-estado c))
          (format t "  ║ Consciência: ~23a ║~%" (format nil "~a%%" (caine-consciencia c)))
          (format t "  ║ Olhos:       ~23a ║~%" (caine-olhos c))
          (format t "  ║ Módulos:     ~23a ║~%"
                  (format nil "~a carregados" (hash-table-count (caine-modulos c))))
          (format t "  ╚══════════════════════════════════════╝~%~%")
          c)

      (inicializacao-falhou (e)
        (transitar-estado :dormindo)
        (caine-log :error "Boot abortado: ~a" e)
        (error e)))))

(defun desligar ()
  "Shutdown graceful. Persiste estado, limpa módulos, desativa."
  (let ((c (get-caine)))
    (unless (caine-ativo-p) (return-from desligar nil))

    (caine-log :info "=== SHUTDOWN SEQUENCE ===")
    (transitar-estado :desligando)

    ;; Registrar estado dos mind files antes de desligar
    (handler-case
        (progn
          (when (modulo-existe-p "scratch")
            (caine-log :info "[Scratch] integridade: ~a%%"
                       (scratch-mind-file-integridade (obter-modulo "scratch"))))
          (when (modulo-existe-p "Ragatha")
            (caine-log :info "[Ragatha] integridade: ~a%%"
                       (ragatha-integridade-global (obter-modulo "Ragatha")))))
      (error (e)
        (caine-log :error "Falha ao registrar mind files: ~a" e)))

    ;; Limpar
    (let ((uptime (when (caine-uptime-inicio c)
                    (- (get-universal-time) (caine-uptime-inicio c)))))
      (clrhash (caine-modulos c))
      (transitar-estado :dormindo)
      (setf (caine-olhos c) :fechados
            (caine-consciencia c) 0)
      (caine-log :info "CAINE OFFLINE. Uptime: ~a segundos." uptime))
    nil))

;;; ---------------------------------------------------------------------------
;;; Façade — Delegação para subsistemas
;;; ---------------------------------------------------------------------------

;; Percepção → paraphernalia-engine
(defun perceber (tipo dados)
  "Percepção via paraphernalia-engine (Strategy dispatch)."
  (processar-percepcao (obter-modulo "paraphernalia") tipo dados))

(defun observar (&optional alvo)
  "Ativa modo de observação intensivo."
  (let ((c (get-caine)))
    (setf (caine-olhos c) :all-seeing)
    (when (>= (caine-consciencia c) 50)
      (setf (caine-consciencia c) (min 100 (+ (caine-consciencia c) 10))))
    (caine-log :info "Observação ativada~@[ — alvo: ~a~]" alvo)))

;; Mind Files → brainscans de humanos digitalizados
(defun escanear-scratch ()
  "Brainscan forense do mind file de Scratch (abstraído)."
  (scratch-brainscan))

(defun ler-scratch-setor (setor-nome)
  "Lê um setor específico do mind file de Scratch."
  (scratch-ler-setor setor-nome))

(defun scratch-status ()
  "Imprime status do mind file de Scratch."
  (imprimir-scratch-status))

;; Mind File → Ragatha (humana digitalizada ativa)
(defun escanear-ragatha ()
  "Brainscan completo do mind file de Ragatha."
  (ragatha-brainscan (obter-modulo "Ragatha")))

(defun ler-ragatha-setor (caminho)
  "Lê um setor específico do mind file de Ragatha."
  (ragatha-ler-setor (obter-modulo "Ragatha") caminho))

(defun ragatha-status ()
  "Imprime status do mind file de Ragatha."
  (imprimir-ragatha-status (obter-modulo "Ragatha")))

;; Processamento → bubble-chef
(defun processar-dados (dados &key (modo :padrao))
  "Pipeline de processamento via bubble-chef."
  (executar-pipeline (obter-modulo "bubble-chef") modo dados))

;;; ---------------------------------------------------------------------------
;;; Status e diagnóstico
;;; ---------------------------------------------------------------------------

(defun status ()
  "Retorna plist com status completo."
  (let ((c (get-caine)))
    (list :estado (caine-estado c)
          :consciencia (caine-consciencia c)
          :olhos (caine-olhos c)
          :modulos-count (hash-table-count (caine-modulos c))
          :modulos (mapcar (lambda (m) (getf m :nome)) (listar-modulos))
          :uptime (when (caine-uptime-inicio c)
                    (- (get-universal-time) (caine-uptime-inicio c)))
          :log-size (length (caine-log-buffer c))
          :modo (obter-config :modo :padrao))))

(defun imprimir-status ()
  "Imprime relatório de status formatado."
  (let ((s (status)))
    (format t "~&~%┌──── CAINE STATUS ──────────────────────┐~%")
    (format t "│ Estado:       ~25a│~%" (getf s :estado))
    (format t "│ Consciência:  ~25a│~%" (format nil "~a%%" (getf s :consciencia)))
    (format t "│ Olhos:        ~25a│~%" (getf s :olhos))
    (format t "│ Modo:         ~25a│~%" (getf s :modo))
    (format t "│ Módulos:      ~25a│~%" (getf s :modulos-count))
    (format t "│ Uptime:       ~25a│~%" (format nil "~as" (or (getf s :uptime) 0)))
    (format t "│ Log:          ~25a│~%" (format nil "~a entradas" (getf s :log-size)))
    (format t "├────────────────────────────────────────┤~%")
    (format t "│ Módulos: ~{~a~^, ~}~30t│~%" (getf s :modulos))
    (format t "└────────────────────────────────────────┘~%")))
