;;;; ============================================================================
;;;; caine-voice.asd — Integração das ferramentas de voz ao Caine
;;;; ============================================================================
;;;; Orquestra as ferramentas locais de voz (GPT-SoVITS, seed-vc, Applio,
;;;; DiffSinger, OpenUtau, Demucs) e o ffmpeg para criar/editar música a partir
;;;; dos áudios do usuário.
;;;;
;;;; Carregar: (asdf:load-system "caine-voice")
;;;; Executar: ./agent/voice/caine-voice --help
;;;; ============================================================================

(asdf:defsystem "caine-voice"
  :description "Ferramentas de voz natural + pipeline de música para o Caine."
  :author "lu4nn3ry"
  :license "GPL-3.0"
  :version "0.1.0"
  :serial t
  :depends-on ()
  :components ((:file "package")
               (:file "config")
               (:file "audio")
               (:file "midi")
               (:file "tools")
               (:file "pipeline")
               (:file "cli"))
  :entry-point "caine.voice:main")
