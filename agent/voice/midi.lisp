;;;; ============================================================================
;;;; midi.lisp — MIDI (SMF), transcrição de melodia e render (FluidSynth)
;;;; ============================================================================
;;;; Fluxo melódico (CPU, sem GPU):
;;;;
;;;;   transcrever   áudio  → .notes  (librosa/pyin, via venv em .midi/)
;;;;   escrever-smf  .notes → .mid    (escritor SMF próprio, em Lisp puro)
;;;;   render-midi   .mid   → .wav    (FluidSynth + SoundFont GM)
;;;;   cantar-melodia áudio → .wav    (opcional: seed-vc modo canto)
;;;;
;;;; Env: CAINE_SOUNDFONT (padrão /usr/share/sounds/sf2/FluidR3_GM.sf2)
;;;; ============================================================================

(in-package :caine.voice)

;;; ---------------------------------------------------------------------------
;;; Localização do venv de análise (.midi/)
;;; ---------------------------------------------------------------------------

(defun midi-home ()
  "Diretório do ambiente de análise MIDI."
  (uiop:ensure-directory-pathname
   (merge-pathnames ".midi/" (voice-tools-home))))

(defun midi-venv-dir () (merge-pathnames "venv/" (midi-home)))

(defun midi-python ()
  "Python do venv de análise (ou python3 do sistema)."
  (let ((py (merge-pathnames "bin/python" (midi-venv-dir))))
    (if (probe-file py) (namestring py) "python3")))

(defun midi-script ()
  "Caminho do midi_transcribe.py (ao lado deste arquivo)."
  (namestring (asdf:system-relative-pathname "caine-voice" "midi_transcribe.py")))

(defun midi-pronto-p () (probe-file (midi-venv-dir)))

;;; --- Engine polifônico (Basic Pitch) ---------------------------------------
;;; Transcrição AMT (multi-pitch) — necessária para instrumentos harmônicos
;;; (violão/piano/banda), onde o pyin monofônico erra oitavas e pula vozes.
;;; Roda em Python 3.10 (via uv) com tflite-runtime (CPU), sem TensorFlow.

(defun midi-poly-venv-dir () (merge-pathnames "venv-poly/" (midi-home)))

(defun midi-poly-python ()
  (let ((py (merge-pathnames "bin/python" (midi-poly-venv-dir))))
    (if (probe-file py) (namestring py) "python3.10")))

(defun basic-pitch-bin ()
  (namestring (merge-pathnames "bin/basic-pitch" (midi-poly-venv-dir))))

(defun midi-poly-pronto-p () (probe-file (basic-pitch-bin)))

(defun uv-bin ()
  "Executável do uv (gerenciador de Python), se disponível."
  (or (uiop:getenv "UV")
      (let ((p (merge-pathnames ".local/bin/uv" (user-homedir-pathname))))
        (if (probe-file p) (namestring p) "uv"))))

(defun instalar-midi ()
  "Cria o venv de análise (numpy/soundfile/librosa) e o venv polifônico
   do Basic Pitch (Python 3.10 + tflite-runtime)."
  (ensure-directories-exist (merge-pathnames "keep" (midi-home)))
  (println "== criando venv MIDI em ~a" (namestring (midi-venv-dir)))
  (run-cmd (list "python3" "-m" "venv" (namestring (midi-venv-dir))) :capture nil)
  (let ((pip (namestring (merge-pathnames "bin/pip" (midi-venv-dir)))))
    (unless (probe-file pip) (error "pip não encontrado no venv MIDI"))
    (run-cmd (list pip "install" "--upgrade" "pip") :capture nil)
    (run-cmd (list pip "install" "numpy" "soundfile" "librosa") :capture nil))
  (instalar-midi-poly)
  (println "== MIDI pronto: mono=~a poly=~a"
           (if (midi-pronto-p) "sim" "não")
           (if (midi-poly-pronto-p) "sim" "não"))
  (midi-pronto-p))

(defun instalar-midi-poly ()
  "Instala o engine polifônico (Basic Pitch) num venv Python 3.10 via uv."
  (let ((venv (midi-poly-venv-dir))
        (uv (uv-bin)))
    (unless (probe-file (merge-pathnames "bin/python" venv))
      (println "== criando venv polifônico (Python 3.10) em ~a" (namestring venv))
      (multiple-value-bind (o e code)
          (run-cmd (list uv "venv" "--python" "3.10" (namestring venv)))
        (declare (ignore o))
        (unless (zerop code) (error "uv venv falhou: ~a" e))))
    (let ((py (midi-poly-python)))
      (println "== instalando Basic Pitch (tflite, CPU)")
      (run-cmd (list uv "pip" "install" "--python" py
                     "basic-pitch" "setuptools<81" "numpy<2")
               :capture nil))
    (println "== Basic Pitch pronto: ~a" (if (midi-poly-pronto-p) "sim" "não"))
    (midi-poly-pronto-p)))

