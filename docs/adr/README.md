# ADR Log — Caine

Registro de decisões de arquitetura (Architecture Decision Records).

| #    | Título                              | Status | Data       |
| ---- | ----------------------------------- | ------ | ---------- |
| 001  | State of the Art 2026 (editor)      | Aceito | 2026-09-17 |
| 002  | CLI NVIDIA NIM com tool calling     | Aceito | 2026-09-17 |
| 003  | Integração das ferramentas de voz   | Aceito | 2026-09-17 |
| 004  | Transcrição MIDI e SVS (canto)      | Aceito | 2026-09-17 |
| 005  | Geração de letras (caine-lyrics)    | Aceito | 2026-09-17 |
| 006  | Personalidades como artistas (caine-artists) | Aceito | 2026-09-17 |
| 007  | Engines 2026 (DiffSinger-utau, ACE-Step, CosyVoice2) | Aceito | 2026-09-17 |

## Formato

Cada ADR é imutável após aceito. Para mudar uma decisão, cria-se um novo ADR que
substitui o anterior. Template: `docs/adr/template.md`.

---

## Síntese do Estado da Arquitetura (Sessão 2026-09-17)

### 1. Correções Estruturais e Estabilização de Código
- **`agent/voice/package.lisp`**: Saneamento de exports com lista consolidada de símbolos de produção (`render-diffsinger`, `diffsinger-bin`, `generate-acestep`, `tts-cosyvoice`, `artista-voicebank`, `produzir-versao-artista`, `produzir-album-artistas`).
- **`agent/voice/artists.lisp`**: Deduplicação de loops e saneamento dos parâmetros de `produzir-album-artistas`.
- **`agent/nim/tools.lisp`**: Normalização das chamadas de tool calling para NVIDIA NIM (`tools_enabled :false`, persistência via `string->file`, ramificação simplificada).

### 2. Validação e Cobertura de Testes
- Suíte autossuficiente e offline em Common Lisp (`tests/run-tests.lisp`).
- Cobertura expandida para **20 testes unitários e 81 asserções OK** (0 falhas) em Windows e WSL:
  - Fonemização X-SAMPA e silabificação pt-BR (`tests/test-lyrics.lisp`).
  - Escrita/leitura binária de SMF formato 0 e alinhamento nota-sílaba (`tests/test-midi.lisp`).
  - Personas dos artistas Caine, Bubble, Ragatha e Scratch (`tests/test-artists.lisp`).
  - Motores neurais ADR 007 e dispatch de CLI make/cover (`tests/test-tools.lisp`).

### 3. Perfil de Hardware e Runtime
- **Host / Runtime**: WSL2 (Ubuntu) sobre Windows 11 com passthrough de driver NVIDIA.
- **GPU**: NVIDIA GeForce GTX 1650 (arquitetura Turing, Compute Capability 7.5, 4096 MiB VRAM).
- **Driver**: 610.43.02, CUDA 13.3.
- **Stack WSL**: SBCL, FFmpeg, FluidSynth, Curl, Python 3, uv e SoundFonts GM (`FluidR3_GM.sf2`).
- **Diretrizes de SO**: Runtime prioritário no WSL (ext4 nativo em `~/caine`), eliminando gargalos de I/O do DrvFS (`/mnt/c/`), conflitos de CRLF/LF e problemas de índice (`.git/index`).

### 4. Engines de 2026 e Estratégia de Síntese Vocal (ADR 007)
- **DiffSinger (`diffsinger-utau`)**: CLI headless via PyPI; inferência SVS acústica por difusão + vocoder NSF-HiFiGAN com aceleração CUDA. Integrado como passo 3/3 em `produzir-versao-artista`.
- **ACE-Step v1.5**: Foundation model de Text-to-Music e cover com letra (< 4GB VRAM para a GTX 1650).
- **CosyVoice2-0.5B / IndexTTS-2**: Clonagem zero-shot e TTS multilíngue para as personas.
- **NVIDIA NIM (Hospedado via API / NVCF)**:
  - Speech NIMs locais (Magpie TTS, Nemotron ASR, Studio Voice) requerem Ampere+ (CC ≥ 8.0) e ≥ 16GB VRAM, além de não suportarem WSL2 para TTS.
  - Decisão: Consumo via API na nuvem através do `caine-nim` (curl + API key), mantendo a inferência leve sem sobrecarregar a GPU local.
  - Modelos LLM NIM quantizados (≤ 4GB) permanecem como opção self-hosted para geração de letras.

### 5. Estado do Código vs. Próximos Passos
- **Código Lisp**: 100% implementado e commitado (`render-diffsinger`, `generate-acestep`, `tts-cosyvoice`, `artista-voicebank`, `fazer-cover :acestep`, subcomandos CLI `caine-voice artists list|write|prompt|sing|album`, `caine-voice cover`, `caine-voice make`).
- **Roadmap Operacional**:
  1. Instalação das dependências e pesos neurais no WSL (`caine-voice install diffsinger`, download de voicebanks em `out/rg/<id>/voicebank/`).
  2. Implementação das ferramentas de speech no `caine-nim` para Magpie TTS Multilingual (`POST /v1/audio/synthesize`).

