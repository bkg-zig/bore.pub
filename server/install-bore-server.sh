#!/usr/bin/env bash
#
# install-bore-server.sh - turn the host that owns eysho.info into a private
# bore server with per-app subdomains.
#
#   sudo DOMAIN=eysho.info BORE_SECRET=... ./install-bore-server.sh
#   sudo DOMAIN=eysho.info BORE_SECRET=... ./install-bore-server.sh --with-caddy
#
# Installs:
#   bore          server on 0.0.0.0:7835, ports 43000-43999 for apps
#   bore-router   <app>.eysho.info -> 127.0.0.1:<deterministic port>
#   caddy         optional, terminates TLS for *.eysho.info on 443
#
# DNS: A record eysho.info and *.eysho.info -> this host's public IP.
# Firewall: 22, 80, 443, 7835/tcp and 43000-43999/tcp.
#
set -Eeuo pipefail

DOMAIN="${DOMAIN:-eysho.info}"
BORE_SECRET="${BORE_SECRET:-}"
PORT_BASE="${PORT_BASE:-43000}"
PORT_RANGE="${PORT_RANGE:-1000}"
PINOKIO_PORT="${PINOKIO_PORT:-42000}"
BORE_VERSION="${BORE_VERSION:-v0.6.0}"
WITH_CADDY=0
for arg in "$@"; do [[ "$arg" == "--with-caddy" ]] && WITH_CADDY=1; done

log() { printf '\033[36m[server]\033[0m %s\n' "$*"; }
die() { printf '\033[31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

[[ "$(id -u)" == 0 ]] || die "run as root"
[[ -n "$BORE_SECRET" ]] || die "set BORE_SECRET (e.g. BORE_SECRET=\"\$(openssl rand -hex 16)\")"

case "$(uname -m)" in
  x86_64)  BORE_ARCH=x86_64-unknown-linux-musl ;;
  aarch64) BORE_ARCH=aarch64-unknown-linux-musl ;;
  *) die "unsupported architecture: $(uname -m)" ;;
esac

export DEBIAN_FRONTEND=noninteractive
log "installing packages"
apt-get update -qq
apt-get install -y -qq --no-install-recommends ca-certificates curl tar gzip ufw >/dev/null

if ! command -v bore >/dev/null; then
  log "installing bore ${BORE_VERSION}"
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/bore.tar.gz" \
    "https://github.com/ekzhang/bore/releases/download/${BORE_VERSION}/bore-${BORE_VERSION}-${BORE_ARCH}.tar.gz"
  tar -xzf "$tmp/bore.tar.gz" -C "$tmp"
  install -m 0755 "$tmp/bore" /usr/local/bin/bore
  rm -rf "$tmp"
fi

# ---- bore server -----------------------------------------------------------
mkdir -p /etc/bore /opt/bore-router
install -m 0600 /dev/null /etc/bore/secret
printf '%s\n' "$BORE_SECRET" >/etc/bore/secret

cat >/etc/systemd/system/bore.service <<UNIT
[Unit]
Description=bore server (private tunnel endpoint)
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/bore server --secret ${BORE_SECRET} --min-port ${PINOKIO_PORT} --max-port $((PORT_BASE + PORT_RANGE - 1)) --bind-addr 0.0.0.0
Restart=always
RestartSec=2
DynamicUser=yes
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
UNIT

# ---- subdomain router ------------------------------------------------------
SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SOURCE_DIR/bore-router.js" ]]; then
  install -m 0644 "$SOURCE_DIR/bore-router.js" /opt/bore-router/bore-router.js
else
  curl -fsSL "https://raw.githubusercontent.com/bkg-zig/bore.pub/main/server/bore-router.js" \
    -o /opt/bore-router/bore-router.js
fi

if ! command -v node >/dev/null; then
  log "installing node 20 for the router"
  tmp="$(mktemp -d)"
  case "$(uname -m)" in x86_64) A=x64 ;; aarch64) A=arm64 ;; esac
  curl -fsSL -o "$tmp/node.tar.xz" "https://nodejs.org/dist/v20.19.5/node-v20.19.5-linux-${A}.tar.xz"
  tar -xJf "$tmp/node.tar.xz" -C "$tmp"
  mv "$tmp/node-v20.19.5-linux-${A}" /usr/local/node20
  ln -sf /usr/local/node20/bin/node /usr/local/bin/node
  rm -rf "$tmp"
fi

cat >/etc/systemd/system/bore-router.service <<UNIT
[Unit]
Description=bore subdomain router (${DOMAIN})
After=network-online.target bore.service
Wants=network-online.target

[Service]
Environment=DOMAIN=${DOMAIN}
Environment=PORT_BASE=${PORT_BASE}
Environment=PORT_RANGE=${PORT_RANGE}
Environment=PINOKIO_PORT=${PINOKIO_PORT}
Environment=HTTP_PORT=8080
Environment=BIND=127.0.0.1
ExecStart=/usr/local/bin/node /opt/bore-router/bore-router.js
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
UNIT

# ---- optional TLS ----------------------------------------------------------
if [[ "$WITH_CADDY" == 1 ]]; then
  if ! command -v caddy >/dev/null; then
    log "installing caddy"
    apt-get install -y -qq --no-install-recommends debian-keyring debian-archive-keyring apt-transport-https >/dev/null
    curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/gpg.key \
      | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt \
      >/etc/apt/sources.list.d/caddy-stable.list
    apt-get update -qq
    apt-get install -y -qq caddy >/dev/null
  fi
  if [[ -f "$SOURCE_DIR/Caddyfile" ]]; then
    install -m 0644 "$SOURCE_DIR/Caddyfile" /etc/caddy/Caddyfile
  else
    curl -fsSL https://raw.githubusercontent.com/bkg-zig/bore.pub/main/server/Caddyfile \
      -o /etc/caddy/Caddyfile
  fi
  sed -i "s/eysho\.info/${DOMAIN}/g" /etc/caddy/Caddyfile
  systemctl enable --now caddy >/dev/null 2>&1 || true
fi

# ---- firewall --------------------------------------------------------------
if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
  log "opening firewall ports"
  ufw allow 7835/tcp >/dev/null
  ufw allow "$PINOKIO_PORT:$((PORT_BASE + PORT_RANGE - 1))/tcp" >/dev/null
  [[ "$WITH_CADDY" == 1 ]] && { ufw allow 80/tcp >/dev/null; ufw allow 443/tcp >/dev/null; }
fi

systemctl daemon-reload
systemctl enable --now bore.service >/dev/null
systemctl enable --now bore-router.service >/dev/null
sleep 1

log "bore:    $(systemctl is-active bore.service) on 7835, ports ${PINOKIO_PORT}-$((PORT_BASE + PORT_RANGE - 1))"
log "router:  $(systemctl is-active bore-router.service) on 127.0.0.1:8080"
[[ "$WITH_CADDY" == 1 ]] && log "caddy:   $(systemctl is-active caddy) on 80/443"

printf '\n  Private bore server is up.\n\n'
printf '  Client (GPU Colab, Pinokio):\n\n'
printf '    BORE_SERVER=%s \\\n' "$DOMAIN"
printf '    BORE_SECRET=%s \\\n' "$BORE_SECRET"
printf '    BORE_PORT=%s \\\n' "$PINOKIO_PORT"
printf '    PUBLIC_DOMAIN=%s \\\n' "$DOMAIN"
printf '    ./start.sh\n\n'
printf '  Pinokio UI : https://pinokio.%s\n' "$DOMAIN"
printf '  Each app   : https://<app-name>.%s\n\n' "$DOMAIN"
