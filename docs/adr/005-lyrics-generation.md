# ADR 005 — Geração de letras (caine-lyrics)

- **Status**: Aceito
- **Data**: 2026-09-17
- **Decisores**: lu4nn3ry
- **Relacionado**: ADR 001, ADR 002, ADR 003, ADR 004, `agent/voice/`

## Contexto

O Caine já transmere → afina → canta melodia (ADR 004) e orquestra SVS
(DiffSinger/OpenUtau, ADR 003). O elo que falta no fluxo de estúdio é a
**letra**: escrevê-la, avaliá-la e convertê-la no insumo que o SVS consome
(sílabas → notas → fonemas). Sem letra, `DiffSinger`/`OpenUtau` não cantam.

A geração em si pode usar o backend LLM com tool calling do `caine-nim`
(ADR 002); a análise de **cantabilidade** e o **alinhamento sílaba→nota** são
problemas determinísticos que devem rodar local, em Lisp puro, sem GPU — mesma
filosofia offline-first do ADR 001.

## Estado da arte (pesquisa 2026)

### 1. Letra estruturada por seções virou padrão de mercado

`[Verse]`, `[Pre-Chorus]`, `[Chorus]`, `[Bridge]`, `[Outro]` são hoje lidas por
todos os motores (Suno, Udio, MiniMax Music, Tencent SongGeneration/LeVo 2,
HeartMuLa). As tags de seção **controlam o arranjo**, não são cosmética. O
léxico de disciplina lírica é portável entre motores (metro consistente entre
seções pareadas, rimas que funcionam faladas, final de verso em vogal aberta,
palavra-chave em posição forte) — é craft de voz humana, não de parser.

> Implicação: o Caine precisa de um **formato canônico de letra com seções**
> que alimente tanto o SVS quanto (no futuro) motores externos.

### 2. Editor de letras de nível de linha / linguagem natural

