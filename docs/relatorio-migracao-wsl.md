# Relatório: Diagnóstico e Plano de Migração do Windows para o WSL (Ubuntu)

> **Data**: 2026-09-17  
> **Projeto**: Caine (Voice Studio, SVS & Persona Agents)  
> **Ambiente Analisado**: Windows 11 Host + WSL2 Ubuntu (CUDA 13.3 / NVIDIA GeForce GTX 1650 4GB)

---

## 1. Diagnóstico da Situação Atual

Atualmente, o repositório e os arquivos de trabalho residem fisicamente no sistema de arquivos do Windows (**NTFS**) em:
```text
C:\Users\luann\Documents\GitHub\caine
```
E são acessados pelo WSL através do ponto de montagem de tradução DrvFS / Plan9:
```text
/mnt/c/Users/luann/Documents/GitHub/caine
```

Ao mesmo tempo, **todos os motores de execução, compiladores e bibliotecas pesadas de IA vivem dentro do WSL**:
- **SBCL 2.x** (Common Lisp)
- **CUDA 13.3 / PyTorch** (GPU Turing GTX 1650 via passthrough de driver)
- **FFmpeg / FFprobe**
- **FluidSynth** e SoundFont (`/usr/share/sounds/sf2/FluidR3_GM.sf2`)
- **Python 3 / venvs**

O comando de diagnóstico `./agent/voice/caine-voice doctor` confirma que os binários de sistema estão 100% no Linux e que o diretório padrão de ferramentas (`VOICE_TOOLS_HOME`) aponta para:
```text
/home/luann/voice-tools/  (dentro do WSL)
```

---

## 2. Inventário: O que está no Windows e o que Deve Mover

