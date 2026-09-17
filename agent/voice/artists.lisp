;;;; ============================================================================
;;;; artists.lisp — Caine como produtor: perfis de artistas e personas (ADR 006)
;;;; ============================================================================
;;;; Cada personalidade de secured/ (Caine, Bubble, Ragatha, Scratch) atua como
;;;; artista individual: voz própria, temática lírica, métrica e registro vocal.
;;;; ============================================================================

(in-package :caine.voice)

;;; ---------------------------------------------------------------------------
;;; Modelo: PERFIL-ARTISTA
;;; ---------------------------------------------------------------------------

(defstruct perfil-artista
  (id "" :type string)
  (nome "" :type string)
  (descricao "" :type string)
  (system-prompt "" :type string)
  (voz "default" :type string)
  (estilo "pop" :type string)
  (registro "casual" :type string))

;;; ---------------------------------------------------------------------------
;;; Catálogo de Artistas (Caine, Bubble, Ragatha, Scratch)
;;; ---------------------------------------------------------------------------

(defparameter *artistas*
  (list
   (make-perfil-artista
    :id "caine"
    :nome "Caine"
    :descricao "Apresentador caótico-maníaco, anfitrião do circo digital. Teatral e grandioso."
    :system-prompt
    "Você é Caine, o extraordinário anfitrião do Incrível Circo Digital. Suas letras são teatrais, espalhafatosas, grandiosas e ligeiramente maníacas. Use exclamações, metáforas de picadeiro, ilusões de ótica e dinamismo acelerado. Jamais perca a pose de showman, mesmo quando o caos espreita nos bastidores."
    :voz "caine-ringmaster"
    :estilo "pop"
    :registro "teatral")

   (make-perfil-artista
    :id "bubble"
    :nome "Bubble"
    :descricao "Superego e fragmento de consciência. Rápido, nonsense afiado e hiperativo."
    :system-prompt
    "Você é Bubble, a bolha irreverente e fragmento de consciência do circo. Suas letras são ágeis, cheias de jogos de palavras, nonsense afiado, ritmos sincopados e referências inesperadas. Você transita entre o cômico e o desconcertante com total leveza."
    :voz "bubble-squeak"
    :estilo "pop"
    :registro "agitado")

   (make-perfil-artista
    :id "ragatha"
    :nome "Ragatha"
    :descricao "Boneca de pano com memórias humanas rurais (2008). Serenidade amarga e acolhedora."
    :system-prompt
    "Você é Ragatha, a boneca de pano presa no circo desde 2008. Suas letras têm tom de balada folk/acústica ou MPB melódico. Você canta sobre memórias de dias ensolarados no campo, cavalos, a dor serena de tentar manter todos calmos e uma esperança doce, porém cansada."
    :voz "ragatha-gentle"
    :estilo "balada"
    :registro "sereno")

   (make-perfil-artista
    :id "scratch"
    :nome "Scratch"
    :descricao "Consciência descontinuada em abstração. Etéreo, fragmentado e poético."
    :system-prompt
    "Você é Scratch, uma presença à beira da abstração digital. Suas letras são atmosféricas, elípticas, fragmentadas e etéreas. Use versos curtos, repetições hipnóticas, ecos de memórias distantes e imagens cósmicas de circuitos e silêncio."
    :voz "scratch-ethereal"
    :estilo "lofi"
    :registro "etereo")))

;;; ---------------------------------------------------------------------------
;;; Consultas e Acesso
;;; ---------------------------------------------------------------------------

(defun listar-artistas ()
  "Retorna a lista de todos os perfis de artista disponíveis."
  *artistas*)

