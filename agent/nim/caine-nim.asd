;;;; ============================================================================
;;;; caine-nim.asd — Sistema ASDF do CLI NVIDIA NIM
;;;; ============================================================================
;;;; CLI para a IA Caine conversar com a API NVIDIA NIM (OpenAI-compatible),
;;;; com tool calling, suporte a API key e persistência de sessões.
;;;;
;;;; Carregar:  (asdf:load-system "caine-nim")
;;;; Executar:  ./agent/nim/caine-nim --help
;;;; ============================================================================

(asdf:defsystem "caine-nim"
  :description "CLI NVIDIA NIM com tool calling, API key e persistência — IA Caine."
  :author "lu4nn3ry"
  :license "MIT"
  :version "0.1.0"
  :serial t
  :depends-on ()
  :components ((:file "package")
               (:file "json")
               (:file "http")
               (:file "config")
               (:file "tools")
               (:file "client")
               (:file "cli"))
  :entry-point "caine.nim:main")
