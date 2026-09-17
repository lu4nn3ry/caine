;;;; ============================================================================
;;;; json.lisp — Codec JSON mínimo, sem dependências externas
;;;; ============================================================================
;;;; Codificador e decodificador JSON em Common Lisp puro, suficiente para o
;;;; protocolo OpenAI-compatible do NVIDIA NIM (chat completions + tool calls).
;;;;
;;;; Representação canônica:
;;;;   objeto  → hash-table (:test 'equal), chaves string
;;;;   array   → vector
;;;;   string  → string
;;;;   número  → integer | float
;;;;   true    → T        false → :FALSE        null → :NULL
;;;;
;;;; Alists com chaves string também são aceitos na codificação (objeto), e
;;;; listas simples viram arrays.
;;;; ============================================================================

(in-package :caine.nim)

;;; ---------------------------------------------------------------------------
;;; Codificação
;;; ---------------------------------------------------------------------------

(defun json-write-string (s out)
  "Escreve S como string JSON escapada em OUT."
  (write-char #\" out)
  (loop for ch across s
        for code = (char-code ch)
        do (cond
             ((char= ch #\") (write-string "\\\"" out))
             ((char= ch #\\) (write-string "\\\\" out))
             ((char= ch #\Newline) (write-string "\\n" out))
             ((char= ch #\Return) (write-string "\\r" out))
             ((char= ch #\Tab) (write-string "\\t" out))
             ((< code 32) (format out "\\u~4,'0x" code))
             (t (write-char ch out))))
  (write-char #\" out))

(defun json-number-string (x)
  "Representação textual JSON de X (inteiro ou float)."
  (if (integerp x)
      (format nil "~d" x)
      (let ((s (substitute #\e #\d (format nil "~a" x))))
        ;; remove o expoente nulo produzido por ~a (ex.: 2.5e0 → 2.5)
        (if (and (> (length s) 2) (string= "e0" s :start2 (- (length s) 2)))
            (subseq s 0 (- (length s) 2))
            s))))

(defun json-object-alist-p (list)
  (and (consp list) (every #'consp list)))

(defun json-write (value out)
  "Escreve VALUE serializado como JSON no stream OUT."
  (cond
    ((eq value t) (write-string "true" out))
    ((eq value :true) (write-string "true" out))
    ((eq value :false) (write-string "false" out))
    ((or (eq value :null) (null value)) (write-string "null" out))
    ((stringp value) (json-write-string value out))
    ((integerp value) (write-string (json-number-string value) out))
    ((floatp value) (write-string (json-number-string value) out))
    ((hash-table-p value)
     (write-char #\{ out)
     (let ((first t))
       (maphash (lambda (k v)
                  (unless first (write-char #\, out))
                  (setf first nil)
                  (json-write-string (string k) out)
                  (write-char #\: out)
                  (json-write v out))
                value))
     (write-char #\} out))
    ((vectorp value)
     (write-char #\[ out)
     (loop for i from 0 below (length value)
           do (when (> i 0) (write-char #\, out))
              (json-write (aref value i) out))
     (write-char #\] out))
    ((listp value)
     (if (json-object-alist-p value)
         (progn
           (write-char #\{ out)
           (loop for (k . v) in value
                 for i from 0
                 do (when (> i 0) (write-char #\, out))
                    (json-write-string (string k) out)
                    (write-char #\: out)
                    (json-write v out))
           (write-char #\} out))
         (progn
           (write-char #\[ out)
           (loop for item in value
                 for i from 0
                 do (when (> i 0) (write-char #\, out))
                    (json-write item out))
           (write-char #\] out))))
    ((or (keywordp value) (symbolp value))
     (json-write-string (string-downcase (symbol-name value)) out))
    (t (error 'json-error
              :mensagem (format nil "valor não serializável: ~s" value)))))

(defun json-encode (value)
  "Serializa VALUE em uma string JSON."
  (with-output-to-string (out) (json-write value out)))

;;; ---------------------------------------------------------------------------
;;; Decodificação — parser recursivo descendente
;;; ---------------------------------------------------------------------------

(defstruct (json-parser (:constructor make-json-parser (text)))
  (text "" :type string)
  (pos 0 :type fixnum))

(declaim (inline jp-peek jp-advance))

(defun jp-peek (p)
  "Caractere atual sem consumir, ou NIL no fim."
  (let ((i (json-parser-pos p))
        (s (json-parser-text p)))
    (when (< i (length s)) (char s i))))

(defun jp-advance (p)
  "Consome e retorna o caractere atual, ou NIL no fim."
  (let ((c (jp-peek p)))
    (when c (incf (json-parser-pos p)))
    c))

(defun jp-skip-ws (p)
  "Pula espaços em branco JSON."
  (loop for c = (jp-peek p)
        while (and c (member c '(#\Space #\Tab #\Newline #\Return)))
        do (jp-advance p)))

(defun jp-fail (p control &rest args)
  "Sinaliza um JSON-ERROR com posição."
  (error 'json-error
         :mensagem (format nil "~a (posição ~a)"
                           (apply #'format nil control args)
                           (json-parser-pos p))))

(defun json-hex4 (p)
  "Lê 4 dígitos hexadecimais (escape \\uXXXX)."
  (let ((val 0))
    (dotimes (i 4)
      (let* ((c (jp-advance p))
             (d (and c (digit-char-p c 16))))
        (unless d (jp-fail p "dígito hexadecimal inválido"))
        (setf val (+ (* val 16) d))))
    val))

(defun json-hex-escape (p)
  "Decodifica um escape \\u, tratando surrogate pairs UTF-16."
  (let ((code (json-hex4 p)))
    (cond
      ((<= #xD800 code #xDBFF)          ; high surrogate
       (let ((save (json-parser-pos p)))
         (if (and (eql (jp-peek p) #\\)
                  (progn (jp-advance p) (eql (jp-peek p) #\u)))
             (progn
               (jp-advance p)
               (let ((low (json-hex4 p)))
                 (if (<= #xDC00 low #xDFFF)
                     (or (code-char (+ #x10000
                                       (* (- code #xD800) #x400)
                                       (- low #xDC00)))
                         #\?)
                     (progn (setf (json-parser-pos p) save) #\?))))
             (progn (setf (json-parser-pos p) save) #\?))))
      ((<= #xDC00 code #xDFFF) #\?)      ; low surrogate solto
      (t (or (code-char code) #\?)))))

(defun json-expect (p literal)
  "Consome o literal esperado (true/false/null)."
  (loop for ch across literal
        do (unless (eql (jp-advance p) ch)
             (jp-fail p "literal inválido (esperado '~a')" literal))))

(defun json-parse-string (p)
  "Lê uma string JSON, resolvendo escapes."
  (unless (eql (jp-advance p) #\")
    (jp-fail p "esperado '\"'"))
  (with-output-to-string (out)
    (loop
      (let ((c (jp-advance p)))
        (cond
          ((null c) (jp-fail p "string não terminada"))
          ((char= c #\") (return))
          ((char= c #\\)
           (let ((e (jp-advance p)))
             (case e
               (#\" (write-char #\" out))
               (#\\ (write-char #\\ out))
               (#\/ (write-char #\/ out))
               (#\b (write-char #\Backspace out))
               (#\f (write-char #\Page out))
               (#\n (write-char #\Newline out))
               (#\r (write-char #\Return out))
               (#\t (write-char #\Tab out))
               (#\u (write-char (json-hex-escape p) out))
               (t (jp-fail p "escape inválido '\\~a'" e)))))
          (t (write-char c out)))))))

(defun json-parse-number (p)
  "Lê um número JSON como integer ou double-float."
  (let ((start (json-parser-pos p)))
    (loop for c = (jp-peek p)
          while (and c (or (digit-char-p c)
                           (member c '(#\- #\+ #\. #\e #\E))))
          do (jp-advance p))
    (let ((str (subseq (json-parser-text p) start (json-parser-pos p))))
      (when (string= str "") (jp-fail p "número inválido"))
      (handler-case
          (let ((*read-eval* nil)
                (*read-default-float-format* 'double-float))
            (multiple-value-bind (val pos)
                (read-from-string str nil nil)
              (unless (and (numberp val) (= pos (length str)))
                (jp-fail p "número inválido: ~a" str))
              val))
        (error () (jp-fail p "número inválido: ~a" str))))))

(defun json-parse-value (p)
  "Lê o próximo valor JSON."
  (jp-skip-ws p)
  (let ((c (jp-peek p)))
    (cond
      ((null c) (jp-fail p "fim inesperado da entrada"))
      ((char= c #\{) (json-parse-object p))
      ((char= c #\[) (json-parse-array p))
      ((char= c #\") (json-parse-string p))
      ((or (char= c #\-) (digit-char-p c)) (json-parse-number p))
      ((char= c #\t) (json-expect p "true") t)
      ((char= c #\f) (json-expect p "false") :false)
      ((char= c #\n) (json-expect p "null") :null)
      (t (jp-fail p "caractere inesperado '~a'" c)))))

(defun json-parse-object (p)
  "Lê um objeto JSON como hash-table."
  (jp-advance p)                            ; consome '{'
  (let ((table (make-hash-table :test 'equal)))
    (jp-skip-ws p)
    (when (char= (or (jp-peek p) #\Nul) #\})
      (jp-advance p)
      (return-from json-parse-object table))
    (loop
      (jp-skip-ws p)
      (let ((key (json-parse-string p)))
        (jp-skip-ws p)
        (unless (eql (jp-advance p) #\:)
          (jp-fail p "esperado ':' após chave"))
        (setf (gethash key table) (json-parse-value p)))
      (jp-skip-ws p)
      (let ((c (jp-advance p)))
        (cond ((null c) (jp-fail p "objeto não terminado"))
              ((char= c #\,) nil)
              ((char= c #\}) (return))
              (t (jp-fail p "esperado ',' ou '}'")))))
    table))

(defun json-parse-array (p)
  "Lê um array JSON como vector."
  (jp-advance p)                            ; consome '['
  (jp-skip-ws p)
  (when (char= (or (jp-peek p) #\Nul) #\])
    (jp-advance p)
    (return-from json-parse-array #()))
  (let ((items '()))
    (loop
      (push (json-parse-value p) items)
      (jp-skip-ws p)
      (let ((c (jp-advance p)))
        (cond ((null c) (jp-fail p "array não terminado"))
              ((char= c #\,) nil)
              ((char= c #\]) (return))
              (t (jp-fail p "esperado ',' ou ']")))))
    (coerce (nreverse items) 'vector)))

;;; ---------------------------------------------------------------------------
;;; API pública
;;; ---------------------------------------------------------------------------

(defun json-parse (text)
  "Decodifica TEXT (string JSON) para a representação canônica."
  (let ((p (make-json-parser text)))
    (let ((value (json-parse-value p)))
      (jp-skip-ws p)
      (when (jp-peek p)
        (jp-fail p "conteúdo extra após o valor JSON"))
      value)))

(defun json-get (object key &optional default)
  "Acessa KEY em um objeto JSON. Trata null e ausência como DEFAULT."
  (if (hash-table-p object)
      (multiple-value-bind (v present) (gethash key object)
        (cond ((not present) default)
              ((eq v :null) default)
              (t v)))
      default))

(defun json-put (object key value)
  "Define KEY=VALUE em um objeto JSON. Retorna OBJECT."
  (setf (gethash key object) value)
  object)

(defun make-json-object (&rest pairs)
  "Constrói um objeto JSON a partir de pares chave/valor alternados."
  (let ((h (make-hash-table :test 'equal)))
    (loop for (k v) on pairs by #'cddr
          do (setf (gethash k h) v))
    h))