;;; ---------------------------------------------------------------------------
;;; Modelo de melodia / nota
;;; ---------------------------------------------------------------------------

(defparameter *soundfont*
  (or (uiop:getenv "CAINE_SOUNDFONT") "/usr/share/sounds/sf2/FluidR3_GM.sf2")
  "SoundFont GM usado no render.")

(defstruct nota
  (onset 0.0 :type single-float)
  (offset 0.0 :type single-float)
  (pitch 60 :type integer)
  (velocity 90 :type integer))

(defstruct melodia
  (bpm 120.0 :type real)
  (duracao 0.0 :type real)
  (programa 54 :type integer)
  (notas '() :type list))

(defun split-por-tab (line)
  "Divide LINE por tabs, descartando campos vazios."
  (let ((toks '()) (start 0))
    (loop for i from 0 below (length line)
          when (char= (char line i) #\Tab)
            do (when (> i start) (push (subseq line start i) toks))
               (setf start (1+ i)))
    (when (> (length line) start) (push (subseq line start) toks))
    (nreverse toks)))

(defun ler-melodia (notes-file &key (programa 54))
  "Lê NOTES-FILE (.notes) e devolve uma MELODIA."
  (let ((m (make-melodia :programa programa)))
    (with-open-file (s notes-file :direction :input :if-does-not-exist :error)
      (loop for line = (read-line s nil nil)
            while line
            for trimmed = (string-trim '(#\Space #\Tab #\Return) line)
            for len = (length trimmed)
            do (cond
                 ((zerop len))
                 ((char= (char trimmed 0) #\#))
                 ((and (>= len 4) (string= "bpm " trimmed :end2 4))
                  (setf (melodia-bpm m)
                        (read-from-string (subseq trimmed 4))))
                 ((and (>= len 9) (string= "duration " trimmed :end2 9))
                  (setf (melodia-duracao m)
                        (read-from-string (subseq trimmed 9))))
                 (t
                  (let ((toks (split-por-tab trimmed)))
                    (when (>= (length toks) 4)
                      (push (make-nota
                             :onset (read-from-string (first toks))
                             :offset (read-from-string (second toks))
                             :pitch (parse-integer (third toks))
                             :velocity (parse-integer (fourth toks)))
                            (melodia-notas m))))))))
    (setf (melodia-notas m) (nreverse (melodia-notas m)))
    m))

(defun transcrever (audio out-notes &key (fmin 65.0) (fmax 2093.0))
  "Transcreve a melodia de AUDIO para OUT-NOTES usando o venv .midi/."
  (unless (midi-pronto-p)
    (error "ambiente MIDI não instalado. Rode: caine-voice install midi"))
  (ensure-out-dir out-notes)
  (multiple-value-bind (o e code)
      (run-cmd (list (midi-python) (midi-script)
                     (namestring audio) (namestring out-notes)
                     "--fmin" (princ-to-string fmin)
                     "--fmax" (princ-to-string fmax))
               :capture nil)
    (declare (ignore o e))
    (unless (zerop code) (error "transcrição falhou (exit ~a)" code)))
  out-notes)

(defun newest-midi (dir)
  "MIDI mais recente em DIR (não recursivo)."
  (let ((mids (remove-if-not (lambda (p) (string-equal (pathname-type p) "mid"))
                             (directory (merge-pathnames "*.mid" dir)))))
    (first (sort mids #'> :key #'file-write-date))))

(defun transcrever-poly (audio outdir &key extra)
  "Transcreve AUDIO (polifônico) para MIDI com Basic Pitch, em OUTDIR.
   Retorna o caminho do MIDI gerado."
  (unless (midi-poly-pronto-p)
    (error "Basic Pitch não instalado. Rode: caine-voice install midi"))
  (let ((out-dir (uiop:ensure-directory-pathname outdir)))
    (ensure-directories-exist (merge-pathnames "keep" out-dir))
    (multiple-value-bind (o e code)
        (run-cmd (append (list (basic-pitch-bin) (namestring out-dir) (namestring audio))
                         extra)
                 :capture nil)
      (declare (ignore o))
      (unless (zerop code) (error "Basic Pitch falhou (exit ~a): ~a" code e)))
  (or (newest-midi outdir)
      (error "MIDI do Basic Pitch não encontrado em ~a" (namestring outdir)))))

;;; ---------------------------------------------------------------------------
;;; Correção de afinação (pitch correction) — MIDI e áudio
;;; ---------------------------------------------------------------------------
;;; Táticas (pesquisa 2026): detecção de tom por cobertura de escala + perfis
;;; de Krumhansl–Schmuckler; quantização à escala (max-shift em semitones);
;;; centralização dos pitch bends (Basic Pitch emite bends de até 2 st que
;;; "desafinam" no render); e correção do F0 por nota no WAV (librosa/pyin +
;;; pitch-shift por segmento com crossfade). Script: pitch_correct.py.

(defun pitch-correct-script ()
  "Caminho do pitch_correct.py (ao lado deste arquivo)."
  (namestring (asdf:system-relative-pathname "caine-voice" "pitch_correct.py")))

(defun afinar-midi (in out &key key mode (max-shift 2) (keep-bends nil))
  "Quantiza o MIDI IN à escala do tom detectado (K-S + cobertura).
   Move notas fora da escala para o grau mais próximo (≤ MAX-SHIFT st) e
   centraliza pitch bends. Devendo KEY, usa tom fixo; MODE maj|min|auto.
   Retorna OUT."
  (unless (midi-pronto-p)
    (error "ambiente MIDI não instalado. Rode: caine-voice install midi"))
  (ensure-out-dir out)
  (let ((args (list (midi-python) (pitch-correct-script) "midi"
                    "--in" (namestring in) "--out" (namestring out)
                    "--max-shift" (princ-to-string max-shift))))
    (when key (setf args (append args (list "--key" key))))
    (when mode (setf args (append args (list "--mode" mode))))
    (when keep-bends (setf args (append args (list "--keep-bends"))))
    (multiple-value-bind (o e code)
        (run-cmd args :capture nil)
      (declare (ignore o))
      (unless (zerop code) (error "afinação do MIDI falhou (exit ~a): ~a" code e)))
    out))

(defun afinar-audio (in out mid &key (max-shift 1.0))
  "Corrige o F0 por nota no WAV IN usando as notas de MID como alvo
   (pyin + pitch-shift por segmento, bounded a ±MAX-SHIFT st). Retorna OUT."
  (unless (midi-pronto-p)
    (error "ambiente MIDI não instalado. Rode: caine-voice install midi"))
  (ensure-out-dir out)
  (multiple-value-bind (o e code)
      (run-cmd (list (midi-python) (pitch-correct-script) "audio"
                     "--in" (namestring in) "--out" (namestring out)
                     "--mid" (namestring mid)
                     "--max-shift" (princ-to-string max-shift))
               :capture nil)
    (declare (ignore o))
    (unless (zerop code)
      (error "afinação do áudio falhou (exit ~a): ~a" code e)))
  out)

;;; ---------------------------------------------------------------------------
;;; Escritor de Standard MIDI File (SMF formato 0)
;;; ---------------------------------------------------------------------------

(defun varlen-bytes (n)
  "Codifica N como variable-length quantity (bytes big-endian)."
  (let ((bytes (list (logand n #x7f))))
    (loop while (>= (setf n (ash n -7)) 1)
          do (push (logior #x80 (logand n #x7f)) bytes))
    bytes))

(defun sec->ticks (sec bpm ppq)
  "Converte SEC (segundos) em ticks segundo BPM e PPQ."
  (round (* (float sec 1.0) (/ (float bpm 1.0) 60.0) ppq)))

(defun write-bytes (stream bytes)
  (dolist (b bytes) (write-byte (logand b #xff) stream)))

(defun write-u16 (stream n)
  (write-bytes stream (list (ldb (byte 8 8) n) (ldb (byte 8 0) n))))

(defun write-u32 (stream n)
  (write-bytes stream (list (ldb (byte 8 24) n) (ldb (byte 8 16) n)
                            (ldb (byte 8 8) n) (ldb (byte 8 0) n))))

(defun escrever-smf (melodia path &key (ppq 480))
  "Escreve PATH (.mid) com a MELODIA. Retorna PATH."
  (ensure-out-dir path)
  (let* ((bpm (max 1.0 (melodia-bpm melodia)))
         (us-q (round (/ 60000000.0 bpm)))
         (events '()))
    (push (cons 0.0 (list #xFF #x51 #x03
                          (ldb (byte 8 16) us-q)
                          (ldb (byte 8 8) us-q)
                          (ldb (byte 8 0) us-q)))
          events)
    (push (cons 0.0 (list #xC0 (logand (melodia-programa melodia) #x7f)))
          events)
    (dolist (n (melodia-notas melodia))
      (push (cons (nota-onset n)
                  (list #x90 (logand (nota-pitch n) #x7f)
                        (logand (nota-velocity n) #x7f)))
            events)
      (push (cons (nota-offset n)
                  (list #x80 (logand (nota-pitch n) #x7f) #x00))
            events))
    (setf events (stable-sort events #'< :key #'car))
    (let ((data '()) (last-tick 0))
      (dolist (ev events)
        (let* ((tick (sec->ticks (car ev) bpm ppq))
               (delta (max 0 (- tick last-tick))))
          (setf data (append data (varlen-bytes delta) (cdr ev)))
          (setf last-tick tick)))
      (setf data (append data (list #x00 #xFF #x2F #x00)))
      (with-open-file (s path :direction :output
                              :element-type '(unsigned-byte 8)
                              :if-exists :supersede
                              :if-does-not-exist :create)
        (write-bytes s (list #x4D #x54 #x68 #x64)) ; "MThd"
        (write-u32 s 6)
        (write-u16 s 0)                             ; formato 0
        (write-u16 s 1)                             ; 1 trilha
        (write-u16 s ppq)
        (write-bytes s (list #x4D #x54 #x72 #x6B)) ; "MTrk"
        (write-u32 s (length data))
        (write-bytes s data))))
  path)

(defun notas->midi (notes-file mid &key (programa 54))
  "Converte NOTES-FILE em MIDI. Retorna MID."
  (escrever-smf (ler-melodia notes-file :programa programa) mid))

;;; ---------------------------------------------------------------------------
;;; Leitor de Standard MIDI File (formatos 0 e 1)
;;; ---------------------------------------------------------------------------
;;; Usado pelo alinhamento letra→nota (ADR 005) para ler o .mid transcrito
;;; (ADR 004) e casar sílabas com notas.

(defun %read-u8 (s)
  "Lê um byte ou NIL em EOF."
  (read-byte s nil nil))

(defun %read-u16 (s)
  "Lê um inteiro big-endian de 16 bits."
  (let ((a (%read-u8 s)) (b (%read-u8 s)))
    (unless (and a b) (return-from %read-u16 nil))
    (logior (ash a 8) b)))

(defun %read-u32 (s)
  "Lê um inteiro big-endian de 32 bits."
  (let ((a (%read-u8 s)) (b (%read-u8 s)) (c (%read-u8 s)) (d (%read-u8 s)))
    (unless (and a b c d) (return-from %read-u32 nil))
    (logior (ash a 24) (ash b 16) (ash c 8) d)))

(defun %read-ascii (s n)
  "Lê N bytes como string ASCII."
  (let ((buf (make-array n :element-type 'character)))
    (dotimes (i n buf)
      (setf (char buf i) (code-char (or (%read-u8 s) 0))))))

(defun %ler-varlen (s)
  "Lê uma quantity variable-length (SMF: delta / meta length)."
  (let ((value 0))
    (loop
      (let ((b (%read-u8 s)))
        (unless b (return value))
        (setf value (logior (logand b #x7f)
                            (ash value 7)))
        (when (zerop (logand b #x80)) (return value))))))

(defun ler-smf (path)
  "Lê PATH (.mid) e devolve uma MELODIA (notas em segundos).
   Suporta SMF formato 0 e 1, running status e mudanças de tempo (meta 0x51)."
  (with-open-file (s path :direction :input :element-type '(unsigned-byte 8)
                          :if-does-not-exist :error)
    (unless (string= (%read-ascii s 4) "MThd")
      (error "não é um arquivo MIDI válido: ~a" path))
    (%read-u32 s)                         ; len do header (6)
    (let ((formato (%read-u16 s))
          (ntrks (%read-u16 s))
          (div (%read-u16 s)))
      (declare (ignore formato))
      (unless div (error "header SMF truncado: ~a" path))
      (when (>= div #x8000) (error "time division SMPTE não suportado: ~a" path))
      (let ((ppq div)
            (tempos '())                  ; (tick . microsseg/beat)
            (raw '()))                    ; (list tick tipo pitch)
        (dotimes (_ ntrks)
          (declare (ignore _))
          (unless (string= (%read-ascii s 4) "MTrk")
            (error "chunk inesperado lendo ~a" path))
          (let* ((mlen (%read-u32 s))
                 (fim (and mlen (+ (file-position s) mlen)))
                 (tick 0) (status 0))
            (loop while (and fim (< (file-position s) fim))
                  do (incf tick (%ler-varlen s))
                     (let ((b1 (%read-u8 s)))
                       (unless b1 (return))
                       (cond
                         ;; meta evento
                         ((= b1 #xFF)
                          (let ((mtype (%read-u8 s))
                                (mlen2 (%ler-varlen s)))
                            (cond
                              ((= mtype #x51)  ; set tempo (3 bytes)
                               (let ((us (logior (ash (%read-u8 s) 16)
                                                 (ash (%read-u8 s) 8)
                                                 (%read-u8 s))))
                                 (push (cons tick us) tempos))
                               (dotimes (_j (- mlen2 3)) (declare (ignore _j)) (%read-u8 s)))
                              (t (dotimes (_j mlen2) (declare (ignore _j)) (%read-u8 s))))))
                         ;; sysex
                         ((or (= b1 #xF0) (= b1 #xF7))
                          (let ((mlen2 (%ler-varlen s)))
                            (dotimes (_j mlen2) (declare (ignore _j)) (%read-u8 s))))
                         ;; evento de canal com status
                         ((>= b1 #x80)
                          (setf status b1)
                          (let ((type (logand b1 #xF0)))
                            (case type
                              ((#x80 #x90)
                               (let ((p (%read-u8 s)) (v (%read-u8 s)))
                                 (cond
                                   ((and (= type #x90) v (plusp v))
                                    (push (list tick :on p) raw))
                                   (t (push (list tick :off p) raw)))))
                              (#xE0 (%read-u8 s) (%read-u8 s))
                              ((#xC0 #xD0) (%read-u8 s))
                              (t (%read-u8 s) (%read-u8 s)))))
                         ;; data byte: running status
                         ((plusp status)
                          (let ((type (logand status #xF0)))
                            (case type
                              ((#x80 #x90)
                               (let ((p b1) (v (%read-u8 s)))
                                 (cond
                                   ((and (= type #x90) v (plusp v))
                                    (push (list tick :on p) raw))
                                   (t (push (list tick :off p) raw)))))
                              (#xE0 (%read-u8 s))
                              ((#xC0 #xD0) nil)
                              (t (%read-u8 s))))))))))
        ;; conversão tick → segundos (tempo por quarto em µs)
        (let* ((tempos (sort tempos #'< :key #'car))
               (spq-por-tick
                 (lambda (tick)
                   "Segundos do TICK dado os eventos de tempo (µs/beat por PPQ)."
                   (let ((sec 0.0) (cur .5) (prev 0))
                     (dolist (seg tempos)
                       (let ((seg-tick (car seg)))
                         (when (> seg-tick tick) (return))
                         (incf sec (* (- seg-tick prev) cur (/ 1.0 ppq)))
                         (setf cur (/ (cdr seg) 1e6) prev seg-tick)))
                     (+ sec (* (- tick prev) cur (/ 1.0 ppq))))))
               (ons (make-hash-table))
               (notas '()))
          (dolist (ev (sort raw #'< :key #'car))
            (let ((tick (first ev)) (tipo (second ev)) (p (third ev)))
              (if (eq tipo :on)
                  (setf (gethash p ons) tick)
                  (let ((on-tick (gethash p ons)))
                    (when on-tick
                      (push (make-nota :onset (funcall spq-por-tick on-tick)
                                       :offset (funcall spq-por-tick tick)
                                       :pitch p)
                            notas)
                      (remhash p ons))))))
          (let* ((notas (sort notas #'< :key #'nota-onset))
                 (bpm (if tempos (/ 60000000.0 (cdar tempos)) 120.0))
                 (duracao (if notas (nota-offset (car (last notas))) 0.0)))
            (make-melodia :bpm (float bpm) :duracao (float duracao)
                          :notas notas)))))))

;;; ---------------------------------------------------------------------------
;;; Render MIDI → WAV (FluidSynth)
;;; ---------------------------------------------------------------------------

(defun render-midi (mid out &key (gain 0.8) (rate 48000) (soundfont nil) (lufs -14.0))
  "Renderiza o MIDI em OUT (.wav 48k/24-bit) via FluidSynth + SoundFont.
   Com LUFS, aplica loudnorm para nivelar/ouvir melhor (NIL desliga)."
  (ensure-out-dir out)
  (let ((sf (or soundfont *soundfont*)))
    (unless (probe-file sf) (error "soundfont não encontrado: ~a" sf))
    (let ((tmp (merge-pathnames "caine-midi-render.wav"
                                (uiop:pathname-directory-pathname out))))
      (multiple-value-bind (o e code)
          (run-cmd (list "fluidsynth" "-ni" "-q"
                         "-F" (namestring tmp)
                         "-T" "wav" "-O" "s16"
                         "-r" (princ-to-string rate)
                         "-g" (princ-to-string gain)
                         sf (namestring mid)))
        (declare (ignore o))
        (unless (zerop code)
          (error "FluidSynth falhou (exit ~a): ~a" code e)))
      (if lufs
          (multiple-value-bind (o e code)
              (run-cmd (list (ffmpeg-bin) "-y" "-hide_banner" "-loglevel" "error"
                             "-i" (namestring tmp)
                             "-af" (format nil "loudnorm=I=~a:TP=-1.5:LRA=11" lufs)
                             "-ar" (princ-to-string rate)
                             "-c:a" "pcm_s24le" (namestring out)))
            (declare (ignore o))
            (unless (zerop code)
              (error "normalização falhou (exit ~a): ~a" code e)))
          (to-wav tmp out :rate rate :channels 2))
      (ignore-errors (delete-file tmp))
      out)))

;;; ---------------------------------------------------------------------------
;;; SVS zero-shot (seed-vc, modo canto) — melodia → voz
;;; ---------------------------------------------------------------------------

(defun cantar-seedvc (fonte voz outdir
                      &key (steps 30) (semi 0) (cfg 0.7) (auto-f0-adjust nil))
  "Gera canto a partir de FONTE (melodia/vocal) no timbre de VOZ.
   seed-vc zero-shot, condicionado ao F0 (preserva a melodia).
   Retorna (values outdir code)."
  (let ((tool (obter-ferramenta "seed-vc")))
    (unless (ferramenta-pronta-p tool)
      (error "seed-vc não instalado. Rode: caine-voice install seed-vc"))
    (ensure-directories-exist (merge-pathnames "keep" outdir))
    (multiple-value-bind (o e code)
        (run-cmd (list (venv-python tool) "inference.py"
                       "--source" (namestring fonte)
                       "--target" (namestring voz)
                       "--output" (namestring outdir)
                       "--diffusion-steps" (princ-to-string steps)
                       "--inference-cfg-rate" (princ-to-string cfg)
                       "--f0-condition" "True"
                       "--auto-f0-adjust" (if auto-f0-adjust "True" "False")
                       "--semi-tone-shift" (princ-to-string semi)
                       "--fp16" "False")
                 :directory (namestring (ferramenta-dir tool))
                 :capture nil)
      (declare (ignore o e))
      (values outdir code))))

;;; ---------------------------------------------------------------------------
;;; Mock de melodia / MIDI (para testes e alinhamento offline sem Python)
;;; ---------------------------------------------------------------------------

(defun gerar-melodia-mock (&key (bpm 120) (num-notas 16))
  "Gera uma estrutura MELODIA em Lisp puro para testes e alinhamento."
  (let* ((pitches '(60 62 64 65 67 69 71 72))
         (n-pitches (length pitches))
         (dur-passo 0.5)
         (notas '())
         (tempo-atual 0.0))
    (dotimes (i num-notas)
      (let* ((p (nth (mod i n-pitches) pitches))
             (onset tempo-atual)
             (offset (+ tempo-atual (* dur-passo 0.9))))
        (push (make-nota
               :onset (float onset 1.0)
               :offset (float offset 1.0)
               :pitch p
               :velocity 85)
              notas)
        (incf tempo-atual dur-passo)))
    (make-melodia
     :bpm bpm
     :duracao (float tempo-atual 1.0)
     :programa 54
     :notas (nreverse notas))))

(defun escrever-midi-mock (caminho &key (bpm 120) (num-notas 16))
  "Salva um arquivo MIDI mock em CAMINHO."
  (ensure-directories-exist caminho)
  (escrever-smf (gerar-melodia-mock :bpm bpm :num-notas num-notas) caminho)
  caminho)
