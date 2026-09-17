# ADR 002 — CLI NVIDIA NIM com tool calling para a IA Caine

- **Status**: Aceito
- **Data**: 2026-09-17
- **Decisores**: lu4nn3ry
- **Relacionado**: `docs/adr/001-state-of-art-2026.md`, `agent/nim/`

## Contexto

O agente Caine (daemon `GreenGROUNDS`, em Common Lisp) precisa de um backend de
LLM que possa **chamar ferramentas**. O endpoint escolhido é a API oficial
**NVIDIA NIM** (`https://integrate.api.nvidia.com/v1`), compatível com o formato
OpenAI (chat completions + `tools`/`tool_calls`).

Requisitos:

1. Ser um **CLI** invocável pela IA (e por humanos).
2. Suportar **tool calling** (function calling) num loop agêntico.
3. Suportar **API key** (env var + arquivo, com permissão restrita).
4. Ter **persistência** de configuração e de sessões de conversa.

O repo `caine` é Common Lisp; a decisão foi manter a linguagem.

## Decisão

Implementar o sistema ASDF **`caine-nim`** em `agent/nim/`, com:

- **Zero dependências externas** de biblioteca: JSON próprio (`json.lisp`) e HTTP
  via `curl` (`http.lisp`), para não exigir Quicklisp.
- **Config persistente** em `~/.caine/nim/config.json`.
- **API key** resolvida na ordem: `NVIDIA_API_KEY` → `NIM_API_KEY` → arquivo
  `~/.caine/nim/key` (chmod 600).
- **Sessões** persistidas em `~/.caine/nim/sessions/<id>.json`.
- **Registro de ferramentas** extensível, com tools built-in de arquivos, shell
  e HTTP.
- **Loop de tool calling** limitado por `max_tool_iterations` para evitar
  execução infinita.

O CLI expõe: `ask`, `chat`, `repl`, `key`, `config`, `models`, `sessions`,
`tools`.

## Consequências

**Positivas**

- Sem dependências → carrega só com SBCL + curl.
- Chave fora do código e com permissão restrita.
- Histórico replayável e auditável em JSON.

**Negativas / custos**

- Parser/encoder JSON próprios exigem manutenção e testes.
- HTTP via `curl` (processo externo) em vez de sockets nativos.

**Riscos**

- A tool `run_shell` executa comandos arbitrários; mitigada por flag de config
  `allow_shell` e por ser ferramenta local explícita.
- Formato JSON de tool calls é o da OpenAI; ajustes do NIM podem exigir
  adaptação.

## Referências

- NVIDIA NIM API — https://integrate.api.nvidia.com/v1
- OpenAI-compatible tool calling (formato `tools`/`tool_calls`)
