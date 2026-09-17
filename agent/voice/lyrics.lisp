;;;; ============================================================================
;;;; lyrics.lisp — Letras: formato .lyrics, linter de cantabilidade, alinhamento
;;;; sílaba→nota e G2P pt-BR (phonemize) para o DiffSinger/OpenUtau.
;;;; ============================================================================
;;;; Fluxo (ADR 005):
;;;;
;;;;   lyrics write     tema + estilo → letra com seções  (template local ou NIM)
;;;;   lyrics analyze   letra → relatório do linter (sílabas, rima, metro, densidade)
;;;;   lyrics align     letra + MIDI → sílabas alinhadas às notas (DiffSinger/OpenUtau)
;;;;   lyrics phonemize letra → fonemas X-SAMPA pt-BR (hint; produção usa dsdict-pt)
;;;;   lyrics edit      letra + instrução → edição local ou via NIM
;;;;
;;;; Formato canônico (.lyrics):
;;;;   # comentário
;;;;   @title Título da música
;;;;   @tempo 128
;;;;   [Intro]
;;;;   linha 1
;;;;   linha 2
;;;;
;;;; Silabificação: regras determinísticas + dicionário de exceções (heurística
;;;; de análise; a produção de fonemas delega ao G2P do OpenUtau/DiffSinger).
;;;; ============================================================================

(in-package :caine.voice)

;;; ---------------------------------------------------------------------------
;;; Modelo: CANCAO (título, tempo, seções), cada seção tem linhas de letra
;;; ---------------------------------------------------------------------------

(defstruct lyric-linha
  (texto "" :type string)
  (silabas 0 :type integer)
  (rima "" :type string)          ; chave de rima (derivável)
  (aberto nil))                   ; fim de verso em vogal aberta

