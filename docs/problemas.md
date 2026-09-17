# Problemas Atuais e Status de Resolução

> Última atualização: 2026-09-17 — Sessão de trabalho Caine: pipeline "produtor" ADR 006 concluído, suite de testes expandida e NIM integrado.

## ✅ Resolvido em Common Lisp

### 1. `lyrics write` quebrava com `The value "ão" is not of type LIST` e outros erros de tipo
- **Status: TOTALMENTE CORRIGIDO e validado por testes unitários e CLI.**
- **Causas identificadas e corrigidas em `agent/voice/lyrics.lisp`**:
  1. `limpar-acentos`: Usava `(dolist (c s) ...)` onde `s` era uma string `"ão"`. Substituído por `(loop for c across s do ...)`.
  2. `limpar-u-silencioso`: No início da palavra (`i = 0`), `prev` era `nil`, e `(member prev '(#\q #\g) :test #'char-equal)` quebrava com `The value NIL is not of type CHARACTER` para palavras como *"uma"*. Adicionadas salvaguardas para `prev` e `nxt`.
  3. `gerar-letra`: Acesso a `*estruturas-por-estilo*` usava `cdr` em vez de `second`, atribuindo uma lista de seções à tag de seção.
  4. `*g2p-letras*` e `*g2p-digrafos*`: Tabela de fonemas foi convertida para alist de dotted pairs, evitando erros de tipo com `assoc`.
- **Validação**: `wsl sbcl --script tests/run-tests.lisp` (17 testes, 63 asserções OK, 0 falhas).

### 2. `lyrics align` sem arquivo MIDI (Destravado via Mock)
- **Status: RESOLVIDO em pasta `/mock`.**
- Criada a pasta `/mock` contendo:
  - `mock/melody.lisp`: Módulo gerador de melodias sintéticas e estruturas de teste em Lisp puro.
  - `mock/melodia-exemplo.mid`: Arquivo Standard MIDI File (SMF formato 0) gerado em Lisp puro para testes offline.
  - `mock/exemplo.lyrics`: Letra canônica de exemplo para alinhamento.
- Adicionado subcomando `caine-voice midi mock [--out <f.mid>] [--bpm 120]` para gerar arquivos MIDI mock sob demanda.
- Corrigido o desbalanceamento de parênteses na função `ler-smf` de `agent/voice/midi.lisp`.
- Pipeline de `lyrics align` testado com sucesso para DiffSinger e OpenUtau.

### 4. Quicklisp não instalado / Testes bloqueados
- **Status: RESOLVIDO com micro-framework de testes 100% autossuficiente.**
- Implementado em `tests/`:
  - `tests/framework.lisp`: Macros `deftest`, `assert-true`, `assert-false`, `assert-equal`, `assert-string=`, contador de asserções e relatório.
  - `tests/test-lyrics.lisp`: Testes de remoção de acentos, rimas, silabificação, linter métrico e G2P.
  - `tests/test-midi.lisp`: Testes de escrita/leitura binária de MIDI e alinhamento sílaba→nota.
  - `tests/test-artists.lisp`: Testes de catálogo, prompts, diretórios de estúdio, alinhamento por artista e pipelines individuais/álbum.
  - `tests/run-tests.lisp`: Executor direto via `sbcl --script tests/run-tests.lisp` (código de saída 0 em sucesso, 1 em falha).

### 5. Pipeline "Produtor", Personas de Artistas e Tools do NIM ([ADR 006](docs/adr/006-artists-as-singers.md))
- **Status: TOTALMENTE IMPLEMENTADO, TESTADO E INTEGRADO.**
- **Módulo `agent/voice/artists.lisp`**:
  - Catálogo de personas: **Caine**, **Bubble**, **Ragatha** e **Scratch**.
  - Funções de estúdio e alinhamento: `artista-outdir`, `artista-voz-ref`, `alinhar-versao-artista`.
  - Motores de produção: `produzir-versao-artista` e `produzir-album-artistas` (com suporte a engines `:diffsinger`, `:openutau`, `:seedvc` e `:instrumental`, além de parâmetro `--mid` compartilhado).
  - Limpeza de artefatos: typo `~a p` corrigido e resíduos de rascunho removidos.
- **Exportações em `agent/voice/package.lisp`**:
  - `artista-outdir`, `artista-voz-ref`, `alinhar-versao-artista`, `produzir-versao-artista`, `produzir-album-artistas`.
