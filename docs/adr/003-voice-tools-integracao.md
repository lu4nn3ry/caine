# ADR 003 — Integração das ferramentas de voz natural (caine-voice)

- **Status**: Aceito
- **Data**: 2026-09-17
- **Decisores**: lu4nn3ry
- **Relacionado**: ADR 001, ADR 002, `agent/voice/`, `TODO.md`

## Contexto

Para o Caine ser um editor/produtor de música completo, ele precisa **gerar e
transformar voz** (canto e fala) e combiná-la com os áudios do usuário. Em 2026 o
estado da arte local está em ferramentas Python (ver ADR 001 §6). O Caine é
Common Lisp.

Ferramentas baixadas em `~/voice-tools/` (clones rasos):

| Ferramenta | Tipo | Licença | Papel |
| ---------- | ---- | ------- | ----- |
| GPT-SoVITS | TTS/clone few-shot | MIT | fala/canto a partir de texto + 5s de voz |
| seed-vc | conversão de voz zero-shot | GPL-3.0 | cover/canto preservando melodia |
| Applio | voice conversion (RVC) | MIT | treino/inferência estilo RVC |
| DiffSinger | SVS | Apache-2.0 | MIDI + letra → canto |
| OpenUtau | SVS | MIT | plataforma de síntese cantada |
| Demucs | separação de stems | MIT | vocal/instrumental |

## Decisão

Criar o sistema ASDF **`caine-voice`** em `agent/voice/`, que **orquestra** as
ferramentas externas em vez de reimplementá-las:

- Cada ferramenta roda no seu **venv isolado** (`<dir>/.venv`), criado por
  `caine-voice install <id>` — nada é instalado implicitamente.
- A comunicação é por **subprocesso** (`uiop:run-program`) e HTTP local
  (`curl`) para a API do GPT-SoVITS.
- **ffmpeg** faz mixagem, conversão (WAV 48k/24bit) e masterização (LUFS).
- Pipelines prontos: `make` (vocal + instrumental → master) e `cover`
  (separa → converte → remixa).
- Config por `CAINE_VOICE_HOME` (padrão `~/voice-tools/`).

## Consequências

**Positivas**

- Aproveita o melhor de 2026 sem reescrever modelos em Lisp.
- Isolamento de dependências (venv por ferramenta) e licenças separadas.
- Pipeline testável já sem GPU (ffmpeg) e extensível para canto.

**Negativas / custos**

- Dependências Python pesadas (torch) e sem GPU ficam lentas.
- Modelos precisam ser baixados/treinados à parte.

**Riscos**

- **seed-vc é GPL-3.0**: por ser executado como processo separado (não linkado
  ao binário do Caine), mantém-se isolado; não embutir seu código no Caine.
- Fallback: se uma ferramenta faltar, o CLI falha com instrução de instalação.

## Referências

- Ver ADR 001 §6 (estado da arte de voz 2026) e os READMEs em `~/voice-tools/`.
