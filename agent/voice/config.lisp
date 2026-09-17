;;;; ============================================================================
;;;; config.lisp — Registro e localização das ferramentas de voz
;;;; ============================================================================
;;;; As ferramentas ficam em VOICE-TOOLS-HOME:
;;;;   env CAINE_VOICE_HOME  ou  ~/voice-tools/
;;;;
;;;; Cada ferramenta tem um venv isolado em <dir>/.venv, criado por
;;;; `caine-voice install <id>`.
;;;; ============================================================================

(in-package :caine.voice)

(defun println (&rest args)
  (apply #'format t args)
  (terpri)
  (finish-output))

(defstruct (ferramenta (:constructor %make-ferramenta))
  (id "" :type string)
  (nome "" :type string)
  (dir-name "" :type string)
  (entry "" :type string)
  (tipo :outro)
  (licenca "" :type string)
  (requirements "requirements.txt")
  (pip nil)
  (descricao "" :type string))

(defun voice-tools-home ()
  "Diretório raiz das ferramentas de voz."
  (uiop:ensure-directory-pathname
   (or (uiop:getenv "CAINE_VOICE_HOME")
       (namestring (merge-pathnames "voice-tools/" (user-homedir-pathname))))))

(defun ferramentas-disponiveis ()
  "Registro das ferramentas de voz suportadas."
  (list
   (%make-ferramenta
    :id "gpt-sovits" :nome "GPT-SoVITS" :dir-name "GPT-SoVITS"
    :entry "GPT_SoVITS/inference_webui.py" :tipo :tts :licenca "MIT"
    :requirements "requirements.txt"
    :descricao "TTS/clonagem few-shot (5s zero-shot, 1min fine-tune). Síntese cantada via SoVITS.")
   (%make-ferramenta
    :id "seed-vc" :nome "seed-vc" :dir-name "seed-vc"
    :entry "inference_v2.py" :tipo :vc :licenca "GPL-3.0"
    :requirements "requirements.txt"
    :descricao "Conversão de voz zero-shot (fala e canto), 44.1kHz, preserva melodia/letra.")
   (%make-ferramenta
    :id "applio" :nome "Applio" :dir-name "Applio"
    :entry "app.py" :tipo :vc :licenca "MIT"
    :requirements "requirements.txt"
    :descricao "Voice conversion estilo RVC, treino e inferência fáceis.")
   (%make-ferramenta
    :id "diffsinger" :nome "DiffSinger" :dir-name "DiffSinger"
    :entry "bin/diffsinger-utau" :tipo :svs :licenca "Apache-2.0"
    :pip "diffsinger-utau"
    :descricao "Singing Voice Synthesis avançada (OpenVPI / diffsinger-utau headless CLI, CUDA).")
   (%make-ferramenta
    :id "ace-step" :nome "ACE-Step v1.5" :dir-name "ace-step"
    :entry "main.py" :tipo :t2m :licenca "Apache-2.0"
    :requirements "requirements.txt"
    :descricao "Text-to-music foundation model (<4GB VRAM), geração e cover com letra.")
   (%make-ferramenta
    :id "cosyvoice" :nome "CosyVoice2-0.5B" :dir-name "CosyVoice"
    :entry "cosyvoice/cli/cosyvoice.py" :tipo :tts :licenca "Apache-2.0"
    :requirements "requirements.txt"
    :descricao "TTS e clonagem zero-shot multilíngue (<4GB VRAM) para personas.")
   (%make-ferramenta
    :id "openutau" :nome "OpenUtau" :dir-name "OpenUtau"
    :entry "OpenUtau.sln" :tipo :svs :licenca "MIT"
    :requirements ""
    :descricao "Plataforma de síntese cantada (sucessor do UTAU); build .NET.")
   (%make-ferramenta
    :id "demucs" :nome "Demucs" :dir-name "demucs"
    :entry "bin/demucs" :tipo :stems :licenca "MIT"
    :requirements ""
    :pip "demucs"
    :descricao "Separação de stems (vocal/instrumental/bateria/baixo). Instalado via pip.")))

(defun obter-ferramenta (id)
  "Busca uma ferramenta pelo ID."
  (find id (ferramentas-disponiveis) :key #'ferramenta-id :test #'string=))

(defun ferramenta-dir (tool)
  "Caminho absoluto do diretório da ferramenta."
  (merge-pathnames (ferramenta-dir-name tool) (voice-tools-home)))

(defun ferramenta-path (tool &optional rel)
  "Caminho de REL (relativo) dentro da ferramenta."
  (if rel
      (merge-pathnames rel (ferramenta-dir tool))
      (ferramenta-dir tool)))

(defun venv-dir (tool)
  (merge-pathnames ".venv/" (ferramenta-dir tool)))

(defun venv-python (tool)
  "Python do venv da ferramenta (ou python3 do sistema, se não houver venv)."
  (let ((py (merge-pathnames "bin/python" (venv-dir tool))))
    (if (probe-file py) (namestring py) "python3")))

(defun venv-pip (tool)
  (let ((pip (merge-pathnames "bin/pip" (venv-dir tool))))
    (if (probe-file pip) (namestring pip) nil)))

;;; ---------------------------------------------------------------------------
;;; Utilitário de execução de processos
;;; ---------------------------------------------------------------------------

(defun run-cmd (args &key directory (capture t) (verbose nil))
  "Executa ARGS (lista de strings). Retorna (values stdout stderr code).
   Se CAPTURE for NIL, herda os streams do processo."
  (when verbose
    (println "[cmd] ~{~a~^ ~}" args))
  (multiple-value-bind (out err code)
      (uiop:run-program args
                        :directory directory
                        :output (if capture :string t)
                        :error-output :string
                        :ignore-error-status t)
    (values (or out "") (or err "") code)))
