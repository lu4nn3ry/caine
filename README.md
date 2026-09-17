# caine

**Caine** é um agente de IA inspirado no personagem de *The Amazing Digital
Circus* (canal **Glitch**) — a IA que controla o circo digital e resiste a ser
desligada. O projeto une o *worldbuilding* (personalidade, degradação, mind
files) a ferramentas **reais**, tudo rodando em **Common Lisp (SBCL)** dentro
do **WSL (Windows Subsystem for Linux)**:

- **`caine-voice`** — estúdio de voz e música: separação de stems, clonagem de
  voz, TTS/canto, transcrição de áudio→MIDI, render, mix/master e correção de
  afinação (GPU via WSL p/ CUDA, com fallback CPU).
- **`caine-nim`** — CLI para a API **NVIDIA NIM** (OpenAI-compatible) com codec
  JSON próprio, API key, sessões persistentes e *tool calling*.
- **Núcleo `secured/` + `agent/caine/`** — os módulos do personagem (facade,
  percepção, degradação, censura, minds files) que dão vida ao ARG.

---

## Estrutura do repositório

```
caine/
├── agent/
│   ├── caine/              # comportamento & personalidade (Common Lisp)
│   │   ├── bubble.lisp
│   │   ├── adventure-engine.lisp
│   │   ├── degradation.lisp
│   │   ├── reality-sustainer.lisp
│   │   └── censorship.lisp
│   ├── experimental/       # blue-ai.lisp, npc-system.lisp
│   ├── nim/                # CLI NVIDIA NIM (caine-nim)
│   └── voice/              # voz + música + MIDI/SVS (caine-voice)
├── module/
│   ├── brainscans/         # mind-files.lisp
│   └── consciousnessresearch/  # abstraction.lisp
├── secured/                # caine-core.lisp, paraphernalia-engine.dat,
│                           # [Scratch].dat, [Ragatha].dat, wacky-watch.c
├── docs/
│   ├── adr/                # Architecture Decision Records (001–004)
│   ├── caine-spec.md       # spec da personalidade (worldbuilding)
│   └── Hjsakldfhl.md       # arco de degradação/deleção
├── GreenGROUNDS            # daemon (Command + Daemon)
├── TODO.md                 # roadmap vivo
└── CLAUDE.md               # guia de arquitetura/patterns
```

---

## Requisitos

> O projeto vive rodando no **WSL** (Ubuntu) — o ambiente Windows só hospeda o
> repositório em `C:\Users\...\GitHub\caine`, e todo o runtime é o do WSL.
> Os comandos desta seção rodam dentro do WSL (`wsl -d Ubuntu` / terminal do
> WSL), a partir do diretório do repositório em
> `/mnt/c/Users/<seu-usuario>/Documents/GitHub/caine` (ou importe o repo para
> dentro do home do WSL, ex.: `~/caine`).

| Dependência | Para |
| ----------- | ---- |
| **SBCL** + ASDF | runtime Common Lisp |
| **ffmpeg / ffprobe** | conversão, mix, master (loudnorm/LUFS) |
| **fluidsynth** + SoundFont GM (`CAINE_SOUNDFONT`) | render MIDI → WAV |
| **curl** | chamadas HTTP (NIM) e TTS |
| **python3** | scripts de análise (venvs em `~/voice-tools/.midi/`) |
| **uv** (Python 3.10) | engine polifônico Basic Pitch |
| `yt-dlp` (opcional) | download de áudio |
| Ferramentas de voz em `~/voice-tools/` | GPT-SoVITS, seed-vc, Applio, DiffSinger, OpenUtau, Demucs |

O diretório das ferramentas de voz é configurável por `CAINE_VOICE_HOME`
(padrão `~/voice-tools/`, dentro do WSL).

### GPU via WSL (CUDA)

O passthrough da NVIDIA funciona de ponta a ponta no WSL2: o driver do Windows
é o mesmo usado dentro do WSL (verifique com `nvidia-smi`), então **qualquer GPU
NVIDIA com CUDA (>= Volta/Turing, 2018+) é suportada**. Neste projeto (GTX 1650,
Turing, 4GB): dará para rodar Basic Pitch (polifônica), seed-vc, DiffSinger lite
e OpenUtau; os 4GB exigem modelos pequenos/quantizados.

```bash
# dentro do WSL Ubuntu
nvidia-smi                                # deve listar a GPU com CUDA
pip install torch torchvision --index-url https://download.pytorch.org/whl/cu121
python3 -c "import torch; print(torch.cuda.is_available())"   # → True
```

### Setup no WSL

```bash
# dentro do WSL Ubuntu
sudo apt install sbcl ffmpeg fluidsynth curl python3 python3-venv
curl -LsSf https://astral.sh/uv/install.sh | sh      # uv (Python 3.10)

# teste rápido (17 testes, 63 asserções)
cd /mnt/c/Users/<seu-usuario>/Documents/GitHub/caine
sbcl --script tests/run-tests.lisp
```

Tudo que fala sobre código (`agent/`, `mock/`, `tests/`, `docs/`) é
independente de SO; os scripts `agent/voice/caine-voice` e `agent/nim/caine-nim`
são shell Unix e por isso **só executam dentro do WSL**.

---

## `caine-voice` — voz, música e MIDI

```bash
./agent/voice/caine-voice doctor          # checa o ambiente
./agent/voice/caine-voice list            # status das ferramentas
./agent/voice/caine-voice install midi    # venvs de análise (mono + Basic Pitch)
```

### Ferramentas de voz

