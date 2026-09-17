;;;; ============================================================================
;;;; cli.lisp — Interface de linha de comando do caine-voice
;;;; ============================================================================

(in-package :caine.voice)

(defparameter *usage*
  "caine-voice — ferramentas de voz natural + pipeline de música do Caine

Ferramentas:
  caine-voice list                          lista as ferramentas e o status
  caine-voice doctor                        checa ambiente (python/ffmpeg/venvs)
  caine-voice install <id>                  cria venv e instala dependências

Tarefas:
  caine-voice stems <audio> [outdir] [--two-stems vocals] [--model htdemucs]
  caine-voice convert --source <s> --target <voz> --out <dir> [--tool seed-vc]
  caine-voice tts --text \"...\" --ref <voz> --out <f.wav> [--prompt-text ..] [--lang pt] [--server]
  caine-voice mix --vocal <f> --inst <f> --out <f> [--lufs -14] [--vocal-db 0] [--inst-db -3]
  caine-voice master --in <f> --out <f> [--lufs -14]

Melodia / MIDI / SVS (CPU):
  caine-voice transcribe --in <audio> --out <f.notes|dir> [--engine poly|mono]
                                                            audio → notas/MIDI
  caine-voice midi --in <audio> --out <f.wav> [--engine poly|mono] [--program 54] [--tune]
                                                            melodia → MIDI → WAV (com loudnorm)
  caine-voice sing --melody <audio> --voice <voz> --out <f.wav> [--engine poly] [--steps 30] [--semi 0]
                                                            canta a melodia (seed-vc)
  caine-voice melody --in <audio> --out <f.wav> [--voice <voz>] [--engine poly] [--tune|-tune-audio]
                                                            pipeline completo melodia→voz

  --engine poly (padrão) = Basic Pitch (polifônico, AMT) · mono = pyin (linha única)
  --tune (MIDI) quantiza à escala do tom detectado antes do render
  --tune-audio igual a --tune e corrige também o F0 por nota no WAV final

Afinação (pitch correction):
  caine-voice tune --in <f.mid> --out <f.mid> [--key A] [--mode maj|min|auto] [--max-shift 2] [--keep-bends]
  caine-voice tune --in <f.wav> --mid <f.mid> --out <f.wav> [--max-shift 1.0]
                            MIDI: detecta tom (K-S + cobertura) e quantiza à escala
                            áudio: corrige F0 por nota no WAV (pyin + pitch-shift)

Pipelines:
  caine-voice make  --inst <f> --out <f> (--vocal <f> | --voice-ref <voz> --text \"...\")
  caine-voice cover --in <f> --voice <voz> --out <f> [--steps 30] [--lufs -14]

Env: CAINE_VOICE_HOME (padrão ~/voice-tools/) · CAINE_SOUNDFONT")

(defun has-flag (args name) (member name args :test #'string=))

(defun flag-value (args name &optional default)
  (let ((pos (position name args :test #'string=)))
    (if (and pos (< (1+ pos) (length args)))
        (nth (1+ pos) args)
        default)))

;;; ---------------------------------------------------------------------------
;;; Comandos de status
;;; ---------------------------------------------------------------------------

(defun cmd-list ()
  (println "Ferramentas em ~a" (namestring (voice-tools-home)))
  (dolist (tool (ferramentas-disponiveis))
    (let ((st (status-ferramenta tool)))
      (println "  ~10@a ~10@a ~12@a ~a"
               (getf st :id)
               (getf st :tipo)
               (if (getf st :pronta) "PRONTA"
                   (if (getf st :existe) "SEM VENV" "AUSENTE"))
               (getf st :nome))))
  0)

(defun check-exe (name)
  (multiple-value-bind (out err code) (run-cmd (list "sh" "-c" (format nil "command -v ~a" name)))
    (declare (ignore err))
    (let ((ok (and (zerop code)
                   (plusp (length (string-trim '(#\Space #\Newline) out))))))
      (println "  [~a] ~a" (if ok "ok" "FALTA") name)
      ok)))

(defun cmd-doctor ()
  (println "Ambiente:")
  (check-exe "python3")
  (check-exe "ffmpeg")
  (check-exe "ffprobe")
  (check-exe "fluidsynth")
  (check-exe "curl")
  (println "VOICE_TOOLS_HOME: ~a (~a)"
           (namestring (voice-tools-home))
           (if (probe-file (voice-tools-home)) "existe" "AUSENTE"))
  (println "MIDI mono (pyin): ~a" (if (midi-pronto-p) "pronto" "não (install midi)"))
  (println "MIDI poly (Basic Pitch): ~a" (if (midi-poly-pronto-p) "pronto" "não (install midi)"))
  (println "SoundFont: ~a (~a)" *soundfont*
           (if (probe-file *soundfont*) "ok" "AUSENTE"))
  (println "Ferramentas:")
  (dolist (tool (ferramentas-disponiveis))
    (let ((st (status-ferramenta tool)))
      (println "  [~a] ~10@a venv=~a"
               (if (getf st :pronta) "ok" "--")
               (getf st :id)
               (if (getf st :venv) "sim" "não"))))
  0)

(defun cmd-config ()
  (println "voice_tools_home = ~a" (namestring (voice-tools-home)))
  (println "python3          = ~a" (or (uiop:getenv "PYTHON") "python3"))
  (println "ffmpeg           = ~a" (or (uiop:getenv "FFMPEG") "ffmpeg"))
  0)

;;; ---------------------------------------------------------------------------
;;; Comandos de tarefa
;;; ---------------------------------------------------------------------------

(defun cmd-install (args)
  (let ((id (first args)))
    (unless id (println "Uso: caine-voice install <id|midi>") (return-from cmd-install 1))
    (if (string= id "midi")
        (progn (instalar-midi) 0)
        (progn (instalar-ferramenta id) 0))))

(defun cmd-stems (args)
  (let ((input (first args))
        (outdir (second (remove "--two-stems" (remove "--model" args
                                                      :test #'string=)))))
    (declare (ignore outdir))
    (unless input (println "Uso: caine-voice stems <audio> [outdir]") (return-from cmd-stems 1))
    (let* ((out (or (flag-value args "--out")
                    (merge-pathnames "stems/" (uiop:pathname-directory-pathname input))))
           (model (flag-value args "--model" "htdemucs"))
           (two (flag-value args "--two-stems" nil)))
      (multiple-value-bind (dir code)
          (stems-demucs input out :model model :two-stems two)
        (println "stems em ~a (exit ~a)" (namestring dir) code)
        (if (zerop code) 0 1)))))

(defun cmd-convert (args)
  (let ((source (flag-value args "--source"))
        (target (flag-value args "--target"))
        (out (flag-value args "--out"))
        (tool (flag-value args "--tool" "seed-vc"))
        (steps (flag-value args "--steps" "30")))
    (unless (and source target out)
      (println "Uso: caine-voice convert --source <s> --target <voz> --out <dir>")
      (return-from cmd-convert 1))
    (cond
      ((string= tool "seed-vc")
       (multiple-value-bind (dir code)
           (convert-seedvc source target out :diffusion-steps (parse-integer steps))
         (println "saída em ~a (exit ~a)" (namestring dir) code)
         (if (zerop code) 0 1)))
      ((string= tool "applio")
       (println "Applio é interface gráfica; abrindo...")
       (convert-applio out))
      (t (println "ferramenta não suportada: ~a" tool) 1))))

(defun cmd-tts (args)
  (let ((text (flag-value args "--text"))
        (ref (flag-value args "--ref"))
        (out (flag-value args "--out"))
        (prompt (flag-value args "--prompt-text" ""))
        (lang (flag-value args "--lang" "pt")))
    (unless (and text ref out)
      (println "Uso: caine-voice tts --text \"...\" --ref <voz> --out <f.wav>")
      (return-from cmd-tts 1))
    (tts-gpt-sovits text ref out
                    :prompt-text prompt :text-lang lang :prompt-lang lang
                    :server-p (has-flag args "--server"))
    0))

(defun cmd-mix (args)
  (let ((vocal (flag-value args "--vocal"))
        (inst (flag-value args "--inst"))
        (out (flag-value args "--out"))
        (lufs (flag-value args "--lufs" "-14"))
        (vdb (flag-value args "--vocal-db" "0"))
        (idb (flag-value args "--inst-db" "-3")))
    (unless (and vocal inst out)
      (println "Uso: caine-voice mix --vocal <f> --inst <f> --out <f>")
      (return-from cmd-mix 1))
    (multiple-value-bind (_ code _e) (mix-audio vocal inst out
                                                :lufs (read-from-string lufs)
                                                :vocal-db (read-from-string vdb)
                                                :inst-db (read-from-string idb))
      (declare (ignore _ _e))
      (println "mix salvo em ~a (exit ~a)" out code)
      (if (zerop code) 0 1))))

(defun cmd-master (args)
  (let ((in (flag-value args "--in"))
        (out (flag-value args "--out"))
        (lufs (flag-value args "--lufs" "-14")))
    (unless (and in out)
      (println "Uso: caine-voice master --in <f> --out <f>") (return-from cmd-master 1))
    (multiple-value-bind (_ code _e) (master-audio in out :lufs (read-from-string lufs))
      (declare (ignore _ _e))
      (println "master salvo em ~a (exit ~a)" out code)
      (if (zerop code) 0 1))))

(defun cmd-make (args)
  (let ((inst (flag-value args "--inst"))
        (vocal (flag-value args "--vocal"))
        (ref (flag-value args "--voice-ref"))
        (text (flag-value args "--text"))
        (out (flag-value args "--out"))
        (lufs (flag-value args "--lufs" "-14")))
    (unless out
      (println "Uso: caine-voice make --inst <f> --out <f> (--vocal <f> | --voice-ref <voz> --text \"...\")")
      (return-from cmd-make 1))
    (handler-case
        (progn
          (criar-musica inst out :vocal vocal :voice-ref ref :texto text
                        :lufs (read-from-string lufs))
          (println "faixa pronta: ~a" out)
          0)
      (error (e) (println "erro: ~a" e) 1))))

(defun cmd-cover (args)
  (let ((in (flag-value args "--in"))
        (voice (flag-value args "--voice"))
        (out (flag-value args "--out"))
        (steps (flag-value args "--steps" "30"))
        (lufs (flag-value args "--lufs" "-14")))
    (unless (and in voice out)
      (println "Uso: caine-voice cover --in <f> --voice <voz> --out <f>")
      (return-from cmd-cover 1))
    (handler-case
        (progn
          (fazer-cover in voice out
                       :diffusion-steps (parse-integer steps)
                       :lufs (read-from-string lufs))
          (println "cover pronto: ~a" out)
          0)
      (error (e) (println "erro: ~a" e) 1))))

;;; ---------------------------------------------------------------------------
;;; Comandos de melodia / MIDI / SVS
;;; ---------------------------------------------------------------------------

(defun cmd-transcribe (args)
  (let ((in (flag-value args "--in"))
        (out (flag-value args "--out"))
        (engine (flag-value args "--engine" "poly")))
    (unless (and in out)
      (println "Uso: caine-voice transcribe --in <audio> --out <f.notes|dir> [--engine poly|mono]")
      (return-from cmd-transcribe 1))
    (handler-case
        (if (string= engine "poly")
            (let ((mid (transcrever-poly in out)))
              (println "MIDI salvo em ~a" (namestring mid)) 0)
            (progn (transcrever in out)
                   (println "notas salvas em ~a" out) 0))
      (error (e) (println "erro: ~a" e) 1))))

(defun cmd-midi (args)
  (let ((in (flag-value args "--in"))
        (out (flag-value args "--out"))
        (engine (flag-value args "--engine" "poly"))
        (program (flag-value args "--program" "54"))
        (gain (flag-value args "--gain" "0.8"))
        (lufs (flag-value args "--lufs" "-14"))
        (work (flag-value args "--work")))
    (unless (and in out)
      (println "Uso: caine-voice midi --in <audio> --out <f.wav> [--engine poly|mono]")
      (return-from cmd-midi 1))
    (handler-case
        (let* ((dir (uiop:ensure-directory-pathname
                     (or work (merge-pathnames "caine-midi/"
                                               (uiop:pathname-directory-pathname out)))))
               (mid (if (string= engine "poly")
                        (progn (println "== transcrevendo (poly) ~a" in)
                               (transcrever-poly in dir))
                        (let ((notes (merge-pathnames "melodia.notes" dir))
                              (m (merge-pathnames "melodia.mid" dir)))
                          (println "== transcrevendo (mono) ~a" in)
                          (transcrever in notes)
                          (println "== escrevendo MIDI (programa ~a)" program)
                          (notas->midi notes m :programa (parse-integer program))
                          m))))
          (when (has-flag args "--tune")
            (let ((mid-afe (merge-pathnames "melodia-afinado.mid" dir)))
              (println "== quantizando à escala do tom")
              (setf mid (afinar-midi mid mid-afe :max-shift 2))))
          (println "== renderizando → ~a" out)
          (render-midi mid out :gain (read-from-string gain)
                             :lufs (read-from-string lufs))
          (println "melodia pronta: ~a" out)
          0)
      (error (e) (println "erro: ~a" e) 1))))

(defun parse-engine (args)
  (if (string= (flag-value args "--engine" "poly") "mono") :mono :poly))

(defun parse-afinar (args)
  "--tune-audio (:audio) igual a --tune (:midi) + passada no WAV final."
  (cond ((has-flag args "--tune-audio") :audio)
        ((has-flag args "--tune") :midi)
        (t nil)))

(defun cmd-sing (args)
  (let ((melody (flag-value args "--melody"))
        (voice (flag-value args "--voice"))
        (out (flag-value args "--out"))
        (steps (flag-value args "--steps" "30"))
        (semi (flag-value args "--semi" "0"))
        (program (flag-value args "--program" "54"))
        (lufs (flag-value args "--lufs" "-14")))
    (unless (and melody voice out)
      (println "Uso: caine-voice sing --melody <audio> --voice <voz> --out <f.wav>")
      (return-from cmd-sing 1))
    (handler-case
        (progn
          (cantar-melodia melody out :voz voice
                          :engine (parse-engine args)
                          :programa (parse-integer program)
                          :steps (parse-integer steps)
                          :semi (parse-integer semi)
                          :lufs (read-from-string lufs)
                          :afinar (parse-afinar args))
          (println "vocal pronto: ~a" out)
          0)
      (error (e) (println "erro: ~a" e) 1))))

(defun cmd-melody (args)
  (let ((in (flag-value args "--in"))
        (out (flag-value args "--out"))
        (voice (flag-value args "--voice"))
        (program (flag-value args "--program" "54"))
        (steps (flag-value args "--steps" "30"))
        (semi (flag-value args "--semi" "0"))
        (lufs (flag-value args "--lufs" "-14")))
    (unless (and in out)
      (println "Uso: caine-voice melody --in <audio> --out <f.wav> [--voice <voz>]")
      (return-from cmd-melody 1))
    (handler-case
        (progn
          (cantar-melodia in out :voz voice
                          :engine (parse-engine args)
                          :programa (parse-integer program)
                          :steps (parse-integer steps)
                          :semi (parse-integer semi)
                          :lufs (read-from-string lufs)
                          :afinar (parse-afinar args))
          (println "faixa pronta: ~a" out)
          0)
      (error (e) (println "erro: ~a" e) 1))))

(defun cmd-tune (args)
  "Afinação: MIDI (tom + escala) ou áudio (F0 por nota via --mid)."
  (let ((in (flag-value args "--in"))
        (mid (flag-value args "--mid"))
        (out (flag-value args "--out"))
        (key (flag-value args "--key"))
        (mode (flag-value args "--mode"))
        (max (flag-value args "--max-shift" "2")))
    (unless (and in out)
      (println "Uso: caine-voice tune --in <mid|wav> --out <f> [--mid <f.mid>] [--key A] [--mode maj|min|auto]")
      (return-from cmd-tune 1))
    (handler-case
        (if mid
            (progn
              (println "== afinação de áudio (F0 por nota) ~a" in)
              (afinar-audio in out mid
                            :max-shift (read-from-string max))
              (println "áudio afinado em ~a" out)
              0)
            (progn
              (println "== afinação de MIDI (tom + escala) ~a" in)
              (afinar-midi in out :key key :mode mode
                           :max-shift (or (parse-integer max :junk-allowed t) 2)
                           :keep-bends (has-flag args "--keep-bends"))
              (println "MIDI afinado em ~a" out)
              0))
      (error (e) (println "erro: ~a" e) 1))))

;;; ---------------------------------------------------------------------------
;;; Dispatch
;;; ---------------------------------------------------------------------------

(defun main (&optional argv)
  (let ((args (or argv (uiop:command-line-arguments))))
    (handler-case
        (let ((cmd (first args))
              (rest (rest args)))
          (cond
            ((or (null cmd) (string= cmd "--help") (string= cmd "-h"))
             (println "~a" *usage*) 0)
            ((or (string= cmd "--version") (string= cmd "-v"))
             (println "caine-voice 0.1.0") 0)
            ((member cmd '("list" "tools") :test #'string=) (cmd-list))
            ((string= cmd "doctor") (cmd-doctor))
            ((string= cmd "config") (cmd-config))
            ((string= cmd "install") (cmd-install rest))
            ((string= cmd "stems") (cmd-stems rest))
            ((string= cmd "convert") (cmd-convert rest))
            ((string= cmd "tts") (cmd-tts rest))
            ((string= cmd "mix") (cmd-mix rest))
            ((string= cmd "master") (cmd-master rest))
            ((string= cmd "transcribe") (cmd-transcribe rest))
            ((string= cmd "midi") (cmd-midi rest))
            ((string= cmd "sing") (cmd-sing rest))
            ((string= cmd "melody") (cmd-melody rest))
            ((string= cmd "tune") (cmd-tune rest))
            ((string= cmd "make") (cmd-make rest))
            ((string= cmd "cover") (cmd-cover rest))
            (t (println "Comando desconhecido: ~a" cmd)
               (println "~a" *usage*) 1)))
      (error (e)
        (format *error-output* "erro: ~a~%" e)
        1))))
