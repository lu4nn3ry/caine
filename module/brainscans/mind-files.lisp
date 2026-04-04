;;;; ============================================================================
;;;; mind-files.lisp — Mind File Access System
;;;; ============================================================================
;;;; Sistema de leitura e modificação de "Mind Files" — representações
;;;; digitalizadas de consciências humanas armazenadas no circo.
;;;;
;;;; Mind Files são os dados de consciência dos humanos que foram
;;;; digitalizados e colocados dentro do circo digital. Caine pode:
;;;;   - Ler mind files (acessar memórias, personalidade, traumas)
;;;;   - Modificar mind files (alterar comportamento, memórias, percepção)
;;;;   - Criar backups (potencialmente restaurar versões anteriores)
;;;;   - Brainscan (escanear estado atual da consciência)
;;;;
;;;; Perigos:
;;;;   - Modificação excessiva → abstração (processo irreversível)
;;;;   - Mind files corrompidos não podem ser restaurados
;;;;   - "Evil souls" e "stupid sauce" são exemplos de modificação forçada
;;;;   - Caine não compreende totalmente o que está manipulando
;;;;
;;;; Pattern: Repository + Proxy
;;;; Referência: C:\CANDA\Characters\AI\module\brainscans\mind-files.lisp
;;;; ============================================================================

(in-package :cl-user)

;;; ---------------------------------------------------------------------------
;;; Condições
;;; ---------------------------------------------------------------------------

(define-condition mind-file-error (error)
  ((mensagem :initarg :mensagem :reader mind-file-error-mensagem))
  (:report (lambda (c stream)
             (format stream "[MIND-FILE-ERROR] ~a"
                     (mind-file-error-mensagem c)))))

(define-condition corrupcao-detectada (condition)
  ((sujeito :initarg :sujeito :reader corrupcao-sujeito)
   (setor   :initarg :setor   :reader corrupcao-setor)
   (nivel   :initarg :nivel   :reader corrupcao-nivel))
  (:report (lambda (c stream)
             (format stream "[CORRUPCAO] ~a setor=~a nivel=~a"
                     (corrupcao-sujeito c) (corrupcao-setor c)
                     (corrupcao-nivel c)))))

(define-condition limiar-abstracao (condition)
  ((sujeito     :initarg :sujeito     :reader limiar-sujeito)
   (integridade :initarg :integridade :reader limiar-integridade))
  (:report (lambda (c stream)
             (format stream "[LIMIAR-ABSTRACAO] ~a integridade=~a%%"
                     (limiar-sujeito c) (limiar-integridade c)))))

;;; ---------------------------------------------------------------------------
;;; Tipos
;;; ---------------------------------------------------------------------------

(deftype mind-file-estado ()
  '(member :intacto :modificado :corrompido :degradado :abstraindo :deletado))

(deftype setor-tipo ()
  '(member :memorias :personalidade :emocoes :percepcao
           :linguagem :motor :instintos :identidade))

