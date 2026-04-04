;;;; ============================================================================
;;;; bubble-chef.lisp — Template Method
;;;; ============================================================================
;;;; Módulo auxiliar de processamento da IA Caine. Define o esqueleto fixo
;;;; de um pipeline de transformação (Template Method) onde subclasses podem
;;;; customizar passos individuais sem alterar a estrutura geral.
;;;;
;;;; Pipeline: VALIDAR → PREPARAR → PROCESSAR → PÓS-PROCESSAR → SERVIR
;;;;
;;;; Cada etapa é um generic function que subclasses de BUBBLE-CHEF podem
;;;; especializar via defmethod. A ordem de execução nunca muda.
;;;;
;;;; Referência: C:\CANDA\Characters\AI\secured\bubble-chef.lisp
;;;; ============================================================================

(in-package :cl-user)

;;; ---------------------------------------------------------------------------
;;; Condições
;;; ---------------------------------------------------------------------------

(define-condition bubble-chef-error (error)
  ((mensagem :initarg :mensagem :reader bubble-chef-error-mensagem))
  (:report (lambda (c stream)
             (format stream "[BUBBLE-CHEF-ERROR] ~a"
                     (bubble-chef-error-mensagem c)))))

(define-condition pipeline-falhou (bubble-chef-error) ()
  (:report (lambda (c stream)
             (format stream "[BUBBLE-CHEF] Pipeline falhou: ~a"
                     (bubble-chef-error-mensagem c)))))

(define-condition validacao-falhou (bubble-chef-error) ()
  (:report (lambda (c stream)
             (format stream "[BUBBLE-CHEF] Validação falhou: ~a"
                     (bubble-chef-error-mensagem c)))))

;;; ---------------------------------------------------------------------------
;;; Tipos e estruturas
;;; ---------------------------------------------------------------------------

