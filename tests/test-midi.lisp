;;;; ============================================================================
;;;; test-midi.lisp — Testes unitários para MIDI e alinhamento sílaba->nota
;;;; ============================================================================

(in-package :caine.test-framework)

(deftest test-mock-melodia
  "Valida a geração de melodia sintética mock em Lisp puro."
  (let ((mel (caine.voice:gerar-melodia-mock :bpm 120 :num-notas 8)))
    (assert-true (caine.voice:melodia-p mel))
    (assert-equal 120 (caine.voice:melodia-bpm mel))
    (assert-equal 8 (length (caine.voice:melodia-notas mel)))))

(deftest test-midi-roundtrip
  "Valida a escrita e leitura binária de arquivo SMF (Standard MIDI File)."
  (let ((mid-path "mock/test-temp.mid")
        (mel-orig (caine.voice:gerar-melodia-mock :bpm 120 :num-notas 4)))
    (unwind-protect
         (progn
           (caine.voice:escrever-smf mel-orig mid-path)
           (assert-true (probe-file mid-path))
           (let ((mel-lida (caine.voice:ler-smf mid-path)))
             (assert-true (caine.voice:melodia-p mel-lida))
             (assert-equal 4 (length (caine.voice:melodia-notas mel-lida)))))
      (when (probe-file mid-path)
        (delete-file mid-path)))))

(deftest test-alinhar-letra-com-mock
  "Valida o alinhamento de sílabas da letra com as notas da melodia mock."
  (let* ((mel (caine.voice:gerar-melodia-mock :bpm 120 :num-notas 12))
         (cancao (caine.voice:gerar-letra "Alegria" :style "pop")))
    (multiple-value-bind (al avisos)
        (caine.voice:alinhar-letra cancao mel :rest-threshold 0.15)
      (declare (ignore avisos))
      (assert-true (caine.voice:alinhamento-p al))
      (assert-true (plusp (length (caine.voice:alinhamento-syllables al))))
      (assert-true (plusp (length (caine.voice:alinhamento-notes al)))))))

