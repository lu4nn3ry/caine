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
   #:make-nota
   #:nota-onset
   #:nota-offset
   #:nota-pitch
   #:nota-velocity
   #:melodia
   #:make-melodia
   #:melodia-p
   #:melodia-bpm
   #:melodia-duracao
   #:melodia-programa
   #:melodia-notas
   #:transcrever
   #:ler-melodia
   #:escrever-smf
   #:notas->midi
   #:gerar-melodia-mock
   #:escrever-midi-mock
   #:render-midi
   #:cantar-seedvc
   ;; letras / SVS (ADR 005)
   #:lyric-linha
   #:make-lyric-linha
   #:lyric-linha-texto
   #:lyric-linha-silabas
   #:lyric-secao
   #:make-lyric-secao
   #:lyric-secao-tag
   #:lyric-secao-linhas
   #:cancao
   #:make-cancao
   #:cancao-p
   #:cancao-titulo
   #:cancao-tempo
   #:cancao-secoes
   #:ler-smf
   #:limpar-acentos
   #:chave-rima
   #:silabas-de-palavra
   #:contar-silabas-palavra
   #:silabas-de-frase
   #:parse-cancao
   #:ler-cancao
   #:escrever-cancao
   #:analisar-letra
   #:gerar-letra
   #:editar-letra-local
   #:alinhar-letra
   #:alinhamento
   #:alinhamento-p
   #:alinhamento-syllables
   #:alinhamento-notes
   #:alinhamento-durations
   #:alinhamento-onsets
   #:alinhamento-avisos
   #:escrever-align-diffsinger
   #:escrever-align-openutau
   #:fonemizar-palavra
   #:fonemizar-letra
   ;; pipeline
   #:criar-musica
   #:fazer-cover
   #:cantar-melodia
   ;; artistas / personas (ADR 006)
   #:perfil-artista
   #:perfil-artista-p
   #:perfil-artista-id
   #:perfil-artista-nome
   #:perfil-artista-descricao
   #:perfil-artista-system-prompt
   #:perfil-artista-voz
   #:perfil-artista-estilo
   #:perfil-artista-registro
   #:listar-artistas
   #:obter-artista
   #:artista-prompt-letra
   #:gerar-letra-artista))
