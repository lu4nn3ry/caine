;;;; ============================================================================
;;;; npc-system.lisp — NPC / Mannequin System
;;;; ============================================================================
;;;; Sistema de criação e controle de NPCs por Caine. NPCs são entidades
;;;; transparentes — simulações óbvias sem livre-arbítrio, controladas
;;;; diretamente por Caine. Incluem os famosos Mannequins.
;;;;
;;;; Tipos de NPC:
;;;;   - Mannequin: Bonecos genéricos, plateia simbólica. Não falam, apenas
;;;;     movem-se em grupo. Usados durante a música de Caine no episódio 8.
;;;;   - NPC narrativo: Personagens de aventura com scripts pré-definidos.
;;;;   - Mob: Entidades hostis em aventuras (monstros, obstáculos).
;;;;   - Prop: Objetos interativos com lógica simples.
;;;;
;;;; Limitações cruciais:
;;;;   - NPCs são TRANSPARENTEMENTE falsos — ninguém é enganado
;;;;   - Sem personalidade real, sem crescimento, sem livre-arbítrio
;;;;   - Quando Caine morre, NPCs congelam (sem IA para controlar)
;;;;   - O contraste com humanos reais é o que torna Caine patético
;;;;
;;;; Pattern: Abstract Factory + Flyweight
;;;; Referência: C:\CANDA\Characters\AI\agent\experimental\npc-system.lisp
;;;; ============================================================================

(in-package :cl-user)

;;; ---------------------------------------------------------------------------
;;; Condições
;;; ---------------------------------------------------------------------------

(define-condition npc-error (error)
  ((mensagem :initarg :mensagem :reader npc-error-mensagem))
  (:report (lambda (c stream)
             (format stream "[NPC-ERROR] ~a" (npc-error-mensagem c)))))

(define-condition npc-congelado (condition)
  ((npc-id :initarg :npc-id :reader congelado-npc-id))
  (:report (lambda (c stream)
             (format stream "[NPC-FREEZE] NPC ~a congelado — sem controlador"
                     (congelado-npc-id c)))))

;;; ---------------------------------------------------------------------------
;;; Tipos
;;; ---------------------------------------------------------------------------