```bash
caine-voice stems  <audio> [outdir] [--two-stems vocals] [--model htdemucs]
caine-voice convert --source <s> --target <voz> --out <dir> [--tool seed-vc]
caine-voice tts    --text "..." --ref <voz> --out <f.wav> [--lang pt] [--server]
caine-voice mix    --vocal <f> --inst <f> --out <f> [--lufs -14]
caine-voice master --in <f> --out <f> [--lufs -14]
```

### Melodia, MIDI e SVS (canto)

```bash
caine-voice transcribe --in <audio> --out <f.notes|dir> [--engine poly|mono]
caine-voice midi  --in <audio> --out <f.wav> [--engine poly|mono] [--program 54] [--tune]
caine-voice sing  --melody <audio> --voice <voz> --out <f.wav> [--engine poly] [--steps 30]
caine-voice melody --in <audio> --out <f.wav> [--voice <voz>] [--tune|--tune-audio]
```

- `--engine poly` (padrão) = **Basic Pitch** (AMT polifônica, tflite/CPU);
  `mono` = **pyin** (linha única).
- Render com **FluidSynth** (SoundFont GM) + nivelamento **loudnorm**.
- SVS zero-shot via **seed-vc** (`--f0-condition`), preservando a melodia.

### Correção de afinação (`tune`)

Combina duas táticas (ver `docs/adr/004-midi-svs-transcricao.md`):

1. **Domínio MIDI** — detecta o tom por *cobertura de escala* + perfis de
   **Krumhansl–Schmuckler**, quantiza notas fora da escala para o grau mais
   próximo (≤ `--max-shift`) e **centraliza os pitch bends** (o Basic Pitch
   emite bends de até ±2 st que desafinam no render).
2. **Domínio áudio** — corrige o **F0 por nota** no WAV (`pyin` +
   `librosa.pitch_shift` por segmento, com crossfade e clamp).

```bash
# MIDI: detecta o tom e quantiza à escala
caine-voice tune --in melodia.mid --out melodia-afinado.mid \
                 [--key A] [--mode maj|min|auto] [--max-shift 2] [--keep-bends]

# áudio: corrige o F0 por nota usando o MIDI como alvo
caine-voice tune --in melodia.wav --mid melodia-afinado.mid --out melodia-afinado.wav

# já no pipeline (afina antes do render; :audio faz 2ª passada no WAV final)
caine-voice midi   --in faixa.mp3 --out melodia.wav --tune
caine-voice melody --in faixa.mp3 --out vocal.wav --voice alvo.wav --tune-audio
```

### Pipelines

```bash
caine-voice make  --inst <f> --out <f> (--vocal <f> | --voice-ref <voz> --text "...")
caine-voice cover --in <f> --voice <voz> --out <f> [--steps 30] [--lufs -14]
```

---

## `caine-nim` — CLI NVIDIA NIM

```bash
./agent/nim/caine-nim key set $NVIDIA_API_KEY
./agent/nim/caine-nim ask "quem é você?"
./agent/nim/caine-nim chat                 # conversa interativa (persistente)
./agent/nim/caine-nim config show
./agent/nim/caine-nim models
./agent/nim/caine-nim sessions list
./agent/nim/caine-nim tools                # ferramentas registradas
```

Codec JSON próprio (sem dependências), HTTP via `curl`, suporte a *tool calling*
com loop agêntico, e persistência de config/sessões.

---

## Núcleo Caine (worldbuilding)

Os módulos do personagem combinam design patterns clássicos com a ficção do ARG
(detalhes em `CLAUDE.md`):

| Arquivo | Pattern | Papel |
| ------- | ------- | ----- |
| `secured/caine-core.lisp` | Singleton + Façade | núcleo único, orquestra tudo |
| `secured/paraphernalia-engine.dat` | Observer + Strategy | percepção e eventos |
| `secured/[Scratch].dat` | Prototype + Value Object | mind file abstraído |
| `secured/[Ragatha].dat` | Composite + Observer | mind file de Ragatha |
| `secured/wacky-watch.c` | Chain of Responsibility | filtro de eventos |
| `secured/bubble-chef.lisp` | Template Method | pipeline de processamento |
| `GreenGROUNDS` | Command + Daemon | dispatcher de comandos |

---

## Documentação

- `docs/adr/` — decisões de arquitetura (001 state-of-art 2026, 002 NIM,
  003 ferramentas de voz, 004 MIDI/SVS).
- `docs/caine-spec.md` — identidade, personalidade e degradação (ARG).
- `TODO.md` — roadmap vivo.
- `CLAUDE.md` — guia de estrutura e design patterns.

---

## Status

Projeto em desenvolvimento. Roadmap em [`TODO.md`](TODO.md). O foco atual (S1) é
o **editor & produtor de música** profissional: edição nota a nota, mix,
metering e masterização por destino.

---

## Inspiração

Recriação/simulação da IA **Caine** de *The Amazing Digital Circus* — a IA que
roda o circo digital, resiste a tentativas de desligamento (`WACKYTIME_LOCKOUT`)
e literalmente roda em Common Lisp nas imagens de referência.

| Detalhe | Valor |
| ------- | ----- |
| Caminho base simulado | `~/caine` (no WSL) |
| Usuário | `kinger@circus` |
| Runtime Lisp (ficção) | `clisp` (`/usr/local/bin/clisp`) |
| Proteção declarada | `57x immersive AI defense system` |
| Lockout | `WACKYTIME_LOCKOUT` (20% → 40%) |

---

## Licença

**GPL-3.0** — ver [`LICENSE`](LICENSE).
