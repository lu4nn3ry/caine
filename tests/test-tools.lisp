;;;; ============================================================================
;;;; test-tools.lisp — Testes para as engines e ferramentas de voz (ADR 007)
;;;; ============================================================================

(in-package :caine.test-framework)

(deftest test-ferramentas-adr-007
  "Verifica o registro das novas engines de 2026 segundo o ADR 007."
  ;; DiffSinger
  (let ((ds (caine.voice:obter-ferramenta "diffsinger")))
    (assert-true ds "ferramenta diffsinger deve estar registrada")
    (assert-equal :svs (caine.voice:ferramenta-tipo ds))
    (assert-string= "diffsinger-utau" (caine.voice::ferramenta-pip ds))
    (assert-string= "bin/diffsinger-utau" (caine.voice::ferramenta-entry ds)))

  ;; ACE-Step v1.5
  (let ((as (caine.voice:obter-ferramenta "ace-step")))
    (assert-true as "ferramenta ace-step deve estar registrada")
    (assert-equal :t2m (caine.voice:ferramenta-tipo as))
    (assert-string= "ACE-Step v1.5" (caine.voice:ferramenta-nome as)))

  ;; CosyVoice2
  (let ((cv (caine.voice:obter-ferramenta "cosyvoice")))
    (assert-true cv "ferramenta cosyvoice deve estar registrada")
    (assert-equal :tts (caine.voice:ferramenta-tipo cv))
    (assert-string= "CosyVoice2-0.5B" (caine.voice:ferramenta-nome cv)))

  ;; Ferramentas existentes preservadas
  (assert-true (caine.voice:obter-ferramenta "demucs"))
  (assert-true (caine.voice:obter-ferramenta "seed-vc"))
  (assert-true (caine.voice:obter-ferramenta "openutau")))

(deftest test-diffsinger-helpers
  "Valida auxiliares de localização de executável e voicebank."
  ;; diffsinger-bin deve executar sem lançar condição não tratada
  (let ((bin (caine.voice:diffsinger-bin)))
    (assert-true (or (null bin) (stringp bin))))
  ;; artista-voicebank não deve lançar erro mesmo sem pasta existente
  (let ((vb (caine.voice:artista-voicebank "caine" :base "mock/rg-inexistente")))
    (assert-false vb "sem pasta de voicebank deve retornar nil")))

(deftest test-cli-dispatch-pipelines
  "Testa a validação de parâmetros dos comandos make e cover."
  ;; make sem argumentos obrigatórios deve falhar graciosamente retornando 1
  (assert-equal 1 (caine.voice::cmd-make '()))
  ;; cover sem argumentos obrigatórios deve retornar 1
  (assert-equal 1 (caine.voice::cmd-cover '()))
  ;; artists list deve retornar 0
  (assert-equal 0 (caine.voice::cmd-artists '("list"))))
