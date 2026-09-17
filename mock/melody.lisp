;;;; ============================================================================
;;;; mock/melody.lisp — Gerador de melodias e dados mock para o Caine
;;;; ============================================================================
;;;; Permite testar e validar o alinhamento letra->nota (lyrics align), DiffSinger
;;;; e OpenUtau sem depender do pipeline em Python (pyin/librosa/Basic Pitch).
;;;; ============================================================================

(defpackage :caine.mock
  (:use :cl)
  (:export
   #:gerar-melodia-mock
   #:escrever-midi-mock
   #:gerar-letra-mock
   #:escrever-letra-mock
   #:gerar-arquivos-mock))

(in-package :caine.mock)

(defun gerar-melodia-mock (&key (bpm 120) (num-notas 16))
  "Delega para a função central caine.voice:gerar-melodia-mock."
  (caine.voice:gerar-melodia-mock :bpm bpm :num-notas num-notas))

(defun escrever-midi-mock (caminho &key (bpm 120) (num-notas 16))
  "Salva um arquivo MIDI mock em CAMINHO."
  (caine.voice:escrever-midi-mock caminho :bpm bpm :num-notas num-notas))

(defun gerar-letra-mock (&optional (titulo "Canção de Teste"))
  "Gera uma estrutura CANCAO de teste para casar com a melodia mock."
  (let ((cancao (caine.voice:make-cancao :titulo titulo :tempo 120)))
    (setf (caine.voice:cancao-secoes cancao)
          (list
           (caine.voice:make-lyric-secao
            :tag "Verse 1"
            :linhas (list
                     (caine.voice:make-lyric-linha
                      :texto "O sol brilha no céu azul"
                      :silabas 7
                      :rima "ul")
                     (caine.voice:make-lyric-linha
                      :texto "Vem cantar com emoção"
                      :silabas 6
                      :rima "ao")))
           (caine.voice:make-lyric-secao
            :tag "Chorus"
            :linhas (list
                     (caine.voice:make-lyric-linha
                      :texto "A música toca no coração"
                      :silabas 8
                      :rima "ao")
                     (caine.voice:make-lyric-linha
                      :texto "Tudo acende no verão"
                      :silabas 7
                      :rima "ao")))))
    cancao))

(defun escrever-letra-mock (caminho &optional (titulo "Canção de Teste"))
  "Salva um arquivo .lyrics no formato canônico."
  (let ((cancao (gerar-letra-mock titulo)))
    (ensure-directories-exist caminho)
    (caine.voice:escrever-cancao cancao caminho)
    caminho))

(defun gerar-arquivos-mock (&optional (dir "mock/"))
  "Gera os arquivos de exemplo mock em DIR."
  (let ((mid-path (merge-pathnames "melodia-exemplo.mid" (uiop:ensure-directory-pathname dir)))
        (lyr-path (merge-pathnames "exemplo.lyrics" (uiop:ensure-directory-pathname dir))))
    (escrever-midi-mock (namestring mid-path))
    (escrever-letra-mock (namestring lyr-path))
    (values (namestring mid-path) (namestring lyr-path))))

