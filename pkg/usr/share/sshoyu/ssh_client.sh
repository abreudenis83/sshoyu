#!/bin/bash

# SShoyu Client
# Usage: sshoyu <subdomain> <localport>

SSH_HOST="__SSH_HOST__"
SSH_PORT="__SSH_PORT__"
SSH_USER="__SSH_USER__"
SSH_KEY="${SSHOYU_KEY:-$HOME/.ssh/sshoyu_id_ed25519}"

if [ $# -ne 2 ]; then
    echo "Usage: sshoyu <subdomain> <localport>[/<http|https>]"
    echo "Example: sshoyu files 8000"
    echo "         sshoyu pictures 8080/https"
    exit 1
fi

subdomain=$1
port_arg=$2

# Aceita port ou port/protocol
case "$port_arg" in
    */*)
        localport="${port_arg%/*}"
        protocol="${port_arg##*/}"
        ;;
    *)
        localport="$port_arg"
        protocol="http"
        ;;
esac

if ! [[ "$localport" =~ ^[0-9]+$ ]] || [ "$localport" -lt 1 ] || [ "$localport" -gt 65535 ]; then
    echo "Error: Invalid local port. Must be a number between 1 and 65535"
    exit 1
fi

case "$protocol" in
    http|https) ;;
    *)
        echo "Error: protocolo inválido (use http ou https)"
        exit 1
        ;;
esac

echo "[*] Subdomain: $subdomain"
echo "[*] Local Port: $localport ($protocol)"
echo ""

get_next_available_port() {
    local caddyfile_content=$(ssh -p "$SSH_PORT" -i "$SSH_KEY" \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=5 \
        "$SSH_USER@$SSH_HOST" caddy 2>/dev/null)

    if [ -z "$caddyfile_content" ]; then
        echo "3000"
        return
    fi

    local used_ports=$(echo "$caddyfile_content" | grep -oP 'reverse_proxy\s+\S+:\K\d+' | sort -n)

    if [ -z "$used_ports" ]; then
        echo "3000"
        return
    fi

    local next_port=3000
    for port in $used_ports; do
        if [ "$port" -ge 3000 ] && [ "$port" -eq "$next_port" ]; then
            ((next_port++))
        fi
    done

    echo "$next_port"
}

echo "[*] Checking for next available port..."
remoteport=$(get_next_available_port)

if [ -z "$remoteport" ]; then
    echo "Error: Could not determine next available port"
    exit 1
fi

echo "[+] Next available port: $remoteport"
echo ""
echo "[*] Establishing SSH reverse tunnel..."
echo ""

local_ip=$(ip route get 1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1); exit}')
local_ip="${local_ip:-127.0.0.1}"

ssh -p "$SSH_PORT" \
    -i "$SSH_KEY" \
    -R "$remoteport:$local_ip:$localport" \
    -o StrictHostKeyChecking=no \
    -o ExitOnForwardFailure=yes \
    "$SSH_USER@$SSH_HOST" \
    "$subdomain" "$remoteport" "$protocol"
