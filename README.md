# SShoyu

![alt text](<ChatGPT Image Apr 22, 2026, 02_43_07 PM.png>)

SShoyu (SSH local publisher) exposes local services to the internet via SSH reverse tunnels, automatically managing [Caddy](https://caddyserver.com/) reverse proxy subdomains on the server side.

```
local service → sshoyu → SSH reverse tunnel → Caddy → public subdomain
```

## How it works

1. The client runs `sshoyu <subdomain> <localport>`
2. The client queries the server for the next available tunnel port (3000+)
3. An SSH reverse tunnel is opened: `-R <remoteport>:<local-ip>:<localport>`
4. The server registers a new reverse proxy block in the Caddyfile: `<subdomain>.<server-host> → 127.0.0.1:<remoteport>`
5. Caddy is reloaded — the subdomain is immediately live
6. On disconnect (Ctrl+C or connection drop), the Caddyfile block is removed and Caddy is reloaded again

---

## Server setup

### Requirements

- Debian/Ubuntu server
- [Caddy](https://caddyserver.com/docs/install) installed and running
- A wildcard DNS record pointing `*.<your-domain>` to your server's IP

### Install

```bash
# Download the latest release
wget https://github.com/<your-user>/sshoyu/releases/latest/download/sshoyu-server_<version>_all.deb

# Install (triggers interactive debconf configuration)
sudo dpkg -i sshoyu-server_<version>_all.deb
```

During installation you will be asked for:

| Question | Description | Default |
|---|---|---|
| SSH hostname | Public hostname clients will connect to | — |
| SSH port | Port sshd listens on for sshoyu connections | `2200` |
| SSH user | System user created for tunnel connections | `sshoyu` |

The installer will:
- Create the `sshoyu` system user
- Generate an ed25519 SSH key pair at `/home/sshoyu/.ssh/`
- Configure `authorized_keys` with a forced command pointing to `sshoyu_cli.sh`
- Write `/etc/sshoyu/sshoyu.conf` with all configuration
- Install `/etc/sudoers.d/sshoyu` with minimal permissions for Caddyfile management
- Serve the client installer at `http://<your-host>/install.sh`

### Reconfigure

```bash
sudo dpkg-reconfigure sshoyu-server
```

### Remove

```bash
# Remove package (keeps config and user)
sudo dpkg -r sshoyu-server

# Remove everything including config and user
sudo dpkg --purge sshoyu-server
```

---

## Client setup

On any machine that needs to publish a local service, run:

```bash
curl -fsSL http://<your-server-host>/install.sh | sh
```

This will:
- Install `sshoyu` to `/usr/local/bin/sshoyu`
- Generate a dedicated SSH key at `~/.ssh/sshoyu_id_ed25519`
- Print the public key to add to the server's `authorized_keys`

### Authorize the client on the server

After running the installer, copy the printed public key and add it to the server:

```bash
sudo bash -c 'echo "command=\"/usr/local/bin/sshoyu_cli.sh\",no-X11-forwarding,no-agent-forwarding,no-pty <public-key>" >> /home/sshoyu/.ssh/authorized_keys'
```

### Usage

```bash
sshoyu <subdomain> <localport>
```

**Examples:**

```bash
# Expose a local web app on port 3000
sshoyu myapp 3000
# → https://myapp.your-server-host

# Expose Portainer on port 9443
sshoyu portainer 9443
# → https://portainer.your-server-host

# Expose a plain HTTP service on port 80
sshoyu site 80
# → https://site.your-server-host
```

Press `Ctrl+C` to close the tunnel. The subdomain is removed from Caddy immediately.

### Custom SSH key

Set `SSHOYU_KEY` to use a different key:

```bash
SSHOYU_KEY=~/.ssh/other_key sshoyu myapp 3000
```

---

## Monitoring

The package installs a systemd service (`sshoyu-monitor`) that runs every 15 seconds and:
- Removes Caddyfile blocks for tunnels whose process has died
- Kills orphaned `sshoyu_cli.sh` processes with no corresponding lock file

```bash
# Check monitor status
systemctl status sshoyu-monitor

# Follow monitor logs
journalctl -u sshoyu-monitor -f
```

### Active tunnels

```bash
for f in /tmp/sshoyu_tunnel_*.lock; do
    [ -f "$f" ] || continue
    subdomain=$(basename "$f" | sed 's/sshoyu_tunnel_//;s/\.lock//')
    pid=$(cat "$f")
    echo "$subdomain (PID $pid)"
done
```

---

## Configuration

`/etc/sshoyu/sshoyu.conf` (server-side):

```bash
SSH_HOST=tunnel.example.com   # used as the base domain for subdomains
SSH_PORT=2200
SSH_USER=sshoyu
CADDYFILE_PATH=/etc/caddy/Caddyfile
MIN_REMOTE_PORT=3000
LOCK_FILE_DIR=/tmp
```

---

## Building from source

```bash
git clone https://github.com/<your-user>/sshoyu.git
cd sshoyu

# Edit version in debian/control if needed, then:
./scripts/build.sh
```

The `.deb` file is created in the repository root.

---

## Architecture

```
sshoyu/
├── pkg/
│   ├── DEBIAN/              # Package scripts (synced from debian/)
│   ├── lib/systemd/system/
│   │   └── sshoyu-monitor.service
│   └── usr/share/sshoyu/
│       ├── ssh_client.sh    # Client template (placeholders replaced at install time)
│       ├── sshoyu_cli.sh    # Server forced command
│       └── sshoyu-monitor.sh
├── debian/                  # Source for packaging scripts
│   ├── control
│   ├── templates            # debconf questions
│   ├── config               # debconf pre-configuration
│   ├── postinst             # Creates user, keys, sudoers, config, client installer
│   ├── prerm                # Stops monitor and active tunnels
│   └── postrm               # Purge cleanup
└── scripts/
    └── build.sh             # Builds the .deb reading version from debian/control
```
