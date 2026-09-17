;;;; ============================================================================
;;;; tools.lisp — Status, instalação e execução das ferramentas de voz
;;;; ============================================================================
;;;; Cada tarefa delega ao executável da ferramenta dentro do seu venv.
;;;; Nada é instalado automaticamente: `caine-voice install <id>` é explícito.
;;;; ============================================================================

(in-package :caine.voice)

;;; ---------------------------------------------------------------------------
;;; Status / instalação
;;; ---------------------------------------------------------------------------

(defun ferramenta-pronta-p (tool)
  "Tá pronta para uso (venv + entrypoint existem)?"
  (let ((dir (ferramenta-dir tool)))
    (and (probe-file dir)
         (probe-file (venv-dir tool))
         (if (ferramenta-pip tool)
             (probe-file (merge-pathnames (ferramenta-entry tool) (venv-dir tool)))
             (probe-file (merge-pathnames (ferramenta-entry tool) dir))))))

(defun status-ferramenta (tool)
  "Retorna um plist com o estado da ferramenta."
  (let ((dir (ferramenta-dir tool)))
    (list :id (ferramenta-id tool)
          :nome (ferramenta-nome tool)
          :tipo (ferramenta-tipo tool)
          :licenca (ferramenta-licenca tool)
          :dir (namestring dir)
          :existe (probe-file dir)
          :venv (probe-file (venv-dir tool))
          :pronta (ferramenta-pronta-p tool))))

(defun instalar-ferramenta (id)
  "Cria o venv e instala as dependências da ferramenta ID.
   Método 1 = venv+pip de pacote; senão, requirements.txt."
  (let* ((tool (obter-ferramenta id))
         (dir (ferramenta-dir tool)))
    (unless tool (error "ferramenta desconhecida: ~a" id))
    (ensure-directories-exist (merge-pathnames "keep" dir))
    (println "== instalando ~a em ~a" (ferramenta-nome tool) (namestring dir))
    (println "-- criando venv")
    (run-cmd (list "python3" "-m" "venv" (namestring (venv-dir tool)))
             :directory (namestring dir) :capture nil)
    (let ((pip (venv-pip tool)))
      (unless pip (error "pip não encontrado no venv de ~a" id))
      (run-cmd (list pip "install" "--upgrade" "pip")
               :directory (namestring dir) :capture nil)
      (if (ferramenta-pip tool)
          (run-cmd (list pip "install" (ferramenta-pip tool))
                   :directory (namestring dir) :capture nil)
          (let ((req (merge-pathnames (ferramenta-requirements tool) dir)))
            (unless (probe-file req)
              (error "requirements.txt não encontrado para ~a" id))
            (run-cmd (list pip "install" "-r" (namestring req))
                     :directory (namestring dir) :capture nil))))
    (println "== pronto: ~a" (if (ferramenta-pronta-p tool) "sim" "não (verifique erros)"))
    (ferramenta-pronta-p tool)))

;;; ---------------------------------------------------------------------------
;;; Tarefa: separação de stems (Demucs)
;;; ---------------------------------------------------------------------------

