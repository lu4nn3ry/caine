# TODO — Caine

Roadmap vivo do projeto. Decisões de arquitetura em `docs/adr/`.

## S1 — Editor & produtor de música

Base: ADR 001 (state of the art 2026). Caine é um **editor e produtor de música
profissional**. Nada de cortes para redes sociais — foco em estúdio.

### Voz natural (`agent/voice/` — ADR 003)

- [x] Baixar ferramentas: GPT-SoVITS, seed-vc, Applio, DiffSinger, OpenUtau, Demucs
- [x] Sistema `caine-voice` (list/doctor/install/stems/convert/tts/mix/master/make/cover)
- [x] Pipeline de mix/master com ffmpeg (WAV 48k/24bit + loudnorm/LUFS)
- [ ] `caine-voice install` dos venvs + download de modelos
- [ ] Cover ponta-a-ponta com os áudios de `~/Music/lu4nn3ry`
- [ ] TTS/canto via GPT-SoVITS com modelo próprio da voz
- [ ] Conectar `caine-voice` ao `caine-nim` (tool calling)

### MIDI & SVS (`agent/voice/midi.lisp` — ADR 004)

- [x] Transcrição **mono** (pyin) → `.notes`
- [x] Transcrição **polifônica** (Basic Pitch, tflite CPU) → MIDI — padrão
- [x] Escritor **SMF** próprio em Lisp + render **FluidSynth** (SoundFont GM)
- [x] Nivelamento **loudnorm** no render
- [x] **Correção de afinação** (`tune`): tom (K-S + cobertura de escala) +
      quantização à escala (+centralização de bends) e passada de **F0 por
      nota** no WAV (`midi/sing/melody --tune[-audio]`)
- [x] SVS zero-shot (`sing`/`melody` via seed-vc, `--f0-condition`)
- [ ] Testar `sing`/`melody` ponta-a-ponta (depende de `install seed-vc`)
- [ ] Quantização à grade de tempo (ritmo)
- [ ] Engine AMT alternativa (MuScriptor/YourMT3) plugável
- [ ] SVS de alta qualidade (DiffSinger/OpenUtau + voicebank)

### MVP (prioridade)

- [ ] Separação de **stems offline** (6+: vocal, bateria, baixo, guitarras, piano)
- [x] **Edição nota a nota** (áudio→MIDI polifônico; falta tom/escala)
- [ ] **Mix**: faders, pan, EQ, compressão, reverb, sidechain
- [ ] **Metering**: LUFS, true peak, correlação de fase, espectro
- [ ] **Masterização** por destino (streaming/CD/vinil) com matching de referência
- [ ] Export **WAV 48kHz/24bit** e **stems WAV**

### Pós-MVP

- [ ] Geração de acompanhamento / co-produção (estilo Layers)
- [ ] Voice-convert / clonagem de voz
- [ ] Inpainting de trecho (regerar intro/verso/drop)
- [ ] Humanização de material gerado por IA
- [ ] Substituição de timbre (sound replacement)
- [ ] Núcleo de DAW: multipista não-destrutiva, VST3/CLAP, piano roll, automação
- [ ] Análise harmônica e sugestão de acordes
- [ ] Preferência por modelos de **pesos abertos / licença comercial**

## S2 — CLI NVIDIA NIM (`agent/nim/`)

Base: ADR 002.

- [x] ADR 001/002 em `docs/adr/`
- [x] Codec JSON próprio (encode/decode, sem dependências)
- [x] HTTP via `curl` (`uiop:run-program`)
- [x] Suporte a **API key** (env + arquivo com chmod 600)
- [x] **Persistência** de config e sessões
- [x] Registro de **ferramentas** + tools built-in
- [x] **Tool calling** com loop agêntico
- [x] CLI: `ask`, `chat`, `repl`, `key`, `config`, `models`, `sessions`, `tools`
- [ ] Testes automatizados do codec JSON
- [ ] Streaming de tokens (SSE)
- [ ] Integração do `caine-nim` com o daemon `GreenGROUNDS`
- [ ] Modo `--json` para consumo programático pela IA

## S3 — Infra / Dev

- [x] Runtime Common Lisp (SBCL) + `ffmpeg` + `yt-dlp`
- [ ] CI: rodar smoke tests de carga do sistema ASDF
- [ ] Empacotar executável standalone (`asdf:make`)
