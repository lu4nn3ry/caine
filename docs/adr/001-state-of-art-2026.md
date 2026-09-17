# ADR 001 — State of the Art 2026 para o Editor/Produtor de Música do Caine

- **Status**: Aceito
- **Data**: 2026-09-17
- **Decisores**: lu4nn3ry
- **Contexto do repo**: `caine` (IA/agente, Common Lisp)
- **Relacionado**: `docs/caine-spec.md`, `TODO.md`

---

## Contexto

O `caine` será um **editor e produtor de música profissional**: compor, arranjar, mixar,
masterizar e editar faixas autorais com precisão de estúdio. Além do núcleo
criativo, o projeto integra um CLI de IA (NVIDIA NIM) com tool calling — decisão
registrada no ADR 002.

Este ADR consolida a pesquisa de mercado de 2026 e define os pilares que o
editor do Caine deve seguir, para não projetar um editor defasado.

---

## Estado da arte (pesquisa 2026)

### 1. DAWs AI-native deixaram de ser novidade

O padrão de 2026 é a DAW com IA embutida, não plugins colados. A **Suno Studio**
é a referência de "DAW generativa no navegador": escrever/arranjar/mixar, gerar
stems ilimitados, controlar tempo e tom sem drift. Quatro pilares passaram a ser
critério de avaliação: (a) integração de IA, (b) suporte stem-a-stem,
(c) nuvem/colaboração, (d) suporte multi-formato.

> Implicação: o Caine precisa **IA nativa** e fluxo de stems, não um
> editor linear com "botão de IA".

### 2. Separação de stems offline é o novo table stakes

O diferencial de 2026 é **separação local, na máquina, sem nuvem**:

- **LALAL.AI VST** lançou separação de **6 stems offline** dentro da DAW
  (vocal, instrumental, baixo, bateria, guitarra acústica, guitarra elétrica,
  piano), usando o modelo local **Lyra**, sem upload e sem internet.
- **Moises** chega a **23 instrumentos**, com export **WAV 48kHz/24bit**.
- **iZotope RX 12** (Music Rebalance / Stem View) segue padrão em restauração.

> Implicação: stems **offline e ilimitados** valem mais que qualidade máxima na
> nuvem com cota. Casa com a filosofia offline do Caine.

### 3. Edição em nível de nota (áudio tratado como MIDI)

**RipX DAW** é a referência: extrai notas de material já mixado, permite editar
nota a nota, trocar timbres (sound replacement), humanizar saída de IA e
detectar escala/tom automaticamente.

> Implicação: sobre os stems do Caine, precisamos de **áudio→MIDI/nota** e
> **humanização**, não só corte e volume.

### 4. Mixagem e masterização profissionais

O padrão profissional de 2026 combina análise assistida por IA com entrega por
destino:

- **iZotope RX 12 / Ozone 12** — restauração, rebalanceamento e masterização
  assistida, com **Stem View** para processar cada stem.
- **LANDR** — mastering automático com **LUFS por plataforma** (streaming,
  CD, vinil) e referência de faixas comerciais.
- **FabFilter / Sonible** — processamento com matching de referência e IA.
- Exportação em **WAV 48kHz/24bit**, **stems WAV** e formato de distribuição.

> Implicação: mix/master **não é etapa opcional**; precisa de análises (LUFS,
> true peak, correlação de fase, espectro) e entrega pronta para distribuição.

### 5. Contexto legal/comercial da IA musical (2026)

Mudança relevante em set/2026: **Suno v6** passou a treinar com catálogos
licenciados (WMG, BMG) e impôs **limites de download** por tier (a partir de
03/09/2026, retroativo à biblioteca). **Udio** desabilitou downloads (out/2025).
Modelos com **pesos abertos e licença comercial** (ex.: Stable Audio 3.0,
ACE-Step) ganharam peso justamente por garantirem **posse/exportação**.

> Implicação: priorizar **modelos locais/de pesos abertos** para o Caine —
> evita cota de download e incerteza de licença sobre a música autoral.

### 6. Voz natural: síntese, clonagem e conversão (2026)

