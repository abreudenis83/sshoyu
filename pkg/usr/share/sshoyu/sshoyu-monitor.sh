#!/bin/bash

CONFIG_FILE="/etc/sshoyu/sshoyu.conf"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

CADDYFILE_PATH="${CADDYFILE_PATH:-/etc/caddy/Caddyfile}"
LOCK_FILE_DIR="${LOCK_FILE_DIR:-/tmp}"
INTERVAL=15

cleanup_tunnel() {
    local full_domain=$1
    local lock_file=$2
    local temp_file="${LOCK_FILE_DIR}/Caddyfile.tmp"

    (
        flock 9
        sudo sed "/^${full_domain} {/,/^}/d" "$CADDYFILE_PATH" | sudo tee "$temp_file" > /dev/null
        sudo mv "$temp_file" "$CADDYFILE_PATH"
        if ! sudo systemctl reload caddy; then
            echo "$(date -Iseconds) Warning: caddy reload falhou após remover ${full_domain}" >&2
        fi
    ) 9>"${LOCK_FILE_DIR}/sshoyu.caddy.lock"
    rm -f "$lock_file"

    echo "$(date -Iseconds) Túnel encerrado: ${full_domain}"
}

kill_orphan_processes() {
    local lock_pids=()

    for lock_file in "${LOCK_FILE_DIR}"/sshoyu_tunnel_*.lock; do
        [ -f "$lock_file" ] || continue
        local pid
        pid=$(sed -n '1p' "$lock_file" 2>/dev/null || true)
        [ -n "$pid" ] && lock_pids+=("$pid")
    done

    for pid in $(pgrep -f sshoyu_cli.sh 2>/dev/null); do
        local found=false
        for lock_pid in "${lock_pids[@]}"; do
            [ "$lock_pid" = "$pid" ] && found=true && break
        done
        if [ "$found" = false ]; then
            kill "$pid" 2>/dev/null || true
            echo "$(date -Iseconds) Processo órfão encerrado: PID $pid"
        fi
    done
}

echo "$(date -Iseconds) sshoyu-monitor iniciado"

while true; do
    # Limpa lock files cujos processos morreram
    for lock_file in "${LOCK_FILE_DIR}"/sshoyu_tunnel_*.lock; do
        [ -f "$lock_file" ] || continue
        pid=$(sed -n '1p' "$lock_file" 2>/dev/null || true)
        if [ -z "$pid" ] || [ ! -d "/proc/$pid" ]; then
            full_domain=$(sed -n '2p' "$lock_file" 2>/dev/null || true)
            # fallback para lock files antigos (apenas PID, sem domínio)
            if [ -z "$full_domain" ]; then
                subdomain=$(basename "$lock_file" | sed 's/sshoyu_tunnel_//;s/\.lock//')
                full_domain="${subdomain}.${SSH_HOST}"
            fi
            cleanup_tunnel "$full_domain" "$lock_file"
        fi
    done

    # Mata processos sshoyu_cli.sh sem lock file correspondente
    kill_orphan_processes

    sleep "$INTERVAL"
done
