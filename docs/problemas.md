# Problemas Atuais e Status de Resolução

> Última atualização: 2026-09-17 — Sessão de trabalho Caine: correção de bugs, suite de testes e personas de artistas (ADR 006).

## ✅ Resolvido em Common Lisp

### 1. `lyrics write` quebrava com `The value "ão" is not of type LIST` e outros erros de tipo
- **Status: TOTALMENTE CORRIGIDO e validado por testes unitários e CLI.**
- **Causas identificadas e corrigidas em `agent/voice/lyrics.lisp`**:
  1. `limpar-acentos`: Usava `(dolist (c s) ...)` onde `s` era uma string `"ão"`. Substituído por `(loop for c across s do ...)`.
  2. `limpar-u-silencioso`: No início da palavra (`i = 0`), `prev` era `nil`, e `(member prev '(#\q #\g) :test #'char-equal)` quebrava com `The value NIL is not of type CHARACTER` para palavras como *"uma"*. Adicionadas salvaguardas para `prev` e `nxt`.
  3. `gerar-letra`: Acesso a `*estruturas-por-estilo*` usava `cdr` em vez de `second`, atribuindo uma lista de seções à tag de seção.
  4. `*g2p-letras*` e `*g2p-digrafos*`: Tabela de fonemas foi convertida para alist de dotted pairs, evitando erros de tipo com `assoc`.
- **Validação**: `wsl sbcl --script tests/run-tests.lisp` (13 testes, 47 asserções OK, 0 falhas).

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
  - `tests/test-artists.lisp`: Testes de catálogo, prompts e personas dos artistas.
  - `tests/run-tests.lisp`: Executor direto via `sbcl --script tests/run-tests.lisp` (código de saída 0 em sucesso, 1 em falha).

### 5. Personas de Artistas e Tools do NIM ([ADR 006](docs/adr/006-artists-as-singers.md))
- **Status: IMPLEMENTADO e integrado.**
- `agent/voice/artists.lisp`: Catálogo dos 4 artistas (`caine`, `bubble`, `ragatha`, `scratch`), integrando suas personas, descrições, registros vocais e estilos.
- Subcomandos adicionados ao CLI:
  - `caine-voice artists list`: Lista os artistas com seus registros e descrições.
  - `caine-voice artists write --artist <id> --theme <tema> --out <f.lyrics>`: Gera a letra com a persona do artista.
- Registro de tools em `agent/nim/tools.lisp`:
  - `write_lyrics`: Gera letra estruturada aceitando parâmetro opcional de artista.
  - `edit_lyrics`: Aplica transformações locais ou instrucionais a uma letra existente.

---

## ⏳ Próximos Passos (Exigem Decisão / Dependências Externas)

### 3. "Cantar like Vocaloid" (Síntese Neural de Voz)
- A infraestrutura de partituras (`.lyrics`, `.mid`, `.txt` DiffSinger, OpenUtau e X-SAMPA) está 100% pronta em Lisp.
- A renderização final do áudio cantado dependerá da escolha e instalação do motor neural no sistema (DiffSinger com voicebanks ou OpenUtau, aproveitando a GPU GTX 1650 4GB).
- Transcrição do áudio real `out/melodia-afinada.mp3` para MIDI dependerá da instalação do ambiente Python (`caine-voice install midi`).

### 6. Governança e Repositório
- `.env` e arquivos temporários de zero bytes mantidos intactos.
- `docs/adr/006-artists-as-singers.md` pronto para transição de "Proposto" para "Aceito".