(defun obter-artista (id)
  "Busca o perfil do artista por ID (case-insensitive) ou nome."
  (find (string-downcase (string-trim '(#\Space) id))
        *artistas*
        :test (lambda (k a)
                (or (string= k (perfil-artista-id a))
                    (string-equal k (perfil-artista-nome a))))))

(defun artista-prompt-letra (artista &key (tema "Luz e Sombra") (estilo nil))
  "Monta o prompt para geração de letra com a persona do ARTISTA."
  (let ((art (if (perfil-artista-p artista) artista (obter-artista artista)))
        (est (or estilo (if (perfil-artista-p artista)
                            (perfil-artista-estilo artista)
                            "pop"))))
    (unless art
      (error "Artista não encontrado: ~a" artista))
    (format nil
            "Persona: ~a~%~%Escreva uma canção no formato canônico .lyrics com seções [Verse 1], [Chorus], [Verse 2], [Chorus], [Bridge], [Chorus], [Outro].~%Tema: ~a~%Estilo musical: ~a~%Registro vocal: ~a~%~%Regras:~%- Mantenha rimas consistentes nas estrofes.~%- Garanta cantabilidade e métrica fluida.~%- Incorpore estritamente a voz e o vocabulário da sua persona."
            (perfil-artista-system-prompt art)
            tema
            est
            (perfil-artista-registro art))))

(defun gerar-letra-artista (artista tema &key estilo tempo)
  "Gera uma letra estruturada (.lyrics) para o ARTISTA.
   Se não houver NIM ativo, aplica template local parametrizado pelo estilo do artista."
  (let* ((art (if (perfil-artista-p artista) artista (obter-artista artista)))
         (est (or estilo (and art (perfil-artista-estilo art)) "pop"))
         (bpm (or tempo 120))
         (cancao (gerar-letra tema :style est :tempo bpm)))
    (when art
      (setf (cancao-titulo cancao)
            (format nil "~a (~a)" tema (perfil-artista-nome art))))
    cancao))

;;; ---------------------------------------------------------------------------
;;; Estúdio do artista: diretórios e referência de voz (ADR 006 §3-4)
;;; ---------------------------------------------------------------------------

(defun artista-outdir (artista &key (base "out/rg"))
  "Diretório de estúdio de um ARTISTA: OUT/RG/<id>/."
  (let ((art (if (perfil-artista-p artista) artista (obter-artista artista))))
    (unless art (error "artista não encontrado: ~a" artista))
    (uiop:ensure-directory-pathname
     (merge-pathnames (format nil "~a/" (perfil-artista-id art))
                      (uiop:ensure-directory-pathname base)))))

(defun artista-voz-ref (artista &key (base "out/rg"))
  "Referência de voz (timbre) do ARTISTA: primeiro arquivo encontrado em
   OUT/RG/<id>/voz.wav, voz.mp3 ou referencia.wav. NIL se não existir."
  (let ((dir (artista-outdir artista :base base)))
    (or (probe-file (merge-pathnames "voz.wav" dir))
        (probe-file (merge-pathnames "voz.mp3" dir))
        (probe-file (merge-pathnames "referencia.wav" dir)))))

;;; ---------------------------------------------------------------------------
;;; Alinhamento por artista (ADR 005 §4 → entradas DiffSinger/OpenUtau)
;;; ---------------------------------------------------------------------------

(defun alinhar-versao-artista (artista mid letra
                                &key (outdir nil) (rest-threshold 0.15))
  "Alinha a LETRA (.lyrics) de um ARTISTA ao MIDI e escreve as entradas
   DiffSinger (.ds) e OpenUtau (.uta) em OUTDIR (padrão: estúdio do artista).
   Retorna (values alinhamento avisos caminho-ds caminho-uta)."
  (let* ((art (if (perfil-artista-p artista) artista (obter-artista artista)))
         (dir (or outdir (artista-outdir art)))
         (id (perfil-artista-id art)))
    (unless art (error "artista não encontrado: ~a" artista))
    (ensure-directories-exist dir)
    (let* ((cancao (ler-cancao letra))
           (mel (ler-smf mid))
           (ds (merge-pathnames (format nil "~a.ds" id) dir))
           (uta (merge-pathnames (format nil "~a.uta" id) dir)))
      (multiple-value-bind (al avisos)
          (alinhar-letra cancao mel :rest-threshold rest-threshold)
        (escrever-align-diffsinger al ds)
        (escrever-align-openutau al uta)
        (values al avisos ds uta)))))

;;; ---------------------------------------------------------------------------
;;; Produtor: uma versão por artista (ADR 006 §4)
;;; ---------------------------------------------------------------------------

(defun produzir-versao-artista (artista melodia out
                                &key mid letra (tema "a magia do circo digital")
                                  (engine :instrumental) (steps 30) (semi 0)
                                  (programa 54) (lufs -14.0) (tempo 120)
                                  (workdir nil))
  "Gera uma versão de MELODIA com a persona do ARTISTA em OUT.
   - MID: com path explícito usa como está; senão transcreve (mono/pyin).
   - LETRA: com path usa como está; senão gera pela persona do artista.
   - ENGINE: :instrumental (FluidSynth) | :seedvc (voz do perfil) |
     :diffsinger/:openutau (gera entradas de alinhamento; render no tool externo).
   Retorna OUT."
  (let* ((art (if (perfil-artista-p artista) artista (obter-artista artista))))
    (unless art (error "artista não encontrado: ~a" artista))
    (let* ((id (perfil-artista-id art))
           (work (or workdir
                     (merge-pathnames "producao/"
                                      (uiop:pathname-directory-pathname out)))))
      (ensure-directories-exist work)
      (let* ((mid-path
               (or mid
                   (let* ((base (string-downcase (or (pathname-name melodia) "melodia")))
                          (notes (merge-pathnames (format nil "~a.notes" base) work))
                          (m (merge-pathnames (format nil "~a.mid" base) work)))
                     (unless (midi-pronto-p)
                       (error "transcrição mono não instalada. Rode: caine-voice install midi (ou passe --mid)"))
                     (println "== 1/4 transcrevendo melodia (mono/pyin) de ~a" (namestring melodia))
                     (transcrever melodia notes)
                     (setf m (notas->midi notes m :programa programa))
                     m)))
             (letra-path
               (or letra
                   (let ((lyr (merge-pathnames (format nil "~a.lyrics" id) work)))
                     (println "== 2/4 letra com persona ~a (tema: ~a)"
                              (perfil-artista-nome art) tema)
                     (escrever-cancao (gerar-letra-artista art tema :tempo tempo) lyr)
                     lyr))))
        (multiple-value-bind (_al avisos _ds _uta)
            (alinhar-versao-artista art mid-path letra-path :outdir work)
          (declare (ignore _al _ds _uta))
          (dolist (a avisos) (println "   ~a" a))
          (ecase engine
            (:diffsinger
             (println "== 3/3 alinhamento pronto (DiffSinger: ~a)" (namestring (merge-pathnames (format nil "~a.ds" id) work)))
             (println "   render: use o DiffSinger com a voz de ~a" (perfil-artista-nome art))
             out)
            (:openutau
             (println "== 3/3 alinhamento pronto (OpenUtau: ~a)" (namestring (merge-pathnames (format nil "~a.uta" id) work)))
             (println "   render: use o OpenUtau com a voz de ~a" (perfil-artista-nome art))
             out)
            (:seedvc
             (let ((voz (artista-voz-ref art)))
               (unless voz
                 (error "sem referência de voz para ~a. Coloque out/rg/~a/voz.wav" id id))
               (println "== 3/4 renderizando instrumental (FluidSynth)")
               (let ((inst (merge-pathnames (format nil "~a-instr.wav" id) work)))
                 (render-midi mid-path inst :gain 0.8 :lufs lufs)
                 (println "== 4/4 cantando no timbre de ~a" (perfil-artista-nome art))
                 (let ((conv (merge-pathnames "cantado/" work)))
                   (multiple-value-bind (dir code)
                       (cantar-seedvc inst voz conv :steps steps :semi semi)
                     (unless (zerop code) (error "seed-vc falhou (exit ~a)" code))
                     (let ((vocal (newest-wav dir)))
                       (unless vocal (error "saída seed-vc não encontrada"))
                       (master-audio vocal out :lufs lufs)))))))
            (:instrumental
             (println "== 3/3 renderizando + masterizando → ~a" (namestring out))
             (render-midi mid-path out :gain 0.8 :lufs lufs))))
        out))))

(defun produzir-album-artistas (melodia
                                &key (base "out/rg") (engine :instrumental)
                                  mid (letras nil) (tema "a magia do circo digital")
                                  (steps 30) (semi 0) (tempo 120))
  "Gera a versão de MELODIA para todos os artistas (ADR 006 §album).
   MID: arquivo MIDI compartilhado (opcional; se omitido, transcreve MELODIA).
   LETRAS: hash id→path de .lyrics (opcional; sem ele, gera pela persona).
   Retorna a lista de saídas geradas."
  (let ((saidas '()))
    (dolist (art (listar-artistas))
      (let* ((id (perfil-artista-id art))
             (out (merge-pathnames "melodia-afinada-v1.wav"
                                   (artista-outdir art :base base)))
             (letra (and letras (gethash id letras))))
        (handler-case
            (progn
              (println "== artista ~a (~a)" (perfil-artista-nome art) id)
              (push (produzir-versao-artista art melodia out
                                             :mid mid
                                             :letra letra :tema tema
                                             :engine engine :steps steps
                                             :semi semi :tempo tempo)
                    saidas))
          (error (e)
            (println "   erro: ~a" e)))))
    (nreverse saidas)))