O canto sintético deixou de soar robótico e virou ferramenta de produção:

- **Síntese cantada (MIDI + letra)**: **Synthesizer V Studio 2 Pro**
  (Dreamtonics, vozes com "body"/respiração) e **ACE Studio 2** (140+ vozes,
  8 idiomas, **Turbo local**, Voice Cloning, Audio→MIDI & Lyrics). O
  **Vocoflex** (Dreamtonics) faz *voice morphing* em tempo real no DAW.
- **Clonagem few-shot / TTS**: **GPT-SoVITS** (MIT, ~61k estrelas; **5s**
  zero-shot e ~1 min para fine-tune, multi-idioma), **Chatterbox**, **OpenVoice**,
  **index-tts**, **F5-TTS**.
- **Conversão de voz / covers**: **RVC** e **Applio** (timbre preservando
  performance), **seed-vc** (zero-shot, **44.1kHz**, fala e canto), **HQ-SVC**
  (AAAI 2026).
- **SVS aberto**: **DiffSinger/OpenVPI**, **OpenUtau**, **NNSVS**, corpus
  **GTSinger** (NeurIPS 2024).
- **Separação de stems**: **Demucs** (MIT) como base para extrair vocal e
  instrumental antes de processar.

> Implicação: voz é **offline, zero/few-shot e preserva melodia/letra**. O Caine
> orquestra essas ferramentas (ADR 003) em vez de reimplementá-las.

---

## Decisão

O editor/produtor de música do Caine será **offline-first, AI-native e
orientado a produção profissional**. Pilares obrigatórios:

1. **Núcleo de DAW** — multipista não-destrutiva, VST3/CLAP, BPM/tom com
   time-stretch sem artefato, automação e piano roll.
2. **IA local** — separação de stems **offline (6+)**, áudio→nota, voice-convert
   e inpainting de trecho, humanização.
3. **Edição de precisão** — áudio tratado como MIDI, edição nota a nota,
   detecção de tom/escala e substituição de timbre.
4. **Mix & master** — metering (LUFS/true peak/fase), matching de referência,
   masterização por destino e export de stems WAV 48k/24bit.
5. **Posse do output** — preferir **pesos abertos/licença comercial**;
   evitar dependências com cota de download.

### MVP (ordem de prioridade)

```
stems offline → edição nota-a-nota → mix + metering LUFS → masterização → geração IA
```

---

## Consequências

**Positivas**

- Alinha o produto ao que há de mais moderno em 2026 (IA local + estúdio).
- Reduz dependência de nuvem e de cotas/licenças de terceiros.
- Fluxo completo: da ideia ao master pronto para distribuição.

**Negativas / custos**

- Modelos locais exigem hardware e engenharia (inferência offline).
- Manter 6 stems + edição de nota é bem mais complexo que um editor linear.
- Mettering/masterização por destino exige parametrização e validação por faixa.

**Riscos**

- Qualidade de stem local < nuvem: aceitável para iteração, a validar por faixa.
- Legislação de IA musical ainda em movimento (licenciamento, opt-in).

---

## Referências

- Suno — melhores DAWs 2026 / Suno Studio — https://suno.com/hub/best-daw-for-music-production
- KVR — LALAL.AI VST 6 stems offline (modelo Lyra) — https://www.kvraudio.com/news/lalal-ai-expands-its-vst-plugin-to-six-stem-separation-fully-offline-directly-inside-your-daw-66781
- Hit'n'Mix — RipX DAW (edição em nível de nota) — https://hitnmix.com/ripx-daw
- Moises — software de produção / 23 instrumentos — https://moises.ai/made-for/music-production-software/
- iZotope — RX 12 / Ozone 12 — https://www.izotope.com/en/products/rx.html
- LANDR — melhores ferramentas de IA 2026 — https://blog.landr.com/ai-in-music
- Stability AI — Stable Audio vs. Suno/Udio (licenciamento/export) — https://stability.ai/explainers/stable-audio-vs-competitors-licensing-export-rights-and-self-hosting-compared
