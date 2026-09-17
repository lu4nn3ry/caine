;;;; ============================================================================
;;;; pipeline.lisp — Pipeline para criar música a partir dos áudios
;;;; ============================================================================
;;;; Junta as tarefas num fluxo único:
;;;;
;;;;   criar-musica   vocal (arquivo ou TTS)  +  instrumental  →  master
;;;;   fazer-cover    separa vocal → converte timbre → remixa  →  master
;;;;   cantar-melodia melodia (áudio) → MIDI → render → voz → master
;;;; ============================================================================

(in-package :caine.voice)

(defun slug (path)
  "Nome base de um pathname, sem extensão."
  (or (pathname-name path) "audio"))

(defun newest-wav (dir)
  "WAV mais recente em DIR (não recursivo)."
  (let ((wavs (remove-if-not (lambda (p) (string-equal (pathname-type p) "wav"))
                             (directory (merge-pathnames "*.wav" dir)))))
    (first (sort wavs #'> :key #'file-write-date))))

(defun criar-musica (instrumental out
                     &key vocal voice-ref texto lufs vocal-db inst-db)
  "Produz uma faixa combinando um vocal com um instrumental.
   - VOCAL: arquivo de vocal pronto; ou
   - VOICE-REF + TEXTO: gera o vocal com GPT-SoVITS (clona VOICE-REF).
   Se INSTRUMENTAL for NIL, apenas masteriza o vocal.
   Retorna o caminho de OUT."
  (ensure-out-dir out)
  (let ((vocal-file
         (cond
           (vocal vocal)
           ((and voice-ref texto)
            (let ((tmp (merge-pathnames "vocal-tts.wav"
                                        (uiop:pathname-directory-pathname out))))
              (tts-gpt-sovits texto voice-ref tmp :server-p t)))
           (t (error "forneça :vocal ou :voice-ref + :texto")))))
    (if instrumental
        (progn
          (println "-- mixando vocal + instrumental → ~a" (namestring out))
          (mix-audio vocal-file instrumental out
                     :vocal-db (or vocal-db 0.0)
                     :inst-db (or inst-db -3.0)
                     :lufs (or lufs -14.0))
          out)
        (progn
          (println "-- masterizando vocal → ~a" (namestring out))
          (master-audio vocal-file out :lufs (or lufs -14.0))
          out))))

(defun fazer-cover (musica voz-alvo out
                    &key (model "htdemucs") (diffusion-steps 30)
                      (lufs -14.0) (workdir nil))
  "Cria um cover de MUSICA com o timbre de VOZ-ALVO:
   1) separa vocal/instrumental (Demucs);
   2) converte a voz para VOZ-ALVO (seed-vc, preservando melodia/letra);
   3) remixa e masteriza em OUT.
   Retorna o caminho de OUT."
  (ensure-out-dir out)
  (let* ((work (or workdir
                   (merge-pathnames "caine-voice-cover/"
                                    (uiop:pathname-directory-pathname out))))
         (stems-dir (merge-pathnames "stems/" work))
         (base (slug musica)))
    (println "== 1/3 separando stems de ~a" (namestring musica))
    (let ((code (stems-demucs musica stems-dir :model model :two-stems "vocals")))
      (unless (zerop code) (error "Demucs falhou (exit ~a)" code)))
    (let* ((track-dir (merge-pathnames (format nil "~a/~a/" model base) stems-dir))
           (vocal (merge-pathnames "vocals.wav" track-dir))
           (instrumental (merge-pathnames "no_vocals.wav" track-dir))
           (conv-dir (merge-pathnames "converted/" work)))
      (unless (probe-file vocal)
        (error "vocal não encontrado em ~a" (namestring vocal)))
      (println "== 2/3 convertendo voz para ~a" (namestring voz-alvo))
      (let ((code (convert-seedvc vocal voz-alvo conv-dir
                                  :diffusion-steps diffusion-steps
                                  :convert-style t)))
        (unless (zerop code) (error "seed-vc falhou (exit ~a)" code)))
      (let ((vocal-conv (newest-wav conv-dir)))
        (unless vocal-conv (error "saída do seed-vc não encontrada em ~a"
                                  (namestring conv-dir)))
        (println "== 3/3 remixando e masterizando → ~a" (namestring out))
        (mix-audio vocal-conv instrumental out :lufs lufs)
        out))))

(defun cantar-melodia (audio out
                       &key voz (engine :poly) (programa 54) (steps 30) (semi 0)
                         (lufs -14.0) (gain 0.8) (workdir nil)
                         (afinar nil))
  "Pega a melodia de AUDIO, transcreve para MIDI, renderiza e — se VOZ —
   canta no timbre de VOZ (seed-vc, preservando a melodia). Masteriza em OUT.
   ENGINE :poly (Basic Pitch, AMT — padrão) ou :mono (pyin, linha única).
   AFINAR quantiza à escala do tom antes do render (:midi/:t) e — com :audio —
   corrige também o F0 por nota no WAV final (segunda passada, p/ vocal).
   Retorna o caminho de OUT."
  (ensure-out-dir out)
  (let* ((work (or workdir
                   (merge-pathnames "caine-melodia/"
                                    (uiop:pathname-directory-pathname out))))
         (notes (merge-pathnames "melodia.notes" work))
         (mid (merge-pathnames "melodia.mid" work))
         (inst (merge-pathnames "melodia.wav" work)))
    (if (eq engine :mono)
        (progn
          (println "== 1/4 transcrevendo melodia (mono/pyin) de ~a" (namestring audio))
          (transcrever audio notes)
          (println "== 2/4 escrevendo MIDI (programa ~a)" programa)
          (setf mid (notas->midi notes mid :programa programa)))
        (progn
          (println "== 1/4 transcrevendo (poly/Basic Pitch) de ~a" (namestring audio))
          (setf mid (transcrever-poly audio work))))
    (when afinar
      (let ((mid-afe (merge-pathnames "melodia-afinado.mid" work)))
        (println "== 2/4 quantizando MIDI à escala do tom")
        (afinar-midi mid mid-afe :max-shift 2)
        (setf mid mid-afe)))
    (println "== 3/4 renderizando melodia (FluidSynth)")
    (render-midi mid inst :gain gain :lufs lufs)
    (let ((final
            (if voz
                (progn
                  (println "== 4/4 cantando no timbre de ~a" (namestring voz))
                  (let ((conv (merge-pathnames "cantado/" work)))
                    (multiple-value-bind (dir code)
                        (cantar-seedvc inst voz conv :steps steps :semi semi)
                      (unless (zerop code) (error "seed-vc falhou (exit ~a)" code))
                      (let ((vocal (newest-wav dir)))
                        (unless vocal
                          (error "saída do seed-vc não encontrada em ~a" (namestring dir)))
                        (master-audio vocal out :lufs lufs)))))
                (progn
                  (println "== 4/4 masterizando melodia → ~a" (namestring out))
                  (master-audio inst out :lufs lufs)))))
      (if (eq afinar :audio)
          (progn
            (println "-- passada de afinação no WAV final (F0 por nota)")
            (let ((tmp (merge-pathnames "melodia-tuned.wav" work)))
              (afinar-audio final tmp mid :max-shift 1.0)
              (uiop:copy-file tmp final :if-exists :supersede)
              (ignore-errors (delete-file tmp)))))
      final)))