(defun stems-demucs (input outdir &key (model "htdemucs") (two-stems nil))
  "Separa INPUT em stems dentro de OUTDIR.
   Com TWO-STEMS (ex.: \"vocals\") gera apenas vocal/instrumental.
   Retorna (values outdir code)."
  (let ((tool (obter-ferramenta "demucs")))
    (unless (ferramenta-pronta-p tool)
      (error "Demucs não instalado. Rode: caine-voice install demucs"))
    (ensure-directories-exist (merge-pathnames "keep" outdir))
    (let ((args (append (list (venv-python tool) "-m" "demucs"
                             "-n" model "-o" (namestring outdir))
                        (when two-stems (list "--two-stems" two-stems))
                        (list (namestring input)))))
      (multiple-value-bind (o e code) (run-cmd args :capture nil)
        (declare (ignore o e))
        (values outdir code)))))

;;; ---------------------------------------------------------------------------
;;; Tarefa: conversão de voz (seed-vc / Applio)
;;; ---------------------------------------------------------------------------

(defun convert-seedvc (source target outdir
                       &key (diffusion-steps 30) (convert-style t) (extra nil))
  "Converte a voz de SOURCE para o timbre de TARGET (seed-vc, zero-shot).
   Preserva melodia/letra — ideal para covers/canto. Retorna (values outdir code)."
  (let ((tool (obter-ferramenta "seed-vc")))
    (unless (ferramenta-pronta-p tool)
      (error "seed-vc não instalado. Rode: caine-voice install seed-vc"))
    (ensure-directories-exist (merge-pathnames "keep" outdir))
    (let ((args (append (list (venv-python tool) "inference_v2.py"
                             "--source" (namestring source)
                             "--target" (namestring target)
                             "--output" (namestring outdir)
                             "--diffusion-steps" (princ-to-string diffusion-steps)
                             "--convert-style" (if convert-style "True" "False"))
                        extra)))
      (multiple-value-bind (o e code) (run-cmd args
                                              :directory (namestring (ferramenta-dir tool))
                                              :capture nil)
        (declare (ignore o e))
        (values outdir code)))))

(defun convert-applio (outdir)
  "Abre a interface do Applio (voice conversion / RVC). Bloqueia até fechar.
   OUTDIR vira o diretório de trabalho (modelos/logs)."
  (let ((tool (obter-ferramenta "applio")))
    (unless (probe-file (ferramenta-dir tool))
      (error "Applio não encontrado. Rode: caine-voice install applio"))
    (ensure-directories-exist (merge-pathnames "keep" outdir))
    (run-cmd (list (venv-python tool) "app.py")
             :directory (namestring (ferramenta-dir tool)) :capture nil)
    0))

;;; ---------------------------------------------------------------------------
;;; Tarefa: TTS / clone de voz (GPT-SoVITS, via API local)
;;; ---------------------------------------------------------------------------

(defun http-post-file (url json out)
  "POST JSON em URL via curl, salvando a resposta em OUT."
  (ensure-out-dir out)
  (multiple-value-bind (o e code)
      (run-cmd (list "curl" "-sS" "-X" "POST" url
                     "-H" "Content-Type: application/json"
                     "--data-binary" json
                     "-o" (namestring out)))
    (declare (ignore o))
    (values out code e)))

(defun http-get-code (url)
  "Código HTTP de um GET em URL (0 se falhar)."
  (multiple-value-bind (out err code)
      (run-cmd (list "curl" "-sS" "-o" "/dev/null" "-w" "%{http_code}" url))
    (declare (ignore err))
    (if (zerop code) (parse-integer (string-trim '(#\Space #\Newline) out)
                                    :junk-allowed t)
        0)))

(defun tts-gpt-sovits (text ref-audio out
                       &key (prompt-text "") (text-lang "pt")
                         (prompt-lang "pt") (port 9880)
                         (server-p nil) (timeout 300))
  "Gera fala/canto com GPT-SoVITS a partir de TEXT, clonando REF-AUDIO.
   Se SERVER-P, sobe o servidor api_v2.py, usa e derruba. Retorna OUT.
   Requer modelos treinados/baixados (GPT_SoVITS/pretrained_models)."
  (let* ((tool (obter-ferramenta "gpt-sovits"))
         (dir (ferramenta-dir tool))
         (proc nil))
    (unless (ferramenta-pronta-p tool)
      (error "GPT-SoVITS não instalado. Rode: caine-voice install gpt-sovits"))
    (unwind-protect
         (progn
           (when server-p
             (println "-- subindo servidor GPT-SoVITS na porta ~a" port)
             (setf proc
                   (uiop:launch-program
                    (list (venv-python tool) "api_v2.py"
                          "-a" "127.0.0.1" "-p" (princ-to-string port)
                          "-c" "GPT_SoVITS/configs/tts_infer.yaml")
                    :directory (namestring dir)
                    :output *standard-output* :error-output *standard-output*))
             (loop repeat 60
                   until (plusp (http-get-code
                                 (format nil "http://127.0.0.1:~a/docs" port)))
                   do (sleep 0.5)))
           (let* ((url (format nil "http://127.0.0.1:~a/tts" port))
                  (payload (format nil
                                   "{\"text\":~s,\"text_lang\":~s,\"ref_audio_path\":~s,~
                                     \"prompt_text\":~s,\"prompt_lang\":~s,~
                                     \"text_split_method\":\"cut5\",\"media_type\":\"wav\"}"
                                   text text-lang (namestring ref-audio)
                                   prompt-text prompt-lang)))
             (multiple-value-bind (o code e) (http-post-file url payload out)
               (declare (ignore o))
               (unless (zerop code)
                 (error "falha no POST /tts (exit ~a): ~a" code e))
               (println "-- vocal gerado em ~a" (namestring out))
               out)))
      (when (and proc (uiop:process-alive-p proc))
        (uiop:terminate-process proc)))))
