#!/bin/bash
set -e

CONFIG_FILE="/etc/sshoyu/sshoyu.conf"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

SSH_USER="${SSH_USER:-sshoyu}"
LOCK_FILE_DIR="${LOCK_FILE_DIR:-/tmp}"
AUTH_KEYS="/home/${SSH_USER}/.ssh/authorized_keys"
CLI_SCRIPT="/usr/local/bin/sshoyu_cli.sh"
FORCED_COMMAND="command=\"${CLI_SCRIPT}\",no-X11-forwarding,no-agent-forwarding,no-pty"

usage() {
    echo "Usage:"
    echo "  sshoyu --add-key \"<public-key>\"      Autoriza uma chave de cliente"
    echo "  sshoyu --list-keys                   Lista as chaves autorizadas"
    echo "  sshoyu --remove-key \"<public-key>\"   Remove uma chave de cliente"
    echo "  sshoyu --list-tunnels                Lista os túneis ativos"
    echo "  sshoyu --close-tunnel <subdomain>    Encerra um túnel ativo"
    exit 1
}

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "Error: este comando requer privilégios de root (use sudo)" >&2
        exit 1
    fi
}

validate_key() {
    local key="$1"
    if ! echo "$key" | grep -qE '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521) [A-Za-z0-9+/]+=* '; then
        echo "Error: formato de chave pública inválido" >&2
        exit 1
    fi
}

case "$1" in
    --add-key)
        require_root
        PUB_KEY="$2"
        [ -z "$PUB_KEY" ] && { echo "Error: chave pública não informada" >&2; usage; }
        validate_key "$PUB_KEY"

        if grep -qF "$PUB_KEY" "$AUTH_KEYS" 2>/dev/null; then
            echo "Aviso: esta chave já está em ${AUTH_KEYS}"
            exit 0
        fi

        echo "${FORCED_COMMAND} ${PUB_KEY}" >> "$AUTH_KEYS"
        echo "✓ Chave adicionada em ${AUTH_KEYS}"
        ;;

    --list-keys)
        require_root
        if [ ! -f "$AUTH_KEYS" ]; then
            echo "Nenhuma chave encontrada em ${AUTH_KEYS}"
            exit 0
        fi
        echo "Chaves autorizadas em ${AUTH_KEYS}:"
        echo ""
        n=1
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            key_part=$(echo "$line" | grep -oE '(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp[0-9]+) [A-Za-z0-9+/]+=* .*' || echo "$line")
            echo "  [$n] $key_part"
            ((n++))
        done < "$AUTH_KEYS"
        ;;

    --remove-key)
        require_root
        PUB_KEY="$2"
        [ -z "$PUB_KEY" ] && { echo "Error: chave pública não informada" >&2; usage; }

        if ! grep -qF "$PUB_KEY" "$AUTH_KEYS" 2>/dev/null; then
            echo "Error: chave não encontrada em ${AUTH_KEYS}" >&2
            exit 1
        fi

        grep -vF "$PUB_KEY" "$AUTH_KEYS" > "${AUTH_KEYS}.tmp"
        mv "${AUTH_KEYS}.tmp" "$AUTH_KEYS"
        echo "✓ Chave removida de ${AUTH_KEYS}"
        ;;

    --list-tunnels)
        require_root
        found=false
        for lock_file in "${LOCK_FILE_DIR}"/sshoyu_tunnel_*.lock; do
            [ -f "$lock_file" ] || continue
            found=true
            pid=$(sed -n '1p' "$lock_file" 2>/dev/null)
            full_domain=$(sed -n '2p' "$lock_file" 2>/dev/null)
            subdomain=$(basename "$lock_file" | sed 's/sshoyu_tunnel_//;s/\.lock//')
            if [ -d "/proc/$pid" ]; then
                status="ativo"
            else
                status="morto (aguardando limpeza)"
            fi
            echo "  ${subdomain} → ${full_domain:-?} (PID ${pid}, ${status})"
        done
        if [ "$found" = false ]; then
            echo "Nenhum túnel ativo no momento."
        fi
        ;;

    --close-tunnel)
        require_root
        SUBDOMAIN="$2"
        [ -z "$SUBDOMAIN" ] && { echo "Error: subdomínio não informado" >&2; usage; }

        lock_file="${LOCK_FILE_DIR}/sshoyu_tunnel_${SUBDOMAIN}.lock"
        if [ ! -f "$lock_file" ]; then
            echo "Error: nenhum túnel ativo para '${SUBDOMAIN}'" >&2
            exit 1
        fi

        pid=$(sed -n '1p' "$lock_file" 2>/dev/null)
        full_domain=$(sed -n '2p' "$lock_file" 2>/dev/null)

        if [ -d "/proc/$pid" ]; then
            kill "$pid"
            echo "✓ Túnel '${full_domain:-$SUBDOMAIN}' encerrado (PID ${pid})"
        else
            echo "Aviso: processo ${pid} já não existe, limpando lock file..."
            rm -f "$lock_file"
        fi
        ;;

    *)
        usage
        ;;
esac