(defstruct lyric-secao
  (tag "Verse" :type string)
  (linhas '() :type list))        ; lista de LYRIC-LINHA

(defstruct cancao
  (titulo "Música" :type string)
  (tempo 120 :type integer)
  (secoes '() :type list))        ; lista de LYRIC-SECAO

;;; ---------------------------------------------------------------------------
;;; Silabificador pt-BR (regras + exceções) — heuristic de análise/lint
;;; ---------------------------------------------------------------------------

(defun vogal-forte-p (c)
  "Vogais fortes (abertas/tônicas) em pt-BR."
  (member (char-downcase c)
          '(#\a #\e #\o #\á #\é #\ó #\â #\ê #\ô #\ã #\õ)
          :test #'char=))

(defun vogal-fraca-p (c)
  "Vogais fracas (i/u, semivogais) em pt-BR."
  (member (char-downcase c) '(#\i #\u #\í #\ú) :test #'char=))

(defun vogal-p (c) (or (vogal-forte-p c) (vogal-fraca-p c)))

(defun vogal-aberta-p (c)
  "Vogais abertas (fins de verso favoráveis ao canto)."
  (member (char-downcase c)
          '(#\a #\e #\o #\á #\é #\ó #\â #\ê #\ô #\ã) :test #'char=))

(defparameter *diftongos-nasais* '("ão" "ãe" "õe" "ãi" "õi" "õu")
  "Diftongos nasais que formam uma só sílaba.")

(defparameter *excecoes-silabas*
  '(("dia" . 2) ("fia" . 2) ("lua" . 2) ("rua" . 2) ("sua" . 2) ("tua" . 2)
    ("nu" . 1) ("piauí" . 3))
  "Dicionário de exceções de contagem silábica (heurística).")

(defun limpar-u-silencioso (s)
  "Remove o U silencioso depois de Q/G antes de E/I (que, qui, gue, gui)."
  (let ((out (make-array 0 :element-type 'character :adjustable t
                            :fill-pointer 0)))
    (loop for i below (length s)
          for ch = (char s i)
          for prev = (and (plusp i) (char s (1- i)))
          for nxt = (and (< (1+ i) (length s)) (char s (1+ i)))
          do (unless (and (char-equal ch #\u)
                          prev
                          (member prev '(#\q #\g) :test #'char-equal)
                          nxt
                          (member nxt '(#\e #\i) :test #'char-equal))
               (vector-push-extend ch out)))
    out))

(defun grupos-vogais (s)
  "Lista de (INICIO . FIM) das sequências de vogais consecutivas em S."
  (let ((groups '()) (start nil))
    (loop for i from 0 to (length s)
          for vi = (and (< i (length s)) (vogal-p (char s i)))
          do (cond
               (vi (unless start (setf start i)))
               (start (push (cons start (1- i)) groups) (setf start nil))))
    (nreverse groups)))

(defun nucleos-no-grupo (s start end)
  "Índices dos núcleos silábicos no grupo de vogais [START END] de S.
   Forte abre núcleo; fraca absorve (semivogal). Diftongo nasal = 1 núcleo."
  (if (and (= 1 (- end start))
           (member (subseq s start (1+ end)) *diftongos-nasais*
                   :test #'string=))
      (list start)
      (loop for i from start to end
            when (vogal-forte-p (char s i)) collect i)))

(defun onset-dupleto-p (a b)
  "A/B formam onset de duas consoantes válido em pt-BR (bl, pr, st, ...)."
  (let ((stop '(#\b #\p #\t #\d #\k #\g #\c #\f)))
    (or (and (member a stop :test #'char=)
             (member b '(#\l #\r) :test #'char=))
        (and (char-equal a #\s)
             (or (member b stop :test #'char=)
                 (member b '(#\l #\r #\n #\m) :test #'char=))))))

(defun silabas-de-palavra (word)
  "Segmenta WORD em sílabas (lista de strings). Heurística determinística:
   núcleos vocálicos + onsets/codas por regras; exceções só ajustam a contagem."
  (let* ((s (limpar-u-silencioso (string-downcase word)))
         (nuclei
           (let ((acc '()) (prev-end -1))
             (dolist (run (grupos-vogais s))
               (let ((nucs (nucleos-no-grupo s (car run) (cdr run))))
                 (loop for k below (length nucs)
                       for ns = (nth k nucs)
                       for pev = (if (zerop k) prev-end (1- ns))
                       do (push (cons ns pev) acc))
                 (setf prev-end (cdr run))))
             (nreverse acc))))
    (if (null nuclei)
        (list s)
        ;; onset = início da sílaba de cada núcleo (bloco consonantal à esquerda)
        (let* ((onsets
                 (loop for k below (length nuclei)
                       for (ns . pev) = (nth k nuclei)
                       for blk = (subseq s (1+ pev) ns)
                       for blen = (length blk)
                       collect (cond ((zerop k) 0)
                                     ((zerop blen) ns)
                                     ((= blen 1) (1- ns))
                                     ((and (>= blen 2)
                                           (onset-dupleto-p
                                            (char blk (- blen 2))
                                            (char blk (1- blen))))
                                      (- ns 2))
                                     (t (1- ns)))))
               (starts '()) (prev 0))
          ;; passa única: garante limites crescentes (nunca invertem)
          (dolist (o onsets)
            (push (max o prev) starts)
            (setf prev (max o prev)))
          (setf starts (nreverse starts))
          (loop for k below (length starts)
                for b0 = (nth k starts)
                for b1 = (if (< (1+ k) (length starts))
                             (nth (1+ k) starts)
                             (length s))
                collect (subseq s b0 (max b0 b1)))))))

(defun contar-silabas-palavra (word)
  "Conta sílabas de WORD usando exceções; senão heuristic."
  (let ((key (string-downcase (string-trim '(#\Space #\Tab) word))))
    (let ((exc (cdr (assoc key *excecoes-silabas* :test #'string=))))
      (if exc exc (length (silabas-de-palavra key))))))

(defun palavras-de-frase (frase)
  "Lista de palavras (lowercase) de FRASE."
  (let ((acc '()) (cur '()))
    (flet ((flush ()
             (when cur
               (push (coerce (nreverse cur) 'string) acc)
               (setf cur '()))))
      (loop for ch across (string-downcase frase)
            do (if (or (alpha-char-p ch) (char-equal ch #\Ç))
                   (push ch cur)
                   (flush)))
      (flush))
    (nreverse acc)))

(defun silabas-de-frase (frase)
  "Conta sílabas de FRASE (soma por palavra, regras + exceções)."
  (loop for p in (palavras-de-frase frase)
        sum (contar-silabas-palavra p)))

(defun limpar-acentos (s &optional (lower nil))
  "Remove acentos de S (comparação de rima) e, se LOWER, minúsculas."
  (let ((out (make-array 0 :element-type 'character :adjustable t
                            :fill-pointer 0))
        (map (list (cons #\á #\a) (cons #\à #\a) (cons #\â #\a) (cons #\ã #\a)
                   (cons #\é #\e) (cons #\è #\e) (cons #\ê #\e)
                   (cons #\í #\i) (cons #\ì #\i) (cons #\î #\i)
                   (cons #\ó #\o) (cons #\ò #\o) (cons #\ô #\o) (cons #\õ #\o)
                   (cons #\ú #\u) (cons #\ù #\u) (cons #\û #\u)
                   (cons #\ç #\c))))
    (loop for c across s
          do (let ((m (assoc c map :test #'char=)))
               (vector-push-extend (cond (m (cdr m))
                                         (lower (char-downcase c))
                                         (t c))
                                   out)))
    out))

(defun ultima-palavra (frase)
  "Última palavra de FRASE (string)."
  (car (last (palavras-de-frase frase))))

(defun chave-rima (frase)
  "Chave de rima de FRASE: da vogal tônica (última vogal acentuada, senão a
   última) até o fim da palavra, normalizada para comparação."
  (let* ((p (ultima-palavra frase))
         (s (string-downcase p))
         (acc (loop for i downfrom (1- (length s)) to 0
                    for c = (char s i)
                    when (member c '(#\á #\é #\í #\ó #\ú #\â #\ê #\ô #\ã #\õ)
                                 :test #'char=)
                      return i))
         (v (loop for i downfrom (1- (length s)) to 0
                  when (vogal-p (char s i)) return i))
         (i (or acc v)))
    (when i (limpar-acentos (subseq s i) t))))

(defun fim-aberto-p (frase)
  "T se a última palavra de FRASE termina com vogal aberta (bom p/ canto)."
  (let* ((p (ultima-palavra frase))
         (s (string-downcase p)))
    (when (plusp (length s))
      (vogal-aberta-p (char s (1- (length s)))))))

(defun remove-substrings (s subs)
  "Remove SUB (strings, case-insensitive) de S."
  (let ((out s))
    (dolist (sub subs)
      (loop for pos = (search sub out :test #'char-equal)
            while pos
            do (setf out (concatenate 'string
                                      (subseq out 0 pos)
                                      (subseq out (+ pos (length sub)))))))
    out))

;;; ---------------------------------------------------------------------------
;;; Parsing / escrita do formato .lyrics
;;; ---------------------------------------------------------------------------

(defun split-lines (texto)
  "Divide TEXTO em linhas (corta CR/LF)."
  (let ((linhas '()) (start 0))
    (loop for i from 0 to (length texto)
          do (when (or (= i (length texto))
                       (char= (char texto i) #\Newline))
               (push (string-trim '(#\Return)
                                  (subseq texto start (min i (length texto))))
                     linhas)
               (setf start (1+ i))))
    (nreverse linhas)))

(defun parse-cancao (texto)
  "Converte TEXTO (.lyrics) numa CANCAO (com sílabas e rima derivadas)."
  (let ((cancao (make-cancao))
        (sec nil))
    (labels ((nova-secao (tag)
               (when sec (push sec (cancao-secoes cancao)))
               (setf sec (make-lyric-secao :tag (string-upcase tag)
                                           :linhas '()))))
      (dolist (raw (split-lines texto))
        (let ((line (string-trim '(#\Space #\Tab #\Return) raw)))
          (cond
            ((zerop (length line)))                          ; vazio
            ((char= (char line 0) #\#))                      ; comentário
            ((and (>= (length line) 6)
                  (string= "@title" line :end2 6))
             (setf (cancao-titulo cancao)
                   (string-trim '(#\Space #\Tab) (subseq line 6))))
            ((and (>= (length line) 6)
                  (string= "@tempo" line :end2 6))
             (setf (cancao-tempo cancao)
                   (or (parse-integer (string-trim '(#\Space #\Tab)
                                                   (subseq line 6))
                                      :junk-allowed t)
                       120)))
            ((and (plusp (length line))
                  (char= (char line 0) #\[)
                  (char= (char line (1- (length line))) #\]))
             (nova-secao (string-trim '(#\Space #\Tab)
                                      (subseq line 1 (1- (length line))))))
            (t
             (unless sec (nova-secao "Verse"))
             (push (make-lyric-linha :texto line
                                     :silabas (silabas-de-frase line)
                                     :rima (chave-rima line)
                                     :aberto (fim-aberto-p line))
                   (lyric-secao-linhas sec))))))
      (when sec (push sec (cancao-secoes cancao)))
      (setf (cancao-secoes cancao) (nreverse (cancao-secoes cancao)))
      (dolist (s (cancao-secoes cancao))
        (setf (lyric-secao-linhas s) (nreverse (lyric-secao-linhas s))))
      cancao)))

(defun ler-cancao (path)
  "Lê PATH (.lyrics) e devolve uma CANCAO."
  (parse-cancao (uiop:read-file-string path)))

(defun escrever-cancao (cancao path &optional (stream nil))
  "Escreve CANCAO em PATH no formato .lyrics (ou em STREAM)."
  (let ((out (or stream (open path :direction :output :if-exists :supersede
                                   :if-does-not-exist :create
                                   :external-format :utf-8))))
    (unwind-protect
        (progn
          (format out "# ~a~%" (cancao-titulo cancao))
          (format out "@title ~a~%" (cancao-titulo cancao))
          (format out "@tempo ~d~%~%" (cancao-tempo cancao))
          (loop for s in (cancao-secoes cancao)
                do (format out "[~a]~%" (lyric-secao-tag s))
                   (dolist (l (lyric-secao-linhas s))
                     (format out "~a~%" (lyric-linha-texto l)))
                   (format out "~%")))
      (unless stream (close out)))
    path))

;;; ---------------------------------------------------------------------------
;;; Linter de cantabilidade (analyze)
;;; ---------------------------------------------------------------------------

(defun analisar-letra (cancao &key (bpm nil))
  "Relatório do linter de cantabilidade de CANCAO. Retorna string."
  (let ((out (make-string-output-stream))
        (total-silabas 0)
        (total-linhas 0))
    (labels ((p (fmt &rest a) (apply #'format out fmt a) (terpri out)))
      (p "~a — ~d BPM" (cancao-titulo cancao) (cancao-tempo cancao))
      (p "~d seção(ões)" (length (cancao-secoes cancao)))
      (p "")
      (loop for s in (cancao-secoes cancao)
            for n = (length (lyric-secao-linhas s))
            for sil = (loop for l in (lyric-secao-linhas s)
                            sum (lyric-linha-silabas l))
            do (incf total-linhas n)
               (incf total-silabas sil)
               (p "[~a]" (lyric-secao-tag s))
               (loop for l in (lyric-secao-linhas s)
                     for li from 1
                     for aberto = (lyric-linha-aberto l)
                     do (p "  ~2d ~2d sil  rima=~a~a  ~a"
                           li (lyric-linha-silabas l)
                           (if (zerop (length (lyric-linha-rima l)))
                               "-"
                               (lyric-linha-rima l))
                           (if aberto "" " (fim fechado)")
                           (lyric-linha-texto l)))
               (p "   → ~d sílabas em ~d linha(s)" sil n)
               (p ""))
      ;; metro pareado entre seções com a mesma tag
      (let ((por-tag (make-hash-table :test 'equal)))
        (dolist (s (cancao-secoes cancao))
          (push s (gethash (string-upcase (lyric-secao-tag s)) por-tag)))
        (maphash (lambda (tag secoes)
                   (when (> (length secoes) 1)
                     (let ((sil (mapcar
                                 (lambda (sc)
                                   (loop for l in (lyric-secao-linhas sc)
                                         sum (lyric-linha-silabas l)))
                                 (nreverse secoes))))
                       (p "Metro [~a]: ~{~d~^ / ~} síl." tag sil)
                       (when (/= (apply #'max sil) (apply #'min sil))
                         (p "  ⚠ metro desigual entre seções ~a" tag))
                       (p ""))))
                 por-tag))
      ;; densidade por BPM
      (when bpm
        (let* ((ms (/ 60000.0 (max 1 bpm)))
               (sil-min (/ 60000.0 ms)))
          (p "Densidade @ ~d BPM: ~,1f ms/sílaba (~,0f sílabas/min)"
             bpm ms sil-min)
          (p "  (limiar confortável de canto ≈ 160–300 ms/sílaba)")
          (when (< ms 160)
            (p "  ⚠ densidade alta — texto ficou rápido demais para cantar."))
          (p "")))
      (p "Total: ~d sílabas em ~d linhas" total-silabas total-linhas)
      (get-output-stream-string out))))

;;; ---------------------------------------------------------------------------
;;; Geração por template (write, fallback sem NIM)
;;; ---------------------------------------------------------------------------

(defparameter *estruturas-por-estilo*
  '(("pop"     ("Intro" "Verse 1" "Pre-Chorus" "Chorus" "Verse 2" "Pre-Chorus"
                "Chorus" "Bridge" "Chorus" "Outro"))
    ("rock"    ("Intro" "Verse 1" "Chorus" "Verse 2" "Chorus" "Bridge" "Chorus"
                "Outro"))
    ("rap"     ("Intro" "Verse 1" "Chorus" "Verse 2" "Chorus" "Verse 3" "Chorus"
                "Outro"))
    ("balada"  ("Intro" "Verse 1" "Verse 2" "Chorus" "Verse 3" "Chorus" "Bridge"
                "Chorus" "Outro"))
    ("eletrônica" ("Intro" "Verse 1" "Chorus" "Verse 2" "Chorus" "Drop" "Chorus"
                   "Outro"))
    ("mpb"     ("Intro" "Verse 1" "Chorus" "Verse 2" "Chorus" "Bridge" "Chorus"
                "Outro"))
    ("forró"   ("Intro" "Verse 1" "Chorus" "Verse 2" "Chorus" "Bridge" "Chorus"
                "Outro"))
    ("default" ("Intro" "Verse 1" "Chorus" "Verse 2" "Chorus" "Bridge" "Chorus"
                "Outro"))))

(defparameter *lexico-verso*
  '("a gente vai até o fim da estrada"
    "o sol acorda antes da cidade"
    "cada esquina guarda uma lembrança"
    "eu sigo a bússola do meu coração"
    "o vento sopra leve na varanda"
    "toda saudade tem um nome e um rosto"
    "as estrelas piscam pra contar segredos"
    "quem corre esquece onde estava indo"))

(defparameter *lexico-refrao*
  '("vem comigo que o mundo acende"
    "vamos dançar até o dia raiar"
    "todo mundo canta junto até cansar"
    "a noite inteira a gente não se deixa"
    "joga a tristeza pra trás da porta"
    "me dá a mão e a gente atravessa"))

(defparameter *lexico-bridge*
  '("e se o mundo desabar a gente se inventa"
    "silêncio também ensina a escutar"
    "entre o medo e o sonho há só um passo"
    "o que a gente cala o coração ainda entende"))

(defun linha-tpl (lexico seed ext)
  "Linha de LEXICO espelhada por SEED (determinística) com extensão EXT."
  (let ((base (nth (mod seed (length lexico)) lexico)))
    (if (and ext (plusp (length ext)))
        (format nil "~a — ~a" base ext)
        base)))

(defun gerar-letra (theme &key (style "default") (lang "pt") (tempo 120))
  "Gera uma CANCAO (rascunho por template) de THEME no ESTILO.
   Qualidade de rascunho — produção usa NIM (──nim)."
  (declare (ignore lang))
  (let* ((norm (string-trim '(#\Space) theme))
         (estrutura (or (second (assoc (string-downcase style)
                                       *estruturas-por-estilo*
                                       :test #'string=))
                        (second (assoc "default" *estruturas-por-estilo*
                                       :test #'string=))))
         (seed (reduce (lambda (a c) (+ a (char-code c))) norm
                       :initial-value 0))
         (cancao (make-cancao
                  :titulo (if (plusp (length norm)) norm "Canção")
                  :tempo tempo)))
    (loop for tag in estrutura
          for pass from 0
          for linhas =
            (cond
              ((search "Verse" tag)
               (list (linha-tpl *lexico-verso* (+ seed pass) norm)
                     (linha-tpl *lexico-verso* (+ seed pass 1) norm)
                     (linha-tpl *lexico-verso* (+ seed pass 2) norm)
                     (linha-tpl *lexico-verso* (+ seed pass 3) norm)))
              ((search "Chorus" tag)
               (list (linha-tpl *lexico-refrao* (+ seed pass) norm)
                     (linha-tpl *lexico-refrao* (+ seed pass 1) norm)
                     (linha-tpl *lexico-refrao* (+ seed pass 2) norm)
                     (linha-tpl *lexico-refrao* (+ seed pass 3) norm)))
              ((search "Bridge" tag)
               (list (linha-tpl *lexico-bridge* (+ seed pass) norm)
                     (linha-tpl *lexico-bridge* (+ seed pass 1) norm)))
              (t (list (linha-tpl *lexico-verso* (+ seed pass) norm))))
          do (push (make-lyric-secao
                    :tag tag
                    :linhas (mapcar (lambda (t1)
                                      (make-lyric-linha
                                       :texto t1
                                       :silabas (silabas-de-frase t1)
                                       :rima (chave-rima t1)
                                       :aberto (fim-aberto-p t1)))
                                    linhas))
                   (cancao-secoes cancao)))
    (setf (cancao-secoes cancao) (nreverse (cancao-secoes cancao)))
    cancao))

;;; ---------------------------------------------------------------------------
;;; Edição local (edit, fallback sem NIM) — micro-transformações
;;; ---------------------------------------------------------------------------

(defun copiar-cancao (c)
  "Cópia rasa de CANCAO (novas listas de seções/linhas)."
  (make-cancao :titulo (cancao-titulo c)
               :tempo (cancao-tempo c)
               :secoes (mapcar (lambda (s)
                                 (make-lyric-secao
                                  :tag (lyric-secao-tag s)
                                  :linhas (copy-list (lyric-secao-linhas s))))
                               (cancao-secoes c))))

(defun refazer-linha (l)
  "Re-deriva sílabas/rima/aberto de uma linha editada."
  (let ((txt (lyric-linha-texto l)))
    (make-lyric-linha :texto txt
                      :silabas (silabas-de-frase txt)
                      :rima (chave-rima txt)
                      :aberto (fim-aberto-p txt))))

(defun curta-linha (l n)
  "Linha truncada a N palavras (mantém metro mais curto)."
  (let* ((pal (palavras-de-frase (lyric-linha-texto l)))
         (pal (if (> (length pal) n) (subseq pal 0 n) pal))
         (txt (format nil "~{~a~^ ~}" pal)))
    (make-lyric-linha :texto txt
                      :silabas (silabas-de-frase txt)
                      :rima (chave-rima txt)
                      :aberto (fim-aberto-p txt))))

(defun editar-letra-local (cancao instrucao)
  "Aplica transformações locais simples a CANCAO segundo INSTRUCAO.
   Sem NIM, suporta: 'mais curta', 'mais direta', 'refrão duas vezes'."
  (let ((instr (string-downcase instrucao)))
    (cond
      ((search "curta" instr)
       (let* ((nova (copiar-cancao cancao)))
         (dolist (s (cancao-secoes nova))
           (setf (lyric-secao-linhas s)
                 (mapcar (lambda (l) (curta-linha l 6))
                         (lyric-secao-linhas s))))
         nova))
      ((search "direta" instr)
       (let* ((nova (copiar-cancao cancao)))
         (dolist (s (cancao-secoes nova))
           (setf (lyric-secao-linhas s)
                 (mapcar (lambda (l)
                           (refazer-linha
                            (make-lyric-linha
                             :texto (string-trim
                                     '(#\Space)
                                     (remove-substrings
                                      (lyric-linha-texto l)
                                      '("porque " " que "))))))
                         (lyric-secao-linhas s))))
         nova))
      ((search "refr" instr)
       (let* ((nova (copiar-cancao cancao))
              (chorus (find "chorus" (cancao-secoes nova)
                            :key (lambda (s)
                                   (string-downcase (lyric-secao-tag s)))
                            :test #'string=)))
         (when chorus
           (setf (cancao-secoes nova)
                 (append (cancao-secoes nova) (list chorus))))
         nova))
      (t cancao))))

;;; ---------------------------------------------------------------------------
;;; Alinhamento sílaba→nota (align) — DiffSinger/OpenUtau
;;; ---------------------------------------------------------------------------

(defstruct alinhamento
  (syllables '() :type list)   ; [text]
  (notes '() :type list)       ; [midi 0-127 | nil = rest]
  (durations '() :type list)   ; [beats]
  (onsets '() :type list)      ; [seconds]
  (avisos '() :type list))

(defun silabas-da-cancao (cancao)
  "Lista de sílabas (strings) de todas as linhas, em ordem."
  (loop for s in (cancao-secoes cancao)
        append (loop for l in (lyric-secao-linhas s)
                     append (loop for p in (palavras-de-frase
                                            (lyric-linha-texto l))
                                  append (silabas-de-palavra p)))))

(defun alinhar-letra (cancao melodia &key (rest-threshold 0.15))
  "Alinha as sílabas de CANCAO às notas de MELODIA.
   1 sílaba/nota; nota excedente → melisma (última sílaba); vão maior que
   REST-THRESHOLD segundos → REST. Retorna (values alinhamento avisos)."
  (let* ((sils (silabas-da-cancao cancao))
         (notas (sort (copy-list (melodia-notas melodia)) #'< :key #'nota-onset))
         (avisos '())
         (n-on (length notas))
         (n-sil (length sils))
         (sy '()) (nt '()) (du '()) (on '()))
    (cond ((null notas)
           (push "melodia vazia — nada a alinhar" avisos))
          ((> n-sil n-on)
           (push (format nil "⚠ ~d sílaba(s) sem nota — estouro sílaba/nota"
                         (- n-sil n-on))
                 avisos))
          ((< n-sil n-on)
           (push (format nil "~d nota(s) excedente(s) → melisma (vogal estendida)"
                         (- n-on n-sil))
                 avisos))
          (t (push (format nil "✓ ~d sílabas para ~d notas" n-sil n-on) avisos)))
    (loop for i below n-on
          for n = (nth i notas)
          for prev = (and (plusp i) (nth (1- i) notas))
          for sil = (if (< i n-sil)
                        (nth i sils)
                        (let ((ult (and (plusp n-sil) (nth (1- n-sil) sils))))
                          (if ult ult "-")))
          for dur = (max 0.05 (- (nota-offset n) (nota-onset n)))
          for beats = (/ (* dur (melodia-bpm melodia)) 60.0)
          for gap = (and prev (max 0 (- (nota-onset n) (nota-offset prev))))
          do (when (and gap (> gap rest-threshold))
               (push "-" sy)
               (push nil nt)
               (push (/ (* gap (melodia-bpm melodia)) 60.0) du)
               (push (nota-offset prev) on))
             (push sil sy)
             (push (nota-pitch n) nt)
             (push beats du)
             (push (nota-onset n) on))
    (values
     (make-alinhamento
      :syllables (nreverse sy)
      :notes (nreverse nt)
      :durations (nreverse du)
      :onsets (nreverse on)
      :avisos (nreverse avisos))
     (nreverse avisos))))

(defun escrever-align-diffsinger (al path)
  "Escreve PATH no formato DiffSinger (opencpop): text<TAB>notes<TAB>beats.
   REST usa midi 'none'."
  (ensure-out-dir path)
  (with-open-file (out path :direction :output :if-exists :supersede
                            :if-does-not-exist :create :external-format :utf-8)
    (format out "# text<TAB>notes<TAB>notes_duration(beats)~%")
    (loop for sil in (alinhamento-syllables al)
          for n in (alinhamento-notes al)
          for d in (alinhamento-durations al)
          do (if (null n)
                 (format out "~a~t~a~%" sil "REST")
                 (format out "~a~t~a~t~,4f~%" sil n d))))
  path)

(defun escrever-align-openutau (al path)
  "Escreve PATH com uma sílaba por linha (texto de letra do OpenUtau)."
  (ensure-out-dir path)
  (with-open-file (out path :direction :output :if-exists :supersede
                            :if-does-not-exist :create :external-format :utf-8)
    (dolist (sil (alinhamento-syllables al))
      (format out "~a~%" sil)))
  path)

;;; ---------------------------------------------------------------------------
;;; G2P pt-BR (phonemize) — hint X-SAMPA; produção delega ao dsdict-pt/OpenUtau
;;; ---------------------------------------------------------------------------

(defparameter *g2p-letras*
  '((#\a . "a") (#\b . "b") (#\d . "d") (#\e . "e") (#\f . "f") (#\g . "g") (#\i . "i") (#\j . "Z")
    (#\k . "k") (#\l . "l") (#\m . "m") (#\n . "n") (#\o . "o") (#\p . "p") (#\r . "4") (#\s . "s")
    (#\t . "t") (#\u . "u") (#\v . "v") (#\x . "S") (#\z . "z") (#\c . "s")
    (#\á . "a") (#\é . "E") (#\í . "i") (#\ó . "O") (#\ú . "u") (#\â . "6") (#\ê . "e") (#\ô . "o")
    (#\ã . "6~") (#\õ . "6~") (#\à . "a") (#\ç . "s") (#\w . "w") (#\y . "j")))

(defparameter *g2p-digrafos*
  '(("ch" . "S") ("lh" . "L") ("nh" . "J") ("rr" . "R") ("ss" . "s") ("gu" . "g")
    ("qu" . "k") ("sc" . "s") ("sç" . "s") ("xc" . "s")))

(defun fonemizar-palavra (palavra)
  "Converte PALAVRA em fonemas X-SAMPA (hint simples, espaçados).
   Dica manual — a produção usa o dsdict-pt do DiffSinger/OpenUtau."
  (let* ((p (limpar-u-silencioso (string-downcase palavra)))
         (out '())
         (i 0))
    (loop while (< i (length p))
          do (let* ((dg (and (< (1+ i) (length p))
                             (subseq p i (+ i 2))))
                    (m-dg (assoc dg *g2p-digrafos* :test #'string=)))
               (cond
                 (m-dg (push (cdr m-dg) out) (incf i 2))
                 (t (let* ((c (char p i))
                           (m (assoc c *g2p-letras* :test #'char=)))
                      (push (if m (cdr m) (string c)) out)
                      (incf i))))))
    ;; remove duplicatas de consoantes (rr→R já tratado; limpa restos)
    (format nil "~{~a~^ ~}" (nreverse out))))

(defun fonemizar-letra (cancao)
  "Relatório-fonema (hint X-SAMPA) de todas as linhas de CANCAO."
  (let ((out (make-string-output-stream)))
    (dolist (s (cancao-secoes cancao))
      (format out "[~a]~%" (lyric-secao-tag s))
      (dolist (l (lyric-secao-linhas s))
        (format out "  ~a~%"
                (loop for p in (palavras-de-frase (lyric-linha-texto l))
                      collect (fonemizar-palavra p) into fonemas
                      finally (return (format nil "~{~a~^  |  ~}" fonemas)))))
      (format out "~%"))
    (get-output-stream-string out)))