- **Subcomandos de CLI em `agent/voice/cli.lisp`**:
  - `caine-voice artists list`: Lista artistas, registros, estilos e descrições.
  - `caine-voice artists prompt --artist <id>`: Imprime o system prompt com a persona para injeção em LLMs.
  - `caine-voice artists write --artist <id> --theme <tema> --out <f.lyrics>`: Gera letra estruturada para a persona.
  - `caine-voice artists sing --artist <id> --melody <audio> --out <wav> [--mid] [--engine ...]`: Produz a versão de uma faixa para um artista.
  - `caine-voice artists album --melody <audio> [--out <dir>] [--mid] [--engine ...]`: Gera as 4 versões do álbum em batch.
- **Integração com NVIDIA NIM em `agent/nim/tools.lisp`**:
  - Tool `write_lyrics` atualizada: quando a API key NIM está presente, injeta o system prompt retornado por `artists prompt` no modelo LLM, salvando a letra com a persona do artista; caso contrário, usa o fallback local de templates.
  - Tool `edit_lyrics` registrada para transformações instrucionais em letras.

### 6. Engines 2026 e Passo 3/3 de Render DiffSinger ([ADR 007](docs/adr/007-engines-2026.md))
- **Status: TOTALMENTE IMPLEMENTADO E TESTADO.**
- **Novas Engines Registradas em `agent/voice/config.lisp`**:
  - `diffsinger`: Atualizado para `diffsinger-utau` (CLI headless via PyPI, inferência SVS via PyTorch/CUDA).
  - `ace-step`: Registrado ACE-Step v1.5 (T2M foundation model, <4GB VRAM para GTX 1650, cover e arranjo com letra).
  - `cosyvoice`: Registrado CosyVoice2-0.5B (TTS e clonagem zero-shot multilíngue, <4GB VRAM).
- **Executores de Ferramenta em `agent/voice/tools.lisp`**:
  - `diffsinger-bin`: Detecção do executável `diffsinger-utau` no venv ou no PATH.
  - `render-diffsinger`: Executa `diffsinger-utau render <ds> -o <wav> --speedup 10 --device cuda` com suporte a `--speaker-folder` (voicebank) e `--vocoder`.
  - `generate-acestep`: Execução headless de ACE-Step v1.5 com condicionamento de letra e áudio de referência.
  - `tts-cosyvoice`: Síntese de fala/clonagem zero-shot cross-lingual para personas.
- **Integração no Produtor de Artistas em `agent/voice/artists.lisp`**:
  - `artista-voicebank`: Localização do modelo acústico do artista (`out/rg/<id>/voicebank/`, `voice-tools/DiffSinger/voicebanks/<id>/` ou `DIFFSINGER_VOICEBANK`).
  - `produzir-versao-artista` sob `:diffsinger`: Fecha o passo 3/3 da arquitetura. Quando `diffsinger-utau` e o voicebank estão presentes, sintetiza diretamente o vocal e masteriza para o áudio de saída. Na ausência do modelo neural, gera a partitura `.ds` e fornece instruções claras de instalação sem quebrar o fluxo nem os testes.
- **Pipelines e CLI em `agent/voice/pipeline.lisp` e `agent/voice/cli.lisp`**:
  - `fazer-cover`: Adicionado suporte ao parâmetro `:engine :acestep` além de `:seedvc`.
  - `caine-voice cover`: Subcomando CLI integrado com `--engine seedvc|acestep`, `--prompt`, `--lyrics`.
  - `caine-voice make`: Subcomando CLI integrado para mixagem e masterização de vocal + instrumental.
- **Suíte de Testes Expandida**:
  - Criado `tests/test-tools.lisp`.
  - Total de 20 testes e 81 asserções com 100% de aprovação via `wsl sbcl --script tests/run-tests.lisp`.

---

## ⏳ Próximos Passos (Exigem Decisão / Dependências Externas)

### 1. Download de Pesos Neurais em GPU (<4GB VRAM)
- Para síntese neural em tempo real com DiffSinger: executar `caine-voice install diffsinger` e baixar voicebank em `out/rg/<id>/voicebank/` ou `voice-tools/DiffSinger/voicebank/`.
- Para geração completa com ACE-Step: clonar repositório e baixar checkpoint FP16 compatível com 4GB VRAM via `caine-voice install ace-step`.
- Para TTS CosyVoice2: `caine-voice install cosyvoice`.

### 2. Governança e Repositório
- `.env` e arquivos temporários de zero bytes mantidos intactos.
- `docs/adr/007-engines-2026.md` aprovado e marcado como **Aceito**.