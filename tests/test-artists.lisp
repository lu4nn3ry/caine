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

(deftest test-artista-outdir-e-voz-ref
  "Valida a derivação de diretório de estúdio e busca de referência de voz."
  (let ((dir-caine (caine.voice:artista-outdir "caine" :base "mock/rg"))
        (voz-caine (caine.voice:artista-voz-ref "caine" :base "mock/rg")))
    (assert-true (uiop:directory-pathname-p dir-caine))
    (assert-true (search "caine" (namestring dir-caine)))
    (assert-false voz-caine "sem arquivos de voz prévios deve ser nil")))

(deftest test-alinhar-versao-artista
  "Valida a escrita das entradas DiffSinger (.ds) e OpenUtau (.uta) por artista."
  (let ((test-dir "mock/rg-test/ragatha/"))
    (unwind-protect
         (multiple-value-bind (al avisos ds uta)
             (caine.voice:alinhar-versao-artista "ragatha"
                                                "mock/melodia-exemplo.mid"
                                                "mock/exemplo.lyrics"
                                                :outdir test-dir)
           (declare (ignore avisos))
           (assert-true (caine.voice:alinhamento-p al))
           (assert-true (probe-file ds) "deve gerar arquivo .ds")
           (assert-true (probe-file uta) "deve gerar arquivo .uta")
           (assert-true (search "ragatha.ds" (namestring ds)))
           (assert-true (search "ragatha.uta" (namestring uta))))
      (uiop:delete-directory-tree (uiop:ensure-directory-pathname "mock/rg-test/")
                                  :validate t :if-does-not-exist :ignore))))

(deftest test-produzir-versao-artista
  "Valida o pipeline de produção por artista com engine :diffsinger."
  (let* ((out-wav "mock/rg-test/caine/caine-v1.wav")
         (work "mock/rg-test/caine/work/")
         (res (caine.voice:produzir-versao-artista "caine"
                                                  "mock/melodia-exemplo.mid"
                                                  out-wav
                                                  :mid "mock/melodia-exemplo.mid"
                                                  :letra "mock/exemplo.lyrics"
                                                  :engine :diffsinger
                                                  :workdir work)))
    (unwind-protect
         (progn
           (assert-string= out-wav (namestring res))
           (assert-true (probe-file (merge-pathnames "caine.ds" (uiop:ensure-directory-pathname work))))
           (assert-true (probe-file (merge-pathnames "caine.uta" (uiop:ensure-directory-pathname work)))))
      (uiop:delete-directory-tree (uiop:ensure-directory-pathname "mock/rg-test/")
                                  :validate t :if-does-not-exist :ignore))))

(deftest test-produzir-album-artistas
  "Valida a produção do álbum com todas as 4 versões de artistas."
  (let* ((album-dir "mock/rg-test/album")
         (saidas (caine.voice:produzir-album-artistas "mock/melodia-exemplo.mid"
                                                     :base album-dir
                                                     :mid "mock/melodia-exemplo.mid"
                                                     :engine :openutau)))
    (unwind-protect
         (progn
           (assert-equal 4 (length saidas))
           (dolist (s saidas)
             (assert-true (pathnamep s))))
      (uiop:delete-directory-tree (uiop:ensure-directory-pathname "mock/rg-test/")
                                  :validate t :if-does-not-exist :ignore))))


