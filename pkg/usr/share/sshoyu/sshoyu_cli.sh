#!/bin/bash

# Custom CLI script for SSH login
# This script runs as the user's shell when they connect via SSH

CONFIG_FILE="/etc/sshoyu/sshoyu.conf"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

CADDYFILE_PATH="${CADDYFILE_PATH:-/etc/caddy/Caddyfile}"
LOCK_FILE_DIR="${LOCK_FILE_DIR:-/tmp}"

SSH_PARAM="${SSH_ORIGINAL_COMMAND:-$2}"
total_args=$(echo $SSH_PARAM | wc -w)

if [ $total_args -eq 1 ]; then
    if [ "$SSH_PARAM" == 'caddy' ]; then
        cat "$CADDYFILE_PATH"
    else
        echo 'Command not found'
    fi
    exit 0
elif [ $total_args -ge 2 ]; then
    export SUBDOMAIN=$(echo $SSH_PARAM | cut -d' ' -f1)
    export LOCALPORT=$(echo $SSH_PARAM | cut -d' ' -f2)
else
    echo "Error: Missing required parameters (subdomain and/or remoteport)"
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
add_reverse_proxy_block() {
    local subdomain=$1
    local domain_base=$2
    local remoteport=$3

    local block="${subdomain}.${domain_base} {
    reverse_proxy 127.0.0.1:${remoteport}
}"

    echo "" | sudo tee -a "$CADDYFILE_PATH" > /dev/null
    echo "$block" | sudo tee -a "$CADDYFILE_PATH" > /dev/null
    sudo systemctl reload caddy
}

# Função para remover bloco reverse_proxy do Caddyfile
remove_reverse_proxy_block() {
    local subdomain=$1
    local domain_base=$2
    local temp_file="${LOCK_FILE_DIR}/Caddyfile.tmp"

    sudo sed "/^${subdomain}\.${domain_base} {/,/^}/d" "$CADDYFILE_PATH" | sudo tee "$temp_file" > /dev/null
    sudo mv "$temp_file" "$CADDYFILE_PATH"
    sudo systemctl reload caddy

    echo "✓ Reverse proxy block removed for ${subdomain}.${domain_base}"
}

# Função de limpeza ao sair
cleanup() {
    if [ "$block_created" = true ]; then
        echo ""
        echo "Closing tunnel... Removing reverse proxy block..."
        remove_reverse_proxy_block "$subdomain" "$domain_base"
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

if check_subdomain_exists "$subdomain" "$domain_base"; then
    echo "ERROR: Subdomain ALREADY EXISTS in Caddyfile"
    exit 1
else
    echo "Status: Subdomain does not exist. Creating reverse proxy block..."
    add_reverse_proxy_block "$subdomain" "$domain_base" "$remoteport"
    block_created=true

    echo "$$" > "$lock_file"

    echo "✓ Reverse proxy block created successfully!"
    echo ""
    echo "=== Tunnel Information ==="
    echo "Access URL: https://${subdomain}.${domain_base}"
    echo "Remote Port: $remoteport"
    echo "Domain: ${subdomain}.${domain_base}"
    echo "=========================="
fi

echo ""
echo "Tunnel is now active. Press Ctrl+C to close."
echo ""

# Bloqueia até o cliente SSH desconectar (stdin fecha → EOF) ou receber sinal
while true; do
    IFS= read -r -t 10 _
    [ $? -eq 1 ] && break  # EOF = cliente desconectou
done