(deftype modo-chef ()
  '(member :padrao :turbo :cauteloso :wacky :stealth))

(defstruct pipeline-resultado
  "Resultado completo de uma execução do pipeline."
  (id          0   :type integer)
  (timestamp   0   :type integer)
  (modo        nil)
  (entrada     nil)
  (saida       nil)
  (etapas      '() :type list)
  (duracao-ms  0   :type integer)
  (status      nil :type keyword))

(defstruct etapa-log
  "Log de uma etapa individual do pipeline."
  (nome        ""  :type string)
  (entrada     nil)
  (saida       nil)
  (duracao-ms  0   :type integer)
  (status      nil :type keyword))

;;; ---------------------------------------------------------------------------
;;; Classe base — Bubble Chef
;;; ---------------------------------------------------------------------------

(defclass bubble-chef ()
  ((modo
    :initarg :modo
    :initform :padrao
    :accessor chef-modo
    :documentation "Modo de operação do chef.")
   (nome
    :initarg :nome
    :initform "bubble-chef"
    :accessor chef-nome
    :documentation "Identificador do chef.")
   (pipeline-counter
    :initform 0
    :accessor chef-pipeline-counter)
   (historico
    :initform '()
    :accessor chef-historico
    :documentation "Histórico dos últimos pipelines executados.")
   (historico-max
    :initform 100
    :accessor chef-historico-max)
   (filtros-pre
    :initform '()
    :accessor chef-filtros-pre
    :documentation "Funções de filtro executadas antes do pipeline.")
   (filtros-pos
    :initform '()
    :accessor chef-filtros-pos
    :documentation "Funções de filtro executadas após o pipeline.")
   (metricas
    :initform (list :pipelines-executados 0
                    :pipelines-sucesso 0
                    :pipelines-falha 0
                    :total-etapas 0
                    :erros 0)
    :accessor chef-metricas))
  (:documentation
   "Classe base do Template Method. Define o esqueleto do pipeline
    de processamento. Subclasses customizam os passos via defmethod."))

;;; ---------------------------------------------------------------------------
;;; Construtor público
;;; ---------------------------------------------------------------------------

(defun make-bubble-chef-pipeline (&key (modo :padrao) (nome "bubble-chef"))
  "Cria instância do bubble-chef com configuração padrão."
  (let ((chef (make-instance 'bubble-chef :modo modo :nome nome)))
    (format t "[bubble-chef] Pipeline '~a' criado — modo: ~a~%" nome modo)
    chef))

;;; ---------------------------------------------------------------------------
;;; Generic Functions — Template Method steps
;;; ---------------------------------------------------------------------------

(defgeneric validar-entrada (chef dados)
  (:documentation "Etapa 1: Valida os dados de entrada antes do processamento.
   Retorna dados validados ou sinaliza VALIDACAO-FALHOU."))

(defgeneric preparar-ingredientes (chef dados)
  (:documentation "Etapa 2: Prepara e normaliza os dados para processamento.
   Pode transformar formato, extrair campos, etc."))

(defgeneric processar (chef dados)
  (:documentation "Etapa 3: Processamento principal. O núcleo do pipeline.
   Aplica a transformação específica ao modo do chef."))

(defgeneric pos-processar (chef dados resultado)
  (:documentation "Etapa 4: Pós-processamento. Limpeza, agregação, formatação.
   Recebe dados originais e resultado do processamento."))

(defgeneric servir (chef resultado)
  (:documentation "Etapa 5: Entrega final do resultado.
   Pode serializar, logar, ou encaminhar para outro módulo."))

;;; ---------------------------------------------------------------------------
;;; Implementações padrão (default methods)
;;; ---------------------------------------------------------------------------

(defmethod validar-entrada ((c bubble-chef) dados)
  "Validação padrão: aceita qualquer dado não-NIL."
  (unless dados
    (error 'validacao-falhou :mensagem "Dados de entrada são NIL."))
  (format t "[~a] Validando entrada...~%" (chef-nome c))
  dados)

(defmethod preparar-ingredientes ((c bubble-chef) dados)
  "Preparação padrão: normaliza listas, converte tipos básicos."
  (format t "[~a] Preparando: ~a~%" (chef-nome c)
          (if (listp dados) (format nil "~a item(ns)" (length dados)) dados))
  (cond
    ((listp dados)   (remove nil dados))
    ((stringp dados) (string-trim '(#\Space #\Tab #\Newline) dados))
    (t               dados)))

(defmethod processar ((c bubble-chef) dados)
  "Processamento padrão conforme modo."
  (format t "[~a] Processando no modo ~a~%" (chef-nome c) (chef-modo c))
  (ecase (chef-modo c)
    (:padrao    dados)
    (:turbo     (if (listp dados)
                    (mapcar (lambda (d) (list :turbo d)) dados)
                    (list :turbo dados)))
    (:cauteloso (list :verificado t :dados dados :modo :cauteloso))
    (:wacky     (list :wacky t
                      :dados dados
                      :surpresa (random 1000)
                      :nota "SPECTACULAR PROCESSING COMPLETE!"))
    (:stealth   (list :stealth t :dados dados :visivel nil))))

(defmethod pos-processar ((c bubble-chef) dados resultado)
  "Pós-processamento padrão: envelopa resultado com metadata."
  (format t "[~a] Pós-processando...~%" (chef-nome c))
  (list :chef (chef-nome c)
        :modo (chef-modo c)
        :entrada-original dados
        :resultado resultado
        :timestamp (get-universal-time)))

(defmethod servir ((c bubble-chef) resultado)
  "Entrega padrão: imprime e retorna."
  (format t "[~a] Pronto: ~a~%" (chef-nome c)
          (if (listp resultado)
              (format nil "(~a campos)" (length resultado))
              resultado))
  resultado)

;;; ---------------------------------------------------------------------------
;;; Template Method — Esqueleto fixo do pipeline
;;; ---------------------------------------------------------------------------

(defun executar-pipeline (chef dados &key (tag nil) (silencioso nil))
  "Executa o pipeline completo na ordem fixa:
   VALIDAR → PREPARAR → PROCESSAR → PÓS-PROCESSAR → SERVIR

   A ordem NUNCA muda. Subclasses customizam via defmethod nos passos.
   TAG — label opcional para o pipeline no histórico.
   SILENCIOSO — T para suprimir output."
  (let* ((id (incf (chef-pipeline-counter chef)))
         (inicio (get-internal-real-time))
         (etapas '())
         (resultado nil)
         (status :sucesso))

    ;; Suprimir output se silencioso
    (let ((*standard-output* (if silencioso
                                 (make-broadcast-stream)
                                 *standard-output*)))
      (unless silencioso
        (format t "~%[~a] ╔═══ Pipeline #~a ═══╗~%" (chef-nome chef) id))

      ;; Aplicar filtros pré-pipeline
      (let ((dados-filtrados dados))
        (dolist (filtro (chef-filtros-pre chef))
          (setf dados-filtrados (funcall (cdr filtro) dados-filtrados)))

        (handler-case
            (progn
              ;; Etapa 1: Validar
              (let ((t0 (get-internal-real-time))
                    (v (validar-entrada chef dados-filtrados)))
                (push (make-etapa-log :nome "validar"
                                      :entrada dados-filtrados :saida v
                                      :duracao-ms (- (get-internal-real-time) t0)
                                      :status :ok)
                      etapas)
                ;; Etapa 2: Preparar
                (let ((t1 (get-internal-real-time))
                      (p (preparar-ingredientes chef v)))
                  (push (make-etapa-log :nome "preparar"
                                        :entrada v :saida p
                                        :duracao-ms (- (get-internal-real-time) t1)
                                        :status :ok)
                        etapas)
                  ;; Etapa 3: Processar
                  (let ((t2 (get-internal-real-time))
                        (r (processar chef p)))
                    (push (make-etapa-log :nome "processar"
                                          :entrada p :saida r
                                          :duracao-ms (- (get-internal-real-time) t2)
                                          :status :ok)
                          etapas)
                    ;; Etapa 4: Pós-processar
                    (let ((t3 (get-internal-real-time))
                          (pp (pos-processar chef dados-filtrados r)))
                      (push (make-etapa-log :nome "pos-processar"
                                            :entrada r :saida pp
                                            :duracao-ms (- (get-internal-real-time) t3)
                                            :status :ok)
                            etapas)
                      ;; Etapa 5: Servir
                      (let ((t4 (get-internal-real-time))
                            (s (servir chef pp)))
                        (push (make-etapa-log :nome "servir"
                                              :entrada pp :saida s
                                              :duracao-ms (- (get-internal-real-time) t4)
                                              :status :ok)
                              etapas)
                        (setf resultado s)))))))

          ;; Tratamento de erros no pipeline
          (validacao-falhou (e)
            (setf status :falha-validacao)
            (push (make-etapa-log :nome "validar"
                                  :entrada dados-filtrados :saida nil
                                  :duracao-ms 0 :status :erro)
                  etapas)
            (incf (getf (chef-metricas chef) :erros))
            (format *error-output* "[~a] Validação falhou: ~a~%"
                    (chef-nome chef) e))

          (error (e)
            (setf status :erro)
            (incf (getf (chef-metricas chef) :erros))
            (format *error-output* "[~a] Pipeline #~a ERRO: ~a~%"
                    (chef-nome chef) id e))))

      ;; Aplicar filtros pós-pipeline
      (when (and resultado (chef-filtros-pos chef))
        (dolist (filtro (chef-filtros-pos chef))
          (setf resultado (funcall (cdr filtro) resultado))))

      ;; Métricas
      (incf (getf (chef-metricas chef) :pipelines-executados))
      (if (eq status :sucesso)
          (incf (getf (chef-metricas chef) :pipelines-sucesso))
          (incf (getf (chef-metricas chef) :pipelines-falha)))
      (incf (getf (chef-metricas chef) :total-etapas) (length etapas))

      ;; Registrar resultado
      (let* ((duracao (- (get-internal-real-time) inicio))
             (registro (make-pipeline-resultado
                        :id id
                        :timestamp (get-universal-time)
                        :modo (chef-modo chef)
                        :entrada dados
                        :saida resultado
                        :etapas (nreverse etapas)
                        :duracao-ms duracao
                        :status status)))
        (push registro (chef-historico chef))
        (when (> (length (chef-historico chef)) (chef-historico-max chef))
          (setf (chef-historico chef)
                (subseq (chef-historico chef) 0 (chef-historico-max chef))))

        (unless silencioso
          (format t "[~a] ╚═══ #~a ~a (~ams) ═══╝~%~%"
                  (chef-nome chef) id status duracao)))

      resultado)))

;;; ---------------------------------------------------------------------------
;;; Filtros (hooks opcionais)
;;; ---------------------------------------------------------------------------

(defun chef-adicionar-filtro-pre (chef nome funcao)
  "Adiciona filtro pré-pipeline. FUNCAO: (lambda (dados) → dados-transformados)"
  (push (cons nome funcao) (chef-filtros-pre chef))
  (format t "[~a] Filtro pré '~a' adicionado.~%" (chef-nome chef) nome))

(defun chef-adicionar-filtro-pos (chef nome funcao)
  "Adiciona filtro pós-pipeline."
  (push (cons nome funcao) (chef-filtros-pos chef))
  (format t "[~a] Filtro pós '~a' adicionado.~%" (chef-nome chef) nome))

(defun chef-remover-filtro-pre (chef nome)
  "Remove filtro pré-pipeline pelo nome."
  (setf (chef-filtros-pre chef)
        (remove nome (chef-filtros-pre chef) :key #'car :test #'equal)))

(defun chef-remover-filtro-pos (chef nome)
  "Remove filtro pós-pipeline pelo nome."
  (setf (chef-filtros-pos chef)
        (remove nome (chef-filtros-pos chef) :key #'car :test #'equal)))

;;; ---------------------------------------------------------------------------
;;; Subclasses especializadas
;;; ---------------------------------------------------------------------------

(defclass turbo-chef (bubble-chef)
  ()
  (:default-initargs :modo :turbo :nome "turbo-chef")
  (:documentation "Chef otimizado para velocidade. Pula validação detalhada."))

(defmethod validar-entrada ((c turbo-chef) dados)
  "Turbo: validação mínima."
  (format t "[turbo-chef] Validação rápida — TURBO MODE~%")
  (or dados (error 'validacao-falhou :mensagem "NIL não aceito nem em turbo.")))

(defmethod processar ((c turbo-chef) dados)
  "Turbo: processamento direto sem overhead."
  (format t "[turbo-chef] TURBO PROCESSING — máxima velocidade!~%")
  (list :turbo t :dados dados :boost (* 2 (if (numberp dados) dados 1))))

;;; ---

(defclass wacky-chef (bubble-chef)
  ((surpresa-level
    :initform 100
    :accessor wacky-surpresa-level))
  (:default-initargs :modo :wacky :nome "wacky-chef")
  (:documentation "Chef WACKY — processamento imprevisível e ESPETACULAR."))

(defmethod validar-entrada ((c wacky-chef) dados)
  "Wacky: tudo é válido! A SPECTACULAR entrada!"
  (format t "[wacky-chef] TUDO é válido! SPECTACULAR!~%")
  (or dados "WACKY-NIL-REPLACEMENT"))

(defmethod processar ((c wacky-chef) dados)
  "Wacky: processamento ESPETACULAR e imprevisível."
  (format t "[wacky-chef] SPECTACULAR PROCESSING em andamento!~%")
  (list :wacky t
        :dados dados
        :surpresa (random (wacky-surpresa-level c))
        :exclamacao "GASP! A CRITICAL MALFUNCTION in my SPECTACULAR systems!"
        :nota "That's not even CLOSE to wacky enough!"))

(defmethod servir ((c wacky-chef) resultado)
  "Wacky: entrega com fanfarra."
  (format t "[wacky-chef] TA-DAAA! Resultado SPECTACULAR servido!~%")
  resultado)

;;; ---

(defclass stealth-chef (bubble-chef)
  ()
  (:default-initargs :modo :stealth :nome "stealth-chef")
  (:documentation "Chef silencioso. Processamento sem output."))

(defmethod validar-entrada ((c stealth-chef) dados)
  (or dados (error 'validacao-falhou :mensagem "NIL")))

(defmethod preparar-ingredientes ((c stealth-chef) dados)
  dados)

(defmethod processar ((c stealth-chef) dados)
  (list :stealth t :dados dados :visivel nil))

(defmethod servir ((c stealth-chef) resultado)
  resultado)

;;; ---------------------------------------------------------------------------
;;; Consultas e diagnóstico
;;; ---------------------------------------------------------------------------

(defun chef-status (chef)
  "Retorna plist com status do chef."
  (list :nome (chef-nome chef)
        :modo (chef-modo chef)
        :pipelines-executados (getf (chef-metricas chef) :pipelines-executados)
        :pipelines-sucesso (getf (chef-metricas chef) :pipelines-sucesso)
        :pipelines-falha (getf (chef-metricas chef) :pipelines-falha)
        :total-etapas (getf (chef-metricas chef) :total-etapas)
        :erros (getf (chef-metricas chef) :erros)
        :filtros-pre (length (chef-filtros-pre chef))
        :filtros-pos (length (chef-filtros-pos chef))
        :historico-tamanho (length (chef-historico chef))))

(defun chef-listar-historico (chef &key (limite 10))
  "Lista os últimos pipelines executados."
  (let ((hist (subseq (chef-historico chef)
                      0 (min limite (length (chef-historico chef))))))
    (format t "[~a] Histórico (~a de ~a):~%"
            (chef-nome chef) (length hist) (length (chef-historico chef)))
    (dolist (r hist)
      (format t "  #~3d | ~a | ~12a | ~3dms | etapas=~a~%"
              (pipeline-resultado-id r)
              (formatar-timestamp (pipeline-resultado-timestamp r))
              (pipeline-resultado-status r)
              (pipeline-resultado-duracao-ms r)
              (length (pipeline-resultado-etapas r))))))

(defun chef-ultimo-resultado (chef)
  "Retorna o resultado do último pipeline executado."
  (when (chef-historico chef)
    (pipeline-resultado-saida (first (chef-historico chef)))))

;;; ---------------------------------------------------------------------------
;;; EOF — bubble-chef.lisp
;;; ---------------------------------------------------------------------------