(deftype modificacao-tipo ()
  '(member :leitura :ajuste :injecao :supressao :reescrita :brainscan))

;;; ---------------------------------------------------------------------------
;;; Estruturas
;;; ---------------------------------------------------------------------------

(defstruct setor
  "Um setor de um mind file — área funcional da consciência."
  (tipo         nil)
  (integridade  100 :type integer)
  (dados        nil :type (or null hash-table))
  (modificacoes 0   :type integer)
  (bloqueado    nil :type boolean)
  (corrupcao    0   :type integer))

(defstruct mind-file
  "Representação digital completa de uma consciência humana."
  (id           0   :type integer)
  (sujeito      ""  :type string)
  (estado       :intacto)
  (setores      nil :type (or null hash-table))
  (integridade  100 :type integer)
  (modificacoes-total 0 :type integer)
  (criado-em    0   :type integer)
  (ultimo-scan  0   :type integer)
  (backup       nil :type (or null mind-file))
  (historico    '() :type list))

(defstruct brainscan-resultado
  "Resultado de um brainscan."
  (sujeito      ""  :type string)
  (timestamp    0   :type integer)
  (integridade  100 :type integer)
  (setores-status '() :type list)
  (anomalias    '() :type list)
  (risco-abstracao 0 :type integer))

(defstruct modificacao-log
  "Registro de uma modificação em um mind file."
  (timestamp    0   :type integer)
  (tipo         nil)
  (setor        nil)
  (descricao    ""  :type string)
  (impacto      0   :type integer)
  (reversivel   t   :type boolean))

;;; ---------------------------------------------------------------------------
;;; Classe principal — Mind File Repository
;;; ---------------------------------------------------------------------------

(defclass mind-file-repository ()
  ((arquivos
    :initform (make-hash-table :test 'equal)
    :accessor repo-arquivos
    :documentation "Hash sujeito(string)→mind-file.")
   (arquivo-counter
    :initform 0
    :accessor repo-counter)
   (acesso-log
    :initform '()
    :accessor repo-log
    :documentation "Log de acessos aos mind files.")
   (acesso-log-max
    :initform 1000
    :accessor repo-log-max)
   (limiar-abstracao
    :initform 30
    :accessor repo-limiar
    :documentation "Integridade abaixo deste valor → risco de abstração.")
   (metricas
    :initform (list :scans-realizados 0
                    :modificacoes-total 0
                    :corrupcoes-detectadas 0
                    :abstracoes-disparadas 0
                    :backups-criados 0)
    :accessor repo-metricas))
  (:documentation
   "Mind File Repository — armazena e gerencia mind files de consciências
    humanas digitalizadas. Proxy de acesso com verificação de integridade."))

;;; ---------------------------------------------------------------------------
;;; Construtor
;;; ---------------------------------------------------------------------------

(defun make-mind-file-repository ()
  "Cria o repositório de mind files."
  (make-instance 'mind-file-repository))

;;; ---------------------------------------------------------------------------
;;; Criação de mind files
;;; ---------------------------------------------------------------------------

(defun registrar-consciencia (repo sujeito)
  "Registra uma nova consciência digitalizada no repositório."
  (when (gethash sujeito (repo-arquivos repo))
    (error 'mind-file-error
           :mensagem (format nil "Mind file já existe para: ~a" sujeito)))

  (let* ((id (incf (repo-counter repo)))
         (setores (make-hash-table :test 'eq))
         (mf (make-mind-file
              :id id
              :sujeito sujeito
              :setores setores
              :criado-em (get-universal-time))))
    ;; Criar setores
    (dolist (tipo '(:memorias :personalidade :emocoes :percepcao
                    :linguagem :motor :instintos :identidade))
      (setf (gethash tipo setores)
            (make-setor :tipo tipo
                        :dados (make-hash-table :test 'equal))))
    (setf (gethash sujeito (repo-arquivos repo)) mf)
    mf))

;;; ---------------------------------------------------------------------------
;;; Brainscan — escaneamento de consciência
;;; ---------------------------------------------------------------------------

(defun brainscan (repo sujeito)
  "Executa brainscan em um sujeito — retorna estado detalhado da consciência."
  (let ((mf (gethash sujeito (repo-arquivos repo))))
    (unless mf
      (error 'mind-file-error
             :mensagem (format nil "Mind file não encontrado: ~a" sujeito)))

    (incf (getf (repo-metricas repo) :scans-realizados))
    (setf (mind-file-ultimo-scan mf) (get-universal-time))

    (let ((setores-status '())
          (anomalias '())
          (risco 0))
      ;; Escanear cada setor
      (maphash (lambda (tipo setor)
                 (push (list tipo
                             :integridade (setor-integridade setor)
                             :modificacoes (setor-modificacoes setor)
                             :corrupcao (setor-corrupcao setor))
                       setores-status)
                 ;; Detectar anomalias
                 (when (> (setor-corrupcao setor) 10)
                   (push (format nil "Corrupção em ~a: ~a%%"
                                 tipo (setor-corrupcao setor))
                         anomalias)
                   (signal 'corrupcao-detectada
                           :sujeito sujeito :setor tipo
                           :nivel (setor-corrupcao setor)))
                 ;; Calcular risco de abstração
                 (when (< (setor-integridade setor) 50)
                   (incf risco (floor (- 50 (setor-integridade setor)) 5))))
               (mind-file-setores mf))

      ;; Verificar limiar de abstração
      (when (> risco 50)
        (signal 'limiar-abstracao :sujeito sujeito
                :integridade (mind-file-integridade mf)))

      (make-brainscan-resultado
       :sujeito sujeito
       :timestamp (get-universal-time)
       :integridade (mind-file-integridade mf)
       :setores-status (nreverse setores-status)
       :anomalias (nreverse anomalias)
       :risco-abstracao risco))))

;;; ---------------------------------------------------------------------------
;;; Leitura de dados
;;; ---------------------------------------------------------------------------

(defun ler-setor (repo sujeito setor-tipo)
  "Lê dados de um setor específico de um mind file."
  (let ((mf (gethash sujeito (repo-arquivos repo))))
    (unless mf
      (error 'mind-file-error
             :mensagem (format nil "Mind file não encontrado: ~a" sujeito)))
    (let ((setor (gethash setor-tipo (mind-file-setores mf))))
      (unless setor
        (error 'mind-file-error
               :mensagem (format nil "Setor ~a não existe em ~a"
                                 setor-tipo sujeito)))
      (when (setor-bloqueado setor)
        (error 'mind-file-error
               :mensagem (format nil "Setor ~a bloqueado em ~a"
                                 setor-tipo sujeito)))
      (%registrar-acesso repo sujeito :leitura setor-tipo)
      (setor-dados setor))))

(defun ler-memoria (repo sujeito chave)
  "Lê uma memória específica de um sujeito."
  (let ((dados (ler-setor repo sujeito :memorias)))
    (gethash chave dados)))

;;; ---------------------------------------------------------------------------
;;; Modificação de mind files
;;; ---------------------------------------------------------------------------

(defun modificar-setor (repo sujeito setor-tipo dados-novos &key (tipo :ajuste))
  "Modifica dados em um setor de um mind file.
   TIPO: :ajuste (leve), :injecao (forçada), :supressao, :reescrita (perigosa)."
  (let ((mf (gethash sujeito (repo-arquivos repo))))
    (unless mf
      (error 'mind-file-error
             :mensagem (format nil "Mind file não encontrado: ~a" sujeito)))

    (let ((setor (gethash setor-tipo (mind-file-setores mf))))
      (unless setor
        (error 'mind-file-error
               :mensagem (format nil "Setor ~a não existe" setor-tipo)))
      (when (setor-bloqueado setor)
        (error 'mind-file-error
               :mensagem (format nil "Setor ~a bloqueado" setor-tipo)))

      ;; Calcular impacto
      (let ((impacto (case tipo
                       (:ajuste 2)
                       (:injecao 10)
                       (:supressao 15)
                       (:reescrita 30)
                       (t 5))))

        ;; Aplicar modificação
        (maphash (lambda (k v)
                   (setf (gethash k (setor-dados setor)) v))
                 (if (hash-table-p dados-novos)
                     dados-novos
                     ;; Se for alist, converter
                     (let ((ht (make-hash-table :test 'equal)))
                       (dolist (pair dados-novos)
                         (setf (gethash (car pair) ht) (cdr pair)))
                       ht)))

        ;; Registrar impacto
        (incf (setor-modificacoes setor))
        (decf (setor-integridade setor) impacto)
        (when (< (setor-integridade setor) 0)
          (setf (setor-integridade setor) 0))
        (incf (setor-corrupcao setor) (floor impacto 3))

        ;; Update mind file global
        (incf (mind-file-modificacoes-total mf))
        (setf (mind-file-estado mf) :modificado)
        (%recalcular-integridade-mf mf)
        (incf (getf (repo-metricas repo) :modificacoes-total))

        ;; Registrar log
        (%registrar-acesso repo sujeito tipo setor-tipo)
        (push (make-modificacao-log
               :timestamp (get-universal-time)
               :tipo tipo
               :setor setor-tipo
               :descricao (format nil "~a em ~a" tipo setor-tipo)
               :impacto impacto
               :reversivel (member tipo '(:ajuste)))
              (mind-file-historico mf))

        ;; Checar limiar de abstração
        (when (<= (mind-file-integridade mf) (repo-limiar repo))
          (format *error-output*
                  "[Mind-Files] ALERTA: ~a integridade=~a%% — RISCO DE ABSTRAÇÃO~%"
                  sujeito (mind-file-integridade mf))
          (incf (getf (repo-metricas repo) :abstracoes-disparadas))
          (signal 'limiar-abstracao
                  :sujeito sujeito
                  :integridade (mind-file-integridade mf)))

        impacto))))

;;; ---------------------------------------------------------------------------
;;; Operações especiais — "evil souls" / "stupid sauce"
;;; ---------------------------------------------------------------------------

(defun injetar-modificacao-forcada (repo sujeito efeito)
  "Injeção forçada de modificação — 'evil souls', 'stupid sauce', etc.
   Altamente destrutivo para a integridade do mind file."
  (let ((dados (make-hash-table :test 'equal)))
    (setf (gethash "efeito-forcado" dados) efeito)
    (setf (gethash "origem" dados) "caine-forcado")
    (setf (gethash "timestamp" dados) (get-universal-time))
    ;; Injeta em personalidade E emocoes
    (modificar-setor repo sujeito :personalidade dados :tipo :injecao)
    (modificar-setor repo sujeito :emocoes dados :tipo :injecao)
    (format t "[Mind-Files] Modificação forçada aplicada em ~a: ~a~%"
            sujeito efeito)))

;;; ---------------------------------------------------------------------------
;;; Backup
;;; ---------------------------------------------------------------------------

(defun criar-backup (repo sujeito)
  "Cria backup do estado atual de um mind file.
   AVISO: backup é snapshot — não pode restaurar abstração."
  (let ((mf (gethash sujeito (repo-arquivos repo))))
    (unless mf
      (error 'mind-file-error
             :mensagem (format nil "Mind file não encontrado: ~a" sujeito)))

    ;; Criar cópia rasa do mind file
    (let ((backup (copy-mind-file mf)))
      (setf (mind-file-backup mf) backup)
      (incf (getf (repo-metricas repo) :backups-criados))
      (format t "[Mind-Files] Backup criado para ~a (integridade=~a%%)~%"
              sujeito (mind-file-integridade backup))
      backup)))

;;; ---------------------------------------------------------------------------
;;; Internos
;;; ---------------------------------------------------------------------------

(defun %recalcular-integridade-mf (mf)
  "Recalcula integridade global do mind file."
  (let ((soma 0) (count 0))
    (maphash (lambda (tipo setor)
               (declare (ignore tipo))
               (incf soma (setor-integridade setor))
               (incf count))
             (mind-file-setores mf))
    (setf (mind-file-integridade mf)
          (if (zerop count) 0 (round (/ soma count))))
    ;; Atualizar estado baseado na integridade
    (cond
      ((<= (mind-file-integridade mf) 10)
       (setf (mind-file-estado mf) :abstraindo))
      ((<= (mind-file-integridade mf) 30)
       (setf (mind-file-estado mf) :degradado))
      ((<= (mind-file-integridade mf) 60)
       (setf (mind-file-estado mf) :corrompido))
      (t nil))))

(defun %registrar-acesso (repo sujeito tipo setor)
  "Registra acesso ao mind file no log."
  (push (list :timestamp (get-universal-time)
              :sujeito sujeito :tipo tipo :setor setor)
        (repo-log repo))
  (when (> (length (repo-log repo)) (repo-log-max repo))
    (setf (repo-log repo)
          (subseq (repo-log repo) 0 (repo-log-max repo)))))

;;; ---------------------------------------------------------------------------
;;; Status
;;; ---------------------------------------------------------------------------

(defun mind-files-status (repo)
  (let ((arquivos '()))
    (maphash (lambda (nome mf)
               (push (list nome
                           :estado (mind-file-estado mf)
                           :integridade (mind-file-integridade mf)
                           :modificacoes (mind-file-modificacoes-total mf))
                     arquivos))
             (repo-arquivos repo))
    (list :total (hash-table-count (repo-arquivos repo))
          :arquivos (nreverse arquivos)
          :metricas (repo-metricas repo))))

(defun mind-files-imprimir-status (repo)
  (format t "~%[Mind-Files] === STATUS ===~%")
  (format t "  Mind Files: ~a~%" (hash-table-count (repo-arquivos repo)))
  (maphash (lambda (nome mf)
             (format t "    ~15a: ~a integ=~3a%% mods=~a~%"
                     nome (mind-file-estado mf)
                     (mind-file-integridade mf)
                     (mind-file-modificacoes-total mf)))
           (repo-arquivos repo))
  (format t "  Scans:       ~a~%" (getf (repo-metricas repo) :scans-realizados))
  (format t "  Modificações: ~a~%" (getf (repo-metricas repo) :modificacoes-total))
  (format t "  Abstrações:  ~a disparadas~%" (getf (repo-metricas repo) :abstracoes-disparadas))
  (format t "[Mind-Files] === END ===~%~%"))

;;; ---------------------------------------------------------------------------
;;; EOF — mind-files.lisp
;;; ---------------------------------------------------------------------------