| Item no Windows (`C:\...`) | Destino no WSL (`/home/luann/...`) | Crítico? | Por que Mover? |
| :--- | :--- | :---: | :--- |
| **Repositório Git `caine/`**<br>`C:\Users\luann\Documents\GitHub\caine` | `/home/luann/caine/` | **Sim** | **I/O e Git**: Ler/gravar em `/mnt/c/` tem um gargalo severo de velocidade (5x a 10x mais lento). Causa conflitos de `.git/index`, avisos de CRLF/LF e perda de permissões `+x`. |
| **Arquivo de Segredos `.env`**<br>`C:\Users\luann\Documents\GitHub\caine\.env` | `/home/luann/caine/.env` | **Sim** | Contém a chave `NVIDIA_API_KEY` (arquivo ignorado pelo Git). Sem ele no WSL, a CLI `caine-nim` e a geração de letras por LLM falham. |
| **Áudio Base `out/melodia-afinada.mp3`**<br>`C:\...\caine\out\melodia-afinada.mp3` (10.8 MB) | `/home/luann/caine/out/melodia-afinada.mp3` | **Sim** | É o áudio gravado que serve de base para o pipeline de transcrição AMT (`Basic Pitch`/`pyin`), afinação e canto das personas. |
| **Configuração de Git (`user.name` / `user.email`)**<br>Configurado no Windows | `git config --global` no WSL | **Recomendado** | O Git dentro do WSL ainda não possui identidade configurada, gerando avisos ou bloqueios em commits direto pelo terminal Linux. |
| **Chaves SSH (`C:\Users\luann\.ssh\`)** | `/home/luann/.ssh/` | **Opcional** | Permite fazer `git push` e `git pull` direto pelo terminal do WSL sem pedir credenciais a cada operação. |
| **Arquivos corrompidos no Windows (`AUSENTE; ...`)** | **DESCARTAR (NÃO MOVER)** | **Não** | Resíduos vazios (0 bytes) gerados acidentalmente por escape de shell no Windows. |

---

## 3. Por que a Migração para o Sistema de Arquivos Nativo do WSL (`ext4`) é Essencial?

### A. Performance Crítica de IA e Aprendizado Profundo (SVS / T2M)
- Os motores do **ADR 007** ([DiffSinger](https://github.com/openvpi/DiffSinger), [ACE-Step](https://github.com/coloth/ccstep) e [CosyVoice2](https://github.com/FunAudioLLM/CosyVoice)) carregam centenas de megabytes de pesos de tensores e arquivos de áudio temporários a cada inferência.
- No DrvFS (`/mnt/c/`), o Windows intercepta cada chamada `open()` e `read()` via rede interna 9P, causando travamentos e alto uso de CPU.
- No `ext4` nativo (`/home/luann/`), a leitura direta em disco NVMe alcança a velocidade máxima do hardware.

### B. Ambientes Virtuais Python (`.venv`) Estáveis
- O comando `caine-voice install <tool>` cria ambientes virtuais em `~/voice-tools/<id>/.venv/`.
- No Windows/DrvFS, criar `venv` gera centenas de links simbólicos e scripts que frequentemente corrompem permissões POSIX. No WSL nativo, a criação via `uv` ou `python3 -m venv` é instantânea e 100% compatível.

### C. Fim dos Conflitos de `.git/index` e Quebras de Linha (CRLF vs LF)
- O Windows Git converte `LF` para `CRLF` silenciosamente. Scripts de shell como `agent/voice/caine-voice` e arquivos Lisp quebram no Linux se contiverem `\r\n` (CRLF).
- Mantendo o código diretamente em `/home/luann/caine`, o Git opera exclusivamente em formato UNIX (LF), eliminando problemas no índice.

---

## 4. Plano de Ação: Passo a Passo para Migrar

Você pode executar a migração em menos de 2 minutos pelo terminal do WSL:

### Passo 1: Clonar o Repositório Diretamente no WSL
Abra o terminal do WSL (Ubuntu) e execute:
```bash
cd ~
git clone https://github.com/lu4nn3ry/caine.git caine
cd ~/caine
```

### Passo 2: Copiar os Arquivos Locais (Untracked) do Windows
Copie o `.env` e o áudio da pasta do Windows para a nova pasta no WSL:
```bash
# Copia o .env (com sua NVIDIA_API_KEY)
cp /mnt/c/Users/luann/Documents/GitHub/caine/.env ~/caine/.env

# Garante que a pasta out existe e copia o áudio gravado
mkdir -p ~/caine/out
cp /mnt/c/Users/luann/Documents/GitHub/caine/out/melodia-afinada.mp3 ~/caine/out/
```

### Passo 3: Configurar a Identidade do Git no WSL
```bash
git config --global user.name "Luan Nery"
git config --global user.email "luannery@live.com"
git config --global core.autocrlf input
```

### Passo 4: (Opcional) Copiar Chaves SSH
Se você utiliza chaves SSH para o GitHub:
```bash
mkdir -p ~/.ssh
cp -r /mnt/c/Users/luann/.ssh/* ~/.ssh/
chmod 700 ~/.ssh
chmod 600 ~/.ssh/* 2>/dev/null || true
```

### Passo 5: Validar a Execução Nativa
Execute a suíte de testes dentro do novo diretório nativo:
```bash
cd ~/caine
sbcl --script tests/run-tests.lisp
./agent/voice/caine-voice doctor
./agent/voice/caine-voice list
```

---

## 5. Como Continuar Trabalhando no Windows (VS Code / Antigravity)

Você não precisa abrir mão das suas ferramentas visuais no Windows:

1. **Acessar os arquivos pelo Windows Explorer**:
   Basta digitar na barra de endereços do Explorer:
   ```text
   \\wsl$\Ubuntu\home\luann\caine
   ```
2. **Abrir no VS Code**:
   Dentro do terminal do WSL, na pasta `~/caine`, rode:
   ```bash
   code .
   ```
   O VS Code abre via extensão **WSL Remote**, rodando a interface gráfica no Windows, mas mantendo a compilação, o terminal e os discos rodando 100% no Linux.

