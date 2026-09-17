;;;; ============================================================================
;;;; audio.lisp — Processamento de áudio via ffmpeg
;;;; ============================================================================
;;;; Helpers de áudio usados pelo pipeline: duração, conversão WAV 48k/24bit,
;;;; mixagem vocal+instrumental e masterização (loudnorm/LUFS).
;;;; ============================================================================

(in-package :caine.voice)

(defun ffmpeg-bin () (or (uiop:getenv "FFMPEG") "ffmpeg"))
(defun ffprobe-bin () (or (uiop:getenv "FFPROBE") "ffprobe"))

(defun ensure-out-dir (path)
  (let ((d (uiop:pathname-directory-pathname path)))
    (when d (ensure-directories-exist d)))
  path)

(defun codec-args (out)
  "Codec de áudio adequado à extensão de OUT."
  (let ((ext (string-downcase (or (pathname-type out) "wav"))))
    (cond
      ((string= ext "wav") (list "-c:a" "pcm_s24le"))
      ((string= ext "flac") (list "-c:a" "flac"))
      ((string= ext "mp3") (list "-c:a" "libmp3lame" "-b:a" "320k"))
      ((string= ext "m4a") (list "-c:a" "aac" "-b:a" "320k"))
      ((string= ext "ogg") (list "-c:a" "libvorbis" "-q:a" "8"))
      (t (list "-c:a" "pcm_s24le")))))

(defun ffprobe-duration (file)
  "Duração de FILE em segundos (float), ou NIL."
  (multiple-value-bind (out err code)
      (run-cmd (list (ffprobe-bin) "-v" "error"
                     "-show_entries" "format=duration"
                     "-of" "default=noprint_wrappers=1:nokey=1"
                     (namestring file)))
    (declare (ignore err))
    (when (zerop code)
      (let ((s (string-trim '(#\Space #\Newline #\Return #\Tab) out)))
        (ignore-errors (read-from-string s))))))

(defun to-wav (in out &key (rate 48000) (channels 2))
  "Converte IN para WAV PCM 24-bit na taxa/canais pedidos."
  (ensure-out-dir out)
  (multiple-value-bind (o e code)
      (run-cmd (list (ffmpeg-bin) "-y" "-i" (namestring in)
                     "-ar" (princ-to-string rate)
                     "-ac" (princ-to-string channels)
                     "-c:a" "pcm_s24le"
                     (namestring out)))
    (declare (ignore o))
    (values out code e)))

(defun master-audio (in out &key (lufs -14.0) (true-peak -1.5) (lra 11))
  "Masteriza IN para OUT aplicando loudnorm (LUFS)."
  (ensure-out-dir out)
  (let ((filter (format nil "loudnorm=I=~a:TP=~a:LRA=~a"
                        lufs true-peak lra)))
    (multiple-value-bind (o e code)
        (run-cmd (append (list (ffmpeg-bin) "-y" "-i" (namestring in)
                              "-af" filter "-ar" "48000")
                         (codec-args out)
                         (list (namestring out))))
      (declare (ignore o))
      (values out code e))))

(defun mix-audio (vocal instrumental out
                  &key (vocal-db 0.0) (inst-db -3.0) (lufs -14.0)
                    (duration "longest"))
  "Mixa VOCAL + INSTRUMENTAL em OUT e masteriza para LUFS.
   VOCAL-DB / INST-DB ajustam o ganho de cada faixa."
  (ensure-out-dir out)
  (let ((filter
         (format nil
                 "[0:a]volume=~adB,aresample=48000[v];~
                  [1:a]volume=~adB,aresample=48000[i];~
                  [v][i]amix=inputs=2:duration=~a:dropout_transition=0:normalize=0[mix];~
                  [mix]loudnorm=I=~a:TP=-1.5:LRA=11[out]"
                 vocal-db inst-db duration lufs)))
    (multiple-value-bind (o e code)
        (run-cmd (append (list (ffmpeg-bin) "-y"
                              "-i" (namestring vocal)
                              "-i" (namestring instrumental)
                              "-filter_complex" filter
                              "-map" "[out]" "-ar" "48000")
                         (codec-args out)
                         (list (namestring out))))
      (declare (ignore o))
      (values out code e))))