Suno jul/2026 reconstruiu o editor de letras: **Lyricist** (perfil de estilo
de escrita reutilizável), **edição por linguagem natural** ("deixa essa linha
mais engraçada"), **Variações/Rimas** (sugestão por palavra ou linha) e
estrutura marcada por seções. Suno v6 (set/2026) permite editar **uma linha
de letra** sem regerar a faixa. Na pesquisa acadêmica, **CLASVS** e
**YingMusic-Singer** fazem lyric editing preservando melodia (zero-shot, sem
alinhamento manual).

> Implicação: o Caine deve suportar **geração + edição incremental de letra**
> por instrução textual — o `caine-nim` já tem tool calling para isso.

### 3. Geração dedicada de letras (modelos/com serviço)

Surgiu oferta dedicada: **MiniMax Lyrics Generation** API (modo
`write_full_song` e `edit`, emite título + tags de estilo + seções, saída
direta para motores de música) e o modelo **ReMi** da Suno (rascunho:
rima, densidade silábica, pronúncia). Modelos abertos de texto→música
aceitam letra como condição e reportam agora alinhamento de fonema: **LeVo 2**
(Tencent, open, PER 8,55 %, formato `[Structure] ... ;`), **HeartMuLa**
(3B, multilíngue, tags de seção), **Muse** (ACL 2026: dataset 116k músicas
licenciadas + pesos abertos), **YuE** (ICLR 2026), **Qwen-Music** (Melody-CoT).

> Implicação: geração por **LLM genérico via NIM** resolve para o Caine agora;
> motor dedicado aberto fica como engine plugável (mesmo padrão do MuScriptor
> no ADR 004).

### 4. Alinhamento letra→música automatizado por LLM

**SegTune** usa um LLM como **predictor de duração** que gera timestamps de
sentença em formato LRC (LyRiCs); **JAM** dá controle de tempo no nível de
**palavra e fonema**; **SongCraft** introduz **alinhamento de fonema por
palavra**. O DiffSinger/OpenUtau consome exatamente `[letra] + [MIDI]` →
fonemas + durações (input `text` + `notes` + `notes_duration`).

> Implicação: o "alinhador" do Caine é o **mapeamento sílaba→nota** sobre o
> MIDI já existente (ADR 004) — deterministicamente em Lisp; LLM opcional para
> estimar timestamps de sentença quando não houver MIDI.

### 5. Prosódia engrenada: silabificação, rima, métrica

Engine **mora** (Rust, MIT/Apache-2.0) faz silabificação (hierarquia de
sonoridade), peso/pé métrico e rima (perfeita/slant/assonância/consonância)
sem depender do sistema de escrita — base para medir cantabilidade. Em pt-BR
o OpenUtau já tem **DiffSinger Portuguese Phonemizer** (`dsdict-pt.yaml`) e a
comunidade mantém **Phonemizers-PTBR** (BRAPA CV, X-SAMPA, CATIPA para
DiffSinger).

> Implicação: a análise (contagem de sílabas, rima, metro) é resolvida **com
> regras de Lisp puro + dicionário de exceções pt-BR**; a conversão G2P final
> delega ao stack do OpenUtau/DiffSinger.

### 6. SVS orientado a partitura 2026 (letra como input)

**VocalRender** sintetiza de partitura simbólica com representação interleaved
sílaba–nota e melisma (1 sílaba → várias notas) sem predictor de duração;
**SoulX-Singer** (42k h, EN/ZH/YUE), **YingMusic-Singer** (zero-shot, sem
alinhamento fonêmico), **UniVoice** (fala+canto unificados) e o **seed-vc**
(ADR 001 §6) consolidam. Ou seja: letra tratada como dado estruturado de
partitura é o padrão de SVS em 2026.

## Decisão

Implementar **letras como mais uma família de tarefas do `caine-voice`**
(como `midi.lisp`, ADR 004), em `agent/voice/lyrics.lisp` + CLI
`caine-voice lyrics ...`:

1. **Formato canônico `.lyrics`** — seções com tags (`[Verse]`, `[Pre-Chorus]`,
   `[Chorus]`, `[Bridge]`, `[Outro]`, `[Intro]`), linhas = frases; cada linha
   carrega, de forma derivável, contagem de sílabas e rima-alvo.
2. **Geração/edição via `caine-nim`** — tools `write_lyrics` (tema + estilo +
   estrutura → letra com seções, rima e metro) e `edit_lyrics` (instrução em
   linguagem natural sobre letra existente, seção a seção). **Fallback local
   sem NIM**: template de estrutura + léxico (rascunho, qualidade inferior).
3. **Linter de cantabilidade em Lisp puro** — silabificador pt-BR (regras +
   exceções), contagem de sílabas por linha, metro pareado entre seções,
   rima (perfeita/assonância por núcleo tônico), finais de verso em vogal
   aberta, densidade silábica por BPM, aviso de sílaba-por-nota estourada.
4. **Alinhamento sílaba→nota** — recebe letra + notas/MIDI (ADR 004), atribui
   1 sílaba/nota, melisma (vogal estendida) quando nota > sílaba, silêncios em
   `rest`; emite `text`/`notes`/`notes_duration` no formato do DiffSinger e
   arquivo padrão do OpenUtau.
5. **G2P pt-BR** — converte letra em fonemas DiffSinger via `dsdict-pt.yaml` /
   fonemas X-SAMPA (OpenUtau/Phonemizers-PTBR); sem ele disponível, fonema-hint
   manual e erro claro pedindo a instalação (mesmo padrão de fallback do ADR 003).

### Comandos

```
caine-voice lyrics write   --theme "..." --style "..." [--nim] [--lang pt]
caine-voice lyrics edit    --in <f.lyrics> "deixa a segunda estrofe mais direta"
caine-voice lyrics analyze --in <f.lyrics> [--bpm 128]      → relatório do linter
caine-voice lyrics align   --in <f.lyrics> --mid <f.mid> --out <dir>
caine-voice lyrics phonemize --in <f.lyrics> --out <f.txt>  → fonemas DiffSinger pt
```

Tudo se integra à pipeline existente: `lyrics + melody → sing/cover` e, com o
voicebank, ao DiffSinger/OpenUtau.

### MVP (ordem de prioridade)

```
lyrics (formato+seções) → analyze (linter pt) → write/edit via NIM →
align sílaba→nota (com MIDI) → phonemize DiffSinger → SVS (sing/cover)
```

## Consequências

**Positivas**

- Fecha o loop "ideia → letra → melodia → vocal" sem sair do Caine; geração
  via NIM, análise e alinhamento 100 % locais (sem GPU).
- Linter e alinhador são determinísticos e testáveis sem GPU (como o ffmpeg no
  ADR 003 e o tom por K-S no ADR 004).
- Formato estruturado por seções é compatível com futuros engines externos
  (HeartMuLa/LeVo/Suno) caso o Caine algum dia orquestre geração de música.
- Edição incremental por instrução aproveita o tool calling já implementado.

**Negativas / custos**

- Silabificador/rima pt-BR em Lisp exige regras e um dicionário de exceções
  (esforço de lexicografia, nível do perfil tonal K-S do ADR 004).
- Sem NIM, a geração de qualidade cai para rascunho por template.
- G2P precisa de um fonemizador/pt instalado para a saída de produção.

**Riscos**

- **G2P errado → fonemas errados → canto ininteligível.** Mitigação:
  fonema-hint, validação do dicionário `dsdict-pt.yaml` e verificação manual
  amostral antes de render final.
- **Colisão de letra/plágio em material LLM.** Mitigação: `--theme` original,
  checagem de colisão no linter e preferência por pesos abertos/licença comercial
  (ADR 001 §5) nas ferramentas usadas.
- Modelo dedicado de letras (ex.: MiniMax) exige API externa: fica como tool
  plugável futura, jamais dependência do núcleo.

## Referências

- Suno — Lyrics Editor jul/2026 (Lyricist, edição em linguagem natural,
  variações/rimas, tags de seção) — https://roo.beehiiv.com/p/suno-lyrics-editor-update-july-2026
- Suno — v6 (edição de uma linha de letra preservando o resto) —
  https://about.suno.com/blog/introducing-v6
- MiniMax Lyrics Generation (write_full_song/edit, saída estruturada) —
  https://www.atlascloud.ai/models/minimax/lyrics-generation
- Tencent SongGeneration / LeVo 2 (PER 8,55 %, formato `[Structure]`) —
  https://github.com/tencent-ailab/SongGeneration
- HeartMuLa (3B open, letra + tags de seção, multilíngue) —
  https://github.com/dapi4/heartmula
- Muse (ACL 2026, dataset 116k músicas licenciadas, pesos abertos) —
  https://aclanthology.org/2026.findings-acl.1129.pdf
- YuE — https://proceedings.iclr.cc/paper_files/paper/2026/file/a6a21421022d1da16eadbba533980530-Paper-Conference.pdf
- Qwen-Music (Melody-CoT) — https://www.alphaxiv.org/overview/2607.11699
- SegTune (predictor LLM de timestamps LRC) —
  https://aclanthology.org/2026.acl-long.586.pdf
- JAM (controle de tempo por palavra/fonema) —
  https://github.com/declare-lab/jamify
- SongCraft (alinhamento de fonema por palavra) — https://arxiv.org/abs/2609.16315
- VocalRender (SVS score-native, interleaved sílaba–nota, melisma) —
  https://arxiv.org/html/2607.27768
- YingMusic-Singer / SoulX-Singer / CLASVS (lyric edit preservando melodia) —
  https://arxiv.org/abs/2608.03253
- mora — engine de prosódia (silabificação, métrica, rima) —
  https://github.com/merely-made/mora
- OpenUtau — DiffSingerPortuguesePhonemizer (`dsdict-pt.yaml`) —
  https://github.com/stakira/OpenUtau
- Phonemizers-PTBR (BRAPA/X-SAMPA/CATIPA DiffSinger) —
  https://github.com/dorayakito/Phonemizers-PTBR
- DiffSinger — input raw `[letra]+[notas]+[durações]` →
  https://github.com/MoonInTheRiver/DiffSinger/blob/master/docs/README-SVS-opencpop-e2e.md