# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**SShoyu** (SSH local publisher) is a two-script Bash system that exposes local services publicly via SSH reverse tunnels routed through a Caddy reverse proxy. The server side is distributed as a Debian package (`sshoyu-server`).

## Usage

```bash
# On the local machine — creates a reverse tunnel and registers a subdomain
./ssh_client.sh <subdomain> <localport>

# Example: expose local port 8000 as files.<domain>
./ssh_client.sh files 8000
```

## Architecture

Two scripts with clearly separated roles:

### `ssh_client.sh` (runs locally)
1. Connects to the server to read `/etc/caddy/Caddyfile` and find the next available port (starting at 3000).
2. Opens an SSH reverse tunnel: `ssh -R <remoteport>:localhost:<localport>`.
3. The SSH connection invokes `sshoyu_cli.sh` on the server as the forced shell command.

Hardcoded server config: host `denis.ddns.net`, port `2200`, user `sshoyu`, key `~/.ssh/id_rsa`.

### `sshoyu_cli.sh` (runs on the server as forced SSH command)
1. Sources `/etc/sshoyu/sshoyu.conf` for all configuration on startup.
2. Receives `<subdomain> <remoteport>` as arguments.
3. Validates subdomain uniqueness, then appends a reverse proxy block to the Caddyfile.
4. Reloads Caddy via `sudo systemctl reload caddy`.
5. Holds the tunnel open with a `sleep 1` loop.
6. On SIGINT/SIGTERM/SIGHUP/EXIT: removes the proxy block, reloads Caddy, deletes the lock file.

Lock files live at `$LOCK_FILE_DIR/sshoyu_tunnel_<subdomain>.lock` (default: `/tmp`).

### Data flow
```
local service → ssh_client.sh → SSH reverse tunnel → sshoyu_cli.sh → Caddyfile → Caddy proxy → public subdomain
```

## Debian Package (`sshoyu-server`)

### Build

```bash
# Construir o pacote
dpkg-deb --build pkg sshoyu-server_1.0.0_all.deb

# Instalar (dispara o debconf interativo)
sudo dpkg -i sshoyu-server_1.0.0_all.deb

# Remover completamente (inclusive config e usuário)
sudo dpkg --purge sshoyu-server
```

### Package structure

```
debian/          # fontes dos scripts de empacotamento
  control        # metadados do pacote
  templates      # perguntas debconf (ssh_host, ssh_port, ssh_user)
  config         # script de pré-configuração debconf
  postinst       # cria usuário, chave SSH, sudoers, sshoyu.conf
  prerm          # encerra túneis ativos antes da remoção
  postrm         # remove config/usuário no purge

pkg/             # árvore de instalação (entrada do dpkg-deb --build)
  DEBIAN/        # cópia dos scripts acima (gerada manualmente)
  usr/share/sshoyu/sshoyu_cli.sh   # script instalado pelo postinst
```

### What `postinst` does (in order)
1. Lê respostas do debconf (`ssh_host`, `ssh_port`, `ssh_user`)
2. Cria `/etc/sshoyu/sshoyu.conf` com as variáveis de configuração
3. Instala `sshoyu_cli.sh` em `/usr/local/bin/`
4. Cria o usuário de sistema `sshoyu` (com `adduser --system`)
5. Gera par de chaves ed25519 em `/home/sshoyu/.ssh/`
6. Configura `authorized_keys` com o forced command apontando para `sshoyu_cli.sh`
7. Instala `/etc/sudoers.d/sshoyu` com permissões mínimas para o Caddyfile e systemctl
8. Exibe resumo com a chave pública para distribuir aos clientes

### Configuration file

`/etc/sshoyu/sshoyu.conf` (lido via `source` pelo `sshoyu_cli.sh`):

```bash
SSH_HOST=<hostname>
SSH_PORT=2200
SSH_USER=sshoyu
CADDYFILE_PATH=/etc/caddy/Caddyfile
MIN_REMOTE_PORT=3000
LOCK_FILE_DIR=/tmp
```

## Server-side Requirements

- Caddy web server com `/etc/caddy/Caddyfile` já configurado (o primeiro entry define o domínio base)
- `sshoyu` user configurado como forced command via `authorized_keys` (feito pelo postinst)
- `sudo` permissions para editar o Caddyfile e `systemctl reload caddy` (feito pelo postinst via `/etc/sudoers.d/sshoyu`)
