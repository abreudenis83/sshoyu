#!/bin/bash

# Custom CLI script for SSH login
# This script runs as the user's shell when they connect via SSH

CONFIG_FILE="/etc/sshoyu/sshoyu.conf"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

CADDYFILE_PATH="${CADDYFILE_PATH:-/etc/caddy/Caddyfile}"
LOCK_FILE_DIR="${LOCK_FILE_DIR:-/tmp}"

SSH_PARAM="${SSH_ORIGINAL_COMMAND:-}"
read -r ARG1 ARG2 _REST <<< "$SSH_PARAM"

if [ -z "$ARG1" ]; then
    echo "Error: Missing required parameters (subdomain and/or remoteport)"
    exit 1
fi

if [ -z "$ARG2" ]; then
    if [ "$ARG1" = "caddy" ]; then
        cat "$CADDYFILE_PATH"
    else
        echo "Command not found"
    fi
    exit 0
fi

SUBDOMAIN="$ARG1"
LOCALPORT="$ARG2"

# Valida subdomain (rótulo DNS RFC 1035: [a-z0-9] e hifens internos, 1-63 chars)
if ! [[ "$SUBDOMAIN" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]; then
    echo "Error: subdomain inválido (use apenas a-z, 0-9 e hífens internos, até 63 chars)"
    exit 1
fi

# Valida porta remota (1-65535)
if ! [[ "$LOCALPORT" =~ ^[1-9][0-9]{0,4}$ ]] || [ "$LOCALPORT" -gt 65535 ]; then
    echo "Error: porta remota inválida"
    exit 1
fi

# Função para verificar se o subdomínio existe no Caddyfile
check_subdomain_exists() {
    local subdomain=$1
    local domain_base=$2

    if grep -q "^${subdomain}\.${domain_base}" "$CADDYFILE_PATH"; then
        return 0  # Subdomínio existe
    else
        return 1  # Subdomínio não existe
    fi
}

# Função para adicionar bloco reverse_proxy ao Caddyfile
# Retorna 0 em sucesso. Em caso de falha no reload, reverte para o estado anterior.
add_reverse_proxy_block() {
    local subdomain=$1
    local domain_base=$2
    local remoteport=$3
    local backup="${LOCK_FILE_DIR}/sshoyu.bak.$$"

    local block="${subdomain}.${domain_base} {
    reverse_proxy 127.0.0.1:${remoteport}
}"

    cp "$CADDYFILE_PATH" "$backup"
    echo "" | sudo tee -a "$CADDYFILE_PATH" > /dev/null
    echo "$block" | sudo tee -a "$CADDYFILE_PATH" > /dev/null

    if sudo systemctl reload caddy; then
        rm -f "$backup"
        return 0
    fi

    echo "ERROR: caddy reload falhou — revertendo Caddyfile" >&2
    sudo tee "$CADDYFILE_PATH" < "$backup" > /dev/null
    sudo systemctl reload caddy >/dev/null 2>&1 || true
    rm -f "$backup"
    return 1
}

# Função para remover bloco reverse_proxy do Caddyfile
remove_reverse_proxy_block() {
    local subdomain=$1
    local domain_base=$2
    local temp_file="${LOCK_FILE_DIR}/Caddyfile.tmp"

    sudo sed "/^${subdomain}\.${domain_base} {/,/^}/d" "$CADDYFILE_PATH" | sudo tee "$temp_file" > /dev/null
    sudo mv "$temp_file" "$CADDYFILE_PATH"
    if ! sudo systemctl reload caddy; then
        echo "Warning: caddy reload falhou após remover ${subdomain}.${domain_base}" >&2
    fi

    echo "✓ Reverse proxy block removed for ${subdomain}.${domain_base}"
}

# Verifica se uma porta remota já está alocada no Caddyfile
check_port_in_use() {
    local port=$1
    grep -qE "reverse_proxy[[:space:]]+[^[:space:]]+:${port}\b" "$CADDYFILE_PATH"
}

# Lock global para serializar mutações no Caddyfile (add/remove)
acquire_caddy_lock() {
    exec 9>"${LOCK_FILE_DIR}/sshoyu.caddy.lock"
    flock 9
}

release_caddy_lock() {
    flock -u 9
    exec 9>&-
}

# Função de limpeza ao sair
cleanup() {
    if [ "$block_created" = true ]; then
        echo ""
        echo "Closing tunnel... Removing reverse proxy block..."
        acquire_caddy_lock
        remove_reverse_proxy_block "$subdomain" "$domain_base"
        release_caddy_lock
        rm -f "$lock_file"
    fi
    exit 0
}

trap cleanup SIGINT SIGTERM SIGHUP EXIT

subdomain="${SUBDOMAIN:-}"
remoteport="${LOCALPORT:-}"  # Nota: é na verdade a porta remota
block_created=false
lock_file="${LOCK_FILE_DIR}/sshoyu_tunnel_${subdomain}.lock"

if [ -z "$subdomain" ] || [ -z "$remoteport" ]; then
    echo "Error: Missing required parameters (subdomain and/or remoteport)"
    exit 1
fi

domain_base="${SSH_HOST}"

if [ -z "$domain_base" ]; then
    echo "Error: Could not determine domain base from SSH_HOST in ${CONFIG_FILE}"
    exit 1
fi

echo
echo "SSHoyu local publisher"
echo '----------------------------------'
echo "Subdomain......: $subdomain"
echo "Your local port: $remoteport"
echo ""

acquire_caddy_lock

if check_subdomain_exists "$subdomain" "$domain_base"; then
    echo "ERROR: Subdomain ALREADY EXISTS in Caddyfile"
    release_caddy_lock
    exit 1
fi

if check_port_in_use "$remoteport"; then
    echo "ERROR: Remote port ${remoteport} ALREADY IN USE in Caddyfile"
    release_caddy_lock
    exit 1
fi

echo "Status: Subdomain does not exist. Creating reverse proxy block..."
if ! add_reverse_proxy_block "$subdomain" "$domain_base" "$remoteport"; then
    release_caddy_lock
    exit 1
fi
block_created=true

printf "%s\n%s\n" "$$" "${subdomain}.${domain_base}" > "$lock_file"

release_caddy_lock

echo "✓ Reverse proxy block created successfully!"
echo ""
echo "=== Tunnel Information ==="
echo "Access URL: https://${subdomain}.${domain_base}"
echo "Remote Port: $remoteport"
echo "Domain: ${subdomain}.${domain_base}"
echo "=========================="

echo ""
echo "Tunnel is now active. Press Ctrl+C to close."
echo ""

# Bloqueia até o cliente SSH desconectar (stdin fecha → EOF) ou receber sinal
while true; do
    IFS= read -r -t 10 _
    [ $? -eq 1 ] && break  # EOF = cliente desconectou
done
