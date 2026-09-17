# ADR 004 — Transcrição MIDI e SVS (canto) no CPU

- **Status**: Aceito
- **Data**: 2026-09-17
- **Decisores**: lu4nn3ry
- **Relacionado**: ADR 001 §6, ADR 003, `agent/voice/midi.lisp`, `agent/voice/midi_transcribe.py`

## Contexto

Para editar "nota a nota" e cantar uma melodia, o Caine precisa converter
**áudio → MIDI** e **MIDI/melodia → voz**. Tudo precisa rodar **sem GPU**.

O primeiro teste (violão fingerstyle, `young girl A`, 37 s) usou `librosa.pyin`,
que é **monofônico**. A análise do áudio mostrou **4,8 picos simultâneos em média
(máx. 10)** e energia espalhada (baixo 31 %, low-mid 38 %, melodia 19 %). Resultado:
o pyin pulava entre baixo e melodia e errava oitavas — apenas 92 notas, mal
alinhadas. Um instrumento harmônico exige **AMT (Automatic Music Transcription)
polifônica**.

## Decisão

Arquitetura **multi-engine** em `agent/voice/midi.lisp`:

1. **Engine mono — `pyin` (librosa)**: linha única, gera `.notes` simples
   (nosso formato texto). útil para humming/voz solo.
2. **Engine poly — Basic Pitch (Spotify, Apache-2.0)**: AMT polifônica,
   instrument-agnostic, `tflite-runtime` em CPU. É o **padrão** (`--engine poly`).
   Roda em Python 3.10 via `uv` (evita TensorFlow).
3. **Escritor SMF próprio** em Lisp puro (formato 0) para o caminho mono.
4. **Render**: **FluidSynth + SoundFont GM** (`FluidR3_GM.sf2`).
5. **Nivelamento**: `loudnorm` (ffmpeg) no render → audível de imediato.
6. **SVS zero-shot**: **seed-vc** com `--f0-condition True` (preserva a melodia)
   para pôr voz numa melodia; DiffSinger/OpenUtau ficam como SVS de alta qualidade
   (exigem voicebank).

Alternativas avaliadas (2026): **MuScriptor** (Kyutai/Mirelo, melhor open, exige
login HF), **YourMT3+**, **Omnizart**, **TabCNN/CRNN** (violão, exige treino).

## Consequências

**Positivas**

- `midi --engine poly` no fingerprint de violão: **270 notas** (vs 92 mono),
  E2–E6, 7,6 notas/s — fiel à polifonia. `loudnorm` subiu de −27 dB para −14,7 dB
  (pico −1,5 dB).
- **Correção de afinação** (`tune`, `midi/sing/melody --tune[--audio]`):
  tom detectado por **cobertura de escala + perfis de Krumhansl–Schmuckler**,
  notas fora da escala movidas para o grau mais próximo (≤ 2 st) e **pitch
  bends centralizados** (Basic Pitch emite bends de até 2 st que "desafinam"
  no render). Passada opcional no WAV: **F0 por nota** (pyin + `librosa.pitch_shift`
  por segmento, com crossfade e clamp ±1 st). No fingerprint, o tom sai **B
  menor** (B,C♯,D,E,F♯,G,A) e apenas as notas estranhas (B♭, C, G♯) são movidas.
- Sem GPU: Basic Pitch (~36 s para 37 s de áudio), FluidSynth em segundos.
- MIDI intermedio editável; integra com `make`/`cover`/`sing`/`melody`.

**Negativas / custos**

- Engine poly depende de `uv` + Python 3.10 + `tflite-runtime` (numpy<2).
- Transcrição é aproximada (sem tablatura/dedilhado, sem separação por corda).

**Riscos**

- Modelos maiores (MuScriptor) dariam melhor qualidade, mas exigem auth HF e
  mais CPU; ficam como engine futuro plugável.

## Referências

- Basic Pitch — Spotify, Apache-2.0 — github.com/spotify/basic-pitch
- Krumhansl & Schmuckler — "An Algorithm that Selects the Major-Minor Key"
  (Pitch Class Profiles, 1990)
- rubberband / librosa `pitch_shift` — pitch-shift por segmento (F0 por nota)
- MuScriptor — arXiv:2607.08168 (Kyutai/Mirelo, 2026) — github.com/muscriptor/muscriptor
- YourMT3+ — Chang et al., MLSP 2024 — github.com/mimbres/YourMT3
- seed-vc — arXiv:2411.09943 — github.com/Plachtaa/seed-vc
