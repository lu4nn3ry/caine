;;;; ============================================================================
;;;; package.lisp — Pacote do caine-voice
;;;; ============================================================================

(in-package :cl-user)

(defpackage :caine.voice
  (:use :cl)
  (:export
   ;; entry point
   #:main
   ;; util
   #:voice-tools-home
   #:run-cmd
   #:println
   ;; ferramentas
   #:ferramenta
   #:ferramenta-id
   #:ferramenta-nome
   #:ferramenta-dir
   #:ferramenta-tipo
   #:ferramenta-licenca
   #:ferramenta-descricao
   #:ferramentas-disponiveis
   #:obter-ferramenta
   #:ferramenta-pronta-p
   #:status-ferramenta
   #:instalar-ferramenta
   ;; áudio
   #:ffprobe-duration
   #:mix-audio
   #:master-audio
   #:to-wav
   ;; tarefas de voz
   #:stems-demucs
   #:convert-seedvc
   #:convert-applio
   #:tts-gpt-sovits
   ;; midi / transcrição / svs
   #:midi-home
   #:midi-pronto-p
   #:midi-poly-pronto-p
   #:instalar-midi
   #:instalar-midi-poly
   #:transcrever-poly
   #:newest-midi
   #:uv-bin
   #:basic-pitch-bin
   #:nota
   #:nota-onset
   #:nota-offset
   #:nota-pitch
   #:nota-velocity
   #:melodia
   #:melodia-bpm
   #:melodia-duracao
   #:melodia-programa
   #:melodia-notas
   #:transcrever
   #:ler-melodia
   #:escrever-smf
   #:notas->midi
   #:render-midi
   #:cantar-seedvc
   ;; pipeline
   #:criar-musica
   #:fazer-cover
   #:cantar-melodia))
