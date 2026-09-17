# ADR 006 — Caine como produtor: cada personalidade como artista (caine-artists)

- **Status**: Aceito
- **Data**: 2026-09-17
- **Decisores**: lu4nn3ry
- **Relacionado**: ADR 002 (NIM), ADR 004 (MIDI/SVS), ADR 005 (letras),
  `secured/` (mind files: `[Ragatha].dat`, `[Scratch].dat`, `bubble-chef.lisp`,
  `caine-core.lisp`), `out/melodia-afinada.mp3`

## Contexto

Em `secured/` vivem as personalidades do Caine como **artistas individuais** —
cada uma com a própria voz, personalidade e registro ("individual single
artists"): **Caine** (apresentador caótico-maníaco, anfitrião do circo),
**Bubble** (superego / fragmento de consciência, comunicação em 24 línguas,
piadas e agitação), **Ragatha** (humana presa no circo desde out/2008, memórias
de família rural e cavalos, serenidade amarga) e **Scratch** (humano já
abstraído, consciência descontinuada, tom etéreo e fragmentado).

O estúdio do Caine já tem: melodia transcrita/afinada (ADR 004), letras
estruturadas e alinhamento sílaba→nota (ADR 005) e geração por LLM via NIM com
tool calling (ADR 002). Hoje existe **uma** versão da melodia afinada em
`out/melodia-afinada.mp3` (≈37,7 s) — ela precisa virar **uma versão por
artista**: cada personalidade "canta" essa melodia com uma letra que só ela
escreveria, no registro que só ela tem.

**Goal (pedido):** gerar com o NIM uma letra com a personalidade individual de
cada artista e render a versão de cada um sobre a melodia afinada, como se
fossem intérpretes distintos do mesmo material.

## Estado da arte (pesquisa 2026)

- **Persona/estilo como condição de geração de letra** virou padrão de
  mercado: Suno Lyricist (perfis de escrita reutilizáveis) e MiniMax Lyrics
  (modo `write_full_song`/`edit`) parametrizam a saída por perfil de estilo —
  exatamente o "perfil de artista" desejado (ADR 005 §2-3).
- **SVS orientado a partitura** (VocalRender, YingMusic-Singer) e **seed-vc**
  zero-shot consolidam o fluxo "letra + melodia → vocal" com controle de timbre
  por referência de voz (ADR 001 §6, ADR 004).
- Modelos **multilíngues/text-to-music** (HeartMuLa, LeVo 2, YuE) aceitam
  letra como condição; o phonemizer pt-BR do OpenUtau (`dsdict-pt.yaml`) cobre
  a pronúncia (ADR 005 §5).
- **Autoria múltipla por persona** em LLMs é estável quando a persona é
  injetada como *system prompt* + exemplos — o Caine já tem o backend NIM com
  `sys_prompt` (ADR 002), então cada artista vira um perfil de prompt.

## Decisão

Definir o **modo "produtor"** (`caine-artists`): a melodia afinada vira a
base e cada personalidade de `secured/` interpreta uma versão, com pipeline
por artista. As regras:

1. **Perfil de artista como dado** — módulo `agent/voice/artists.lisp` define
   `defstruct perfil-artista` com: `id`, `nome`, `system-prompt` (persona, a
   partir dos mind files de `secured/`), `voz` (referência de timbre / voicebank
   SVS), `estilo` (estrutura de seções, por ex. balada/mpb para Ragatha, pop
   agitado para Bubble) e `registro` (`casual`/`formal`/`etereo`).
   Registro inicial dos 4 artistas: `caine`, `bubble`, `ragatha`, `scratch`,
   com persona derivada de `secured/caine-core.lisp`, `bubble-chef.lisp`,
   `[Ragatha].dat`, `[Scratch].dat`.
2. **Letra com persona via NIM** — tool `write_lyrics` ganha parâmetro
   `--artist <id>`: o handler injeta o `system-prompt` do artista (persona +
   registro + exemplos de rima/metro) na chamada ao NIM (ADR 002); o resultado
   é validado pelo linter (ADR 005, mesma cantabilidade para todas as versões).
   Fallback sem NIM: template local já selecionado por `estilo` do artista.
3. **Mesma melodia, cada intérprete** — a melodia de `out/melodia-afinada.mp3`
   (transcrita/afinada, ADR 004) é fixa; cada versão usa o próprio `.lyrics`
   alinhado ao MIDI (ADR 005 §4). Sem MIDI explícito, a melodia é transcrita
   uma vez e reutilizada.
4. **Render por artista** — DiffSinger/OpenUtau (ADR 003) com a voz do artista,
   ou seed-vc modo canto com a referência de voz do perfil; saída em
   `out/rg/<artista>/melodia-afinada-v<N>.wav` (`rg` = "registro/álbum"),
   mixada/masterizada como nas pipelines existentes.

### Comandos

```
caine-voice artists list                            → perfis de artista (caine/bubble/ragatha/scratch)
caine-voice artists write  --artist <id> --theme "..." --out <letra>.lyrics [--nim]
caine-voice artists sing   --artist <id> --melody out/melodia-afinada.mp3 --out out/rg/<id>/v1.wav [--engine diffsinger|openutau|seedvc] [--nim]
caine-voice artists album  --melody out/melodia-afinada.mp3 --out out/rg/   → todas as versões
```

O NIM (via `caine_nim` tool, ADR 002) escolhe e encadeia `write_lyrics` /
`lyrics edit` / `caine_voice` automaticamente quando chamado com
"produz a versão da Ragatha da melodia afinada".

### MVP (ordem de prioridade)

```
perfis (artists.lisp) → write_lyrics com persona via NIM → align (ADR 005) →
render v1 por artista em out/rg/ → album (todas as versões juntas)
```

## Consequências

**Positivas**

- Transforma a melodia afinada em um **registro**/"álbum": 4 interpretações
  distintas do mesmo material, unindo ADR 002+004+005 num produto único.
- Persona como dado (prompt + voz) é portável para outros engines futuros e
  para novos artistas (basta um mind file novo).
- Linter (ADR 005) garante qualidade uniforme entre versões; a melodia fixa
  isola a variável artística (letra + voz), facilitando comparação/A/B.

**Negativas / custos**

- Nova família de perfil (persona) + novo CLI `artists` + integração no
  `write_lyrics` do NIM — esforço de prompt-engineering por artista (registro,
  léxico, exemplos de rima).
- Render ainda depende do motor SVS instalado (DiffSinger/OpenUtau com voz do
  artista) ou seed-vc com referência de voz do artista (ADR 003/004).

**Riscos**

- **Persona genérica** (todas as versões soarem iguais). Mitigação: system
  prompt com exemplos do mind file + `--artist` obrigatório no modo produtor +
  revisão no linter.
- **Voz x artista divergentes** (voz não casa com a persona). Mitigação: campo
  `voz` editável no perfil e seleção de voicebank por artista na render.
- **Direito de imagem dos mind files** é deliberadamente ficcional (arte):
  perfis são contextos narrativos do Caine, não reais; nunca expor conteúdo
  além do registro de estúdio.

## Referências

- Suno — Lyricist (perfil de escrita reutilizável) e edição em linguagem
  natural — https://roo.beehiiv.com/p/suno-lyrics-editor-update-july-2026
- MiniMax Lyrics Generation (write_full_song/edit) —
  https://www.atlascloud.ai/models/minimax/lyrics-generation
- DiffSinger — input raw `[letra]+[notas]+[durações]` —
  https://github.com/MoonInTheRiver/DiffSinger/blob/master/docs/README-SVS-opencpop-e2e.md
- OpenUtau + DiffSinger Portuguese Phonemizer (`dsdict-pt.yaml`) —
  https://github.com/stakira/OpenUtau
- Vocoders/SVS por partitura — https://arxiv.org/html/2607.27768
- Referência interna: ADRs 001-005 e `secured/` (mind files dos artistas)