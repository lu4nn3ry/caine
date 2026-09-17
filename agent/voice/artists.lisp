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
