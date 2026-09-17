;;;; ============================================================================
;;;; test-artists.lisp — Testes unitários para o módulo de artistas (ADR 006)
;;;; ============================================================================

(in-package :caine.test-framework)

(deftest test-catalogo-artistas
  "Verifica se os 4 artistas de ADR 006 estão registrados e configurados."
  (let ((artistas (caine.voice:listar-artistas)))
    (assert-equal 4 (length artistas))
    (assert-true (caine.voice:obter-artista "caine"))
    (assert-true (caine.voice:obter-artista "bubble"))
    (assert-true (caine.voice:obter-artista "ragatha"))
    (assert-true (caine.voice:obter-artista "scratch"))))

(deftest test-detalhes-artistas
  "Valida os metadados específicos de cada persona."
  (let ((ragatha (caine.voice:obter-artista "ragatha"))
        (caine (caine.voice:obter-artista "caine")))
    (assert-string= "Ragatha" (caine.voice:perfil-artista-nome ragatha))
    (assert-string= "sereno" (caine.voice:perfil-artista-registro ragatha))
    (assert-string= "Caine" (caine.voice:perfil-artista-nome caine))
    (assert-string= "teatral" (caine.voice:perfil-artista-registro caine))))

(deftest test-gerar-letra-artista
  "Valida a geração de letra estruturada para uma persona específica."
  (let ((cancao (caine.voice:gerar-letra-artista "bubble" "Chiclete Espacial")))
    (assert-true (caine.voice:cancao-p cancao))
    (assert-true (search "Bubble" (caine.voice:cancao-titulo cancao)))
    (assert-true (plusp (length (caine.voice:cancao-secoes cancao))))))

(deftest test-prompt-persona
  "Garante que o prompt injeta a persona e as diretrizes artísticas."
  (let ((prompt (caine.voice:artista-prompt-letra "scratch" :tema "Vazio Binário")))
    (assert-true (stringp prompt))
    (assert-true (search "Scratch" prompt))
    (assert-true (search "Vazio Binário" prompt))))