(deftype npc-tipo ()
  '(member :mannequin :narrativo :mob :prop))

(deftype npc-estado ()
  '(member :inativo :ativo :scripted :combate :congelado :destruido))

(deftype mannequin-formacao ()
  '(member :plateia :circulo :fila :dispersa :coreografia))

;;; ---------------------------------------------------------------------------
;;; Estruturas
;;; ---------------------------------------------------------------------------

(defstruct npc-template
  "Template flyweight — compartilhado entre NPCs do mesmo tipo."
  (tipo       nil)
  (aparencia  ""  :type string)
  (hp-base    100 :type integer)
  (velocidade 1.0 :type float)
  (tags       '() :type list))

(defstruct npc
  "Instância de um NPC ativo no circo."
  (id          0   :type integer)
  (nome        ""  :type string)
  (tipo        nil)
  (estado      :inativo)
  (template    nil :type (or null npc-template))
  (posicao     '(0 0 0) :type list)
  (hp          100 :type integer)
  (script      '() :type list)
  (script-idx  0   :type integer)
  (controlador nil :type (or null keyword))
  (criado-em   0   :type integer)
  (propriedades (make-hash-table :test 'equal)))

(defstruct mannequin-grupo
  "Grupo de mannequins em formação."
  (id          0   :type integer)
  (formacao    :plateia)
  (membros     '() :type list)
  (posicao-centro '(0 0 0) :type list)
  (animacao    nil)
  (sincronizados t :type boolean))

;;; ---------------------------------------------------------------------------
;;; Templates flyweight
;;; ---------------------------------------------------------------------------

(defparameter *npc-templates* (make-hash-table :test 'eq))

(defun %registrar-templates ()
  "Registra templates padrão de NPCs."
  (dolist (spec '((:mannequin "Boneco articulado sem face" 1 0.5
                   (:silencioso :grupo :descartavel))
                  (:narrativo "Personagem de aventura scriptado" 50 1.0
                   (:fala :script :interativo))
                  (:mob "Entidade hostil de aventura" 30 1.5
                   (:hostil :combate :descartavel))
                  (:prop "Objeto interativo com lógica" 999 0.0
                   (:estatico :interativo))))
    (setf (gethash (first spec) *npc-templates*)
          (make-npc-template
           :tipo (first spec)
           :aparencia (second spec)
           :hp-base (third spec)
           :velocidade (fourth spec)
           :tags (fifth spec)))))

(%registrar-templates)

;;; ---------------------------------------------------------------------------
;;; Classe principal — NPC System
;;; ---------------------------------------------------------------------------

(defclass npc-system ()
  ((npcs-ativos
    :initform (make-hash-table :test 'eql)
    :accessor sys-npcs
    :documentation "Hash id→npc de todas as instâncias ativas.")
   (npc-counter
    :initform 0
    :accessor sys-npc-counter)
   (grupos-mannequin
    :initform '()
    :accessor sys-grupos
    :documentation "Grupos de mannequins coordenados.")
   (grupo-counter
    :initform 0
    :accessor sys-grupo-counter)
   (max-npcs
    :initform 500
    :accessor sys-max-npcs
    :documentation "Limite de NPCs simultâneos.")
   (caine-ativo
    :initform t
    :accessor sys-caine-ativo
    :documentation "Se Caine está ativo. Sem Caine → todos congelam.")
   (metricas
    :initform (list :npcs-criados 0
                    :npcs-destruidos 0
                    :mannequins-criados 0
                    :grupos-formados 0
                    :congelamentos 0)
    :accessor sys-metricas))
  (:documentation
   "NPC System — fábrica e controlador de NPCs e Mannequins.
    Todos os NPCs são transparentemente falsos — simulações óbvias de Caine."))

;;; ---------------------------------------------------------------------------
;;; Construtor
;;; ---------------------------------------------------------------------------

(defun make-npc-system ()
  "Cria o sistema de NPCs."
  (make-instance 'npc-system))

;;; ---------------------------------------------------------------------------
;;; Factory — criação de NPCs
;;; ---------------------------------------------------------------------------

(defun criar-npc (sys tipo &key (nome "") (posicao '(0 0 0)) script)
  "Cria um NPC do tipo especificado. Retorna o NPC criado."
  (unless (sys-caine-ativo sys)
    (error 'npc-error :mensagem "Caine inativo — não é possível criar NPCs"))

  (let ((total (hash-table-count (sys-npcs sys))))
    (when (>= total (sys-max-npcs sys))
      (error 'npc-error
             :mensagem (format nil "Limite de NPCs atingido (~a)" (sys-max-npcs sys)))))

  (let* ((template (gethash tipo *npc-templates*))
         (id (incf (sys-npc-counter sys)))
         (npc (make-npc
               :id id
               :nome (if (string= nome "")
                         (format nil "~a-~a" tipo id)
                         nome)
               :tipo tipo
               :estado :ativo
               :template template
               :posicao posicao
               :hp (if template (npc-template-hp-base template) 100)
               :script (or script '())
               :controlador :caine
               :criado-em (get-universal-time))))
    (setf (gethash id (sys-npcs sys)) npc)
    (incf (getf (sys-metricas sys) :npcs-criados))
    (when (eq tipo :mannequin)
      (incf (getf (sys-metricas sys) :mannequins-criados)))
    npc))

(defun destruir-npc (sys id)
  "Destrói um NPC por ID."
  (let ((npc (gethash id (sys-npcs sys))))
    (when npc
      (setf (npc-estado npc) :destruido)
      (remhash id (sys-npcs sys))
      (incf (getf (sys-metricas sys) :npcs-destruidos))
      t)))

;;; ---------------------------------------------------------------------------
;;; Mannequin Groups — sistema de formações
;;; ---------------------------------------------------------------------------

(defun criar-grupo-mannequin (sys quantidade formacao &key (posicao '(0 0 0)))
  "Cria um grupo de mannequins em formação coordenada."
  (let ((grupo-id (incf (sys-grupo-counter sys)))
        (membros '()))
    ;; Criar mannequins individuais
    (dotimes (i quantidade)
      (let* ((offset (%calcular-posicao-formacao formacao i quantidade))
             (pos-npc (mapcar #'+ posicao offset))
             (npc (criar-npc sys :mannequin
                             :nome (format nil "mannequin-~a-~a" grupo-id i)
                             :posicao pos-npc)))
        (push (npc-id npc) membros)))

    (let ((grupo (make-mannequin-grupo
                  :id grupo-id
                  :formacao formacao
                  :membros (nreverse membros)
                  :posicao-centro posicao)))
      (push grupo (sys-grupos sys))
      (incf (getf (sys-metricas sys) :grupos-formados))
      grupo)))

(defun %calcular-posicao-formacao (formacao indice total)
  "Calcula offset de posição para um membro em formação."
  (case formacao
    (:plateia
     ;; Filas escalonadas
     (let ((col (mod indice 10))
           (row (floor indice 10)))
       (list (* col 2) 0 (* row 2))))
    (:circulo
     ;; Círculo ao redor do centro
     (let ((angulo (* 2 pi (/ indice total)))
           (raio (+ 5 (floor total 10))))
       (list (round (* raio (cos angulo)))
             0
             (round (* raio (sin angulo))))))
    (:fila
     ;; Fila reta
     (list (* indice 2) 0 0))
    (:dispersa
     ;; Posições pseudo-aleatórias
     (list (- (mod (* indice 7) 20) 10)
           0
           (- (mod (* indice 13) 20) 10)))
    (:coreografia
     ;; Mesma posição (coreografia calculada por animação)
     (list 0 0 0))
    (t (list 0 0 0))))

;;; ---------------------------------------------------------------------------
;;; Animação de grupo
;;; ---------------------------------------------------------------------------

(defun animar-grupo (sys grupo-id animacao)
  "Define animação sincronizada para um grupo de mannequins."
  (let ((grupo (find grupo-id (sys-grupos sys) :key #'mannequin-grupo-id)))
    (when grupo
      (setf (mannequin-grupo-animacao grupo) animacao)
      (dolist (npc-id (mannequin-grupo-membros grupo))
        (let ((npc (gethash npc-id (sys-npcs sys))))
          (when npc
            (setf (gethash "animacao" (npc-propriedades npc)) animacao))))
      t)))

(defun mudar-formacao (sys grupo-id nova-formacao)
  "Muda a formação de um grupo de mannequins."
  (let ((grupo (find grupo-id (sys-grupos sys) :key #'mannequin-grupo-id)))
    (when grupo
      (setf (mannequin-grupo-formacao grupo) nova-formacao)
      ;; Recalcular posições
      (let ((centro (mannequin-grupo-posicao-centro grupo))
            (total (length (mannequin-grupo-membros grupo))))
        (loop for npc-id in (mannequin-grupo-membros grupo)
              for i from 0
              do (let* ((offset (%calcular-posicao-formacao nova-formacao i total))
                        (pos (mapcar #'+ centro offset))
                        (npc (gethash npc-id (sys-npcs sys))))
                   (when npc
                     (setf (npc-posicao npc) pos)))))
      t)))

;;; ---------------------------------------------------------------------------
;;; Script execution — NPCs narrativos
;;; ---------------------------------------------------------------------------

(defun executar-script-step (sys npc-id)
  "Executa o próximo passo do script de um NPC narrativo."
  (let ((npc (gethash npc-id (sys-npcs sys))))
    (when (and npc (npc-script npc))
      (let ((idx (npc-script-idx npc))
            (script (npc-script npc)))
        (when (< idx (length script))
          (let ((acao (nth idx script)))
            (incf (npc-script-idx npc))
            ;; Executar ação
            (cond
              ((stringp acao)         ; Fala
               (format t "[~a] ~a~%" (npc-nome npc) acao))
              ((and (consp acao) (eq (car acao) :mover))
               (setf (npc-posicao npc) (cdr acao)))
              ((and (consp acao) (eq (car acao) :emote))
               (format t "[~a] *~a*~%" (npc-nome npc) (cdr acao)))
              (t nil))
            acao))))))

;;; ---------------------------------------------------------------------------
;;; Congelamento — Caine morre
;;; ---------------------------------------------------------------------------

(defun congelar-todos (sys)
  "Congela todos os NPCs — Caine foi deletado.
   NPCs param no lugar sem animação. Plateia de mannequins congela."
  (setf (sys-caine-ativo sys) nil)
  (format t "[NPC-System] ████ CONTROLADOR PERDIDO ████~%")
  (format t "[NPC-System] Congelando todos os NPCs...~%")

  (let ((count 0))
    (maphash (lambda (id npc)
               (declare (ignore id))
               (when (member (npc-estado npc) '(:ativo :scripted :combate))
                 (setf (npc-estado npc) :congelado)
                 (signal 'npc-congelado :npc-id (npc-id npc))
                 (incf count)))
             (sys-npcs sys))
    (incf (getf (sys-metricas sys) :congelamentos))
    (format t "[NPC-System] ~a NPCs congelados. Sem IA para movê-los.~%~%" count)
    count))

;;; ---------------------------------------------------------------------------
;;; Tick do sistema
;;; ---------------------------------------------------------------------------

(defun npc-system-tick (sys)
  "Tick global — atualiza todos os NPCs ativos."
  (unless (sys-caine-ativo sys)
    (return-from npc-system-tick nil))

  (maphash (lambda (id npc)
             (declare (ignore id))
             (when (eq (npc-estado npc) :scripted)
               (executar-script-step sys (npc-id npc))))
           (sys-npcs sys))
  t)

;;; ---------------------------------------------------------------------------
;;; Status
;;; ---------------------------------------------------------------------------

(defun npc-system-status (sys)
  (let ((por-tipo (make-hash-table :test 'eq))
        (por-estado (make-hash-table :test 'eq)))
    (maphash (lambda (id npc)
               (declare (ignore id))
               (incf (gethash (npc-tipo npc) por-tipo 0))
               (incf (gethash (npc-estado npc) por-estado 0)))
             (sys-npcs sys))
    (list :caine-ativo (sys-caine-ativo sys)
          :total-ativos (hash-table-count (sys-npcs sys))
          :grupos (length (sys-grupos sys))
          :por-tipo por-tipo
          :por-estado por-estado
          :metricas (sys-metricas sys))))

(defun npc-system-imprimir-status (sys)
  (format t "~%[NPC-System] === STATUS ===~%")
  (format t "  Caine ativo:  ~a~%" (sys-caine-ativo sys))
  (format t "  NPCs ativos:  ~a/~a~%"
          (hash-table-count (sys-npcs sys)) (sys-max-npcs sys))
  (format t "  Grupos:       ~a~%" (length (sys-grupos sys)))
  (format t "  Criados:      ~a~%" (getf (sys-metricas sys) :npcs-criados))
  (format t "  Mannequins:   ~a~%" (getf (sys-metricas sys) :mannequins-criados))
  (format t "  Congelados:   ~a vezes~%" (getf (sys-metricas sys) :congelamentos))
  (format t "[NPC-System] === END ===~%~%"))

;;; ---------------------------------------------------------------------------
;;; EOF — npc-system.lisp
;;; ---------------------------------------------------------------------------
