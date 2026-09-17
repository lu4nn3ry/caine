;;;; ============================================================================
;;;; test-lyrics.lisp — Testes unitários para o módulo de letras
;;;; ============================================================================

(in-package :caine.test-framework)

(deftest test-limpar-acentos
  "Valida a normalização de caracteres acentuados sem erro de tipo."
  (assert-string= "verao" (caine.voice:limpar-acentos "verão" t))
  (assert-string= "coracao" (caine.voice:limpar-acentos "coração" t))
  (assert-string= "nao" (caine.voice:limpar-acentos "não" t))
  (assert-string= "musica" (caine.voice:limpar-acentos "música" t))
  (assert-string= "ao" (caine.voice:limpar-acentos "ão" t)))

(deftest test-chave-rima
  "Valida a extração da chave de rima fonética de palavras e versos."
  (assert-string= "ao" (caine.voice:chave-rima "Amor de Verão"))
  (assert-string= "ao" (caine.voice:chave-rima "o meu coração"))
  (assert-string= "e"  (caine.voice:chave-rima "tomando um café"))
  (assert-string= "ul" (caine.voice:chave-rima "o céu é azul")))

(deftest test-silabificador
  "Valida a segmentação e contagem silábica em pt-BR."
  (assert-equal 2 (caine.voice:contar-silabas-palavra "amor"))
  (assert-equal 2 (caine.voice:contar-silabas-palavra "verão"))
  (assert-equal 3 (caine.voice:contar-silabas-palavra "coração"))
  (assert-equal 1 (caine.voice:contar-silabas-palavra "não"))
  (assert-true (plusp (caine.voice:silabas-de-frase "Amor de Verão no circo digital"))))

(deftest test-gerar-letra-acentuada
  "Garante que gerar-letra não quebra com tema contendo 'Verão' (Item 1)."
  (let ((cancao (caine.voice:gerar-letra "Amor de Verão" :style "pop" :tempo 120)))
    (assert-true (caine.voice:cancao-p cancao))
    (assert-string= "Amor de Verão" (caine.voice:cancao-titulo cancao))
    (assert-true (plusp (length (caine.voice:cancao-secoes cancao))))
    (let ((primeira-secao (first (caine.voice:cancao-secoes cancao))))
      (assert-true (plusp (length (caine.voice:lyric-secao-linhas primeira-secao)))))))

(deftest test-analisar-letra
  "Valida o linter de cantabilidade e cálculo métrico."
  (let* ((cancao (caine.voice:gerar-letra "Circo da Ilusão" :style "pop"))
         (relatorio (caine.voice:analisar-letra cancao)))
    (assert-true (stringp relatorio))
    (assert-true (search "sílabas" relatorio))
    (assert-true (search "linhas" relatorio))))

(deftest test-fonemizar-letra
  "Valida a geração de fonemas X-SAMPA pt-BR."
  (let* ((cancao (caine.voice:gerar-letra "Luz" :style "pop"))
         (fonemas (caine.voice:fonemizar-letra cancao)))
    (assert-true (stringp fonemas))
    (assert-true (plusp (length fonemas)))))
