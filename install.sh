#!/usr/bin/env bash
#
# install.sh - install pinokiod and expose it with a bore tunnel.
#
#   curl -fsSL https://raw.githubusercontent.com/bkg-zig/bore.pub/main/install.sh | sudo bash
#   curl -fsSL https://raw.githubusercontent.com/bkg-zig/bore.pub/main/install.sh | sudo bash -s -- --start
#
# Safe to run again at any time: it updates what exists instead of wiping it,
# so `--start` on a fresh Colab runtime is a full reinstall in one command.
#
# Environment:
#   PINOKIO_DIR     where pinokiod is cloned        (default: $HOME/pinokiod)
#   NODE_VERSION    Node.js version to install      (default: v20.19.5)
#   BORE_VERSION    bore release to install         (default: v0.6.0)
#   REPO            pinokiod git remote             (default: upstream)
#   PORT            local pinokiod port             (default: 42000)
#   START           1 = start after installing      (same as --start)
#
set -Eeuo pipefail

# Resolve this script to an absolute path *before* any cd, so the local
# checkout is used when there is one.
SELF="${BASH_SOURCE[0]:-}"
if [[ -n "$SELF" && -f "$SELF" ]]; then
  SELF="$(cd -- "$(dirname -- "$SELF")" && pwd)/$(basename -- "$SELF")"
fi

REPO="${REPO:-https://github.com/pinokiocomputer/pinokiod.git}"
PINOKIO_DIR="${PINOKIO_DIR:-$HOME/pinokiod}"
NODE_VERSION="${NODE_VERSION:-v20.19.5}"
BORE_VERSION="${BORE_VERSION:-v0.6.0}"
WANT_START="${START:-0}"

for arg in "$@"; do
  case "$arg" in
    --start)    WANT_START=1 ;;
    --no-start) WANT_START=0 ;;
    *) printf '[install] ignoring unknown argument: %s\n' "$arg" >&2 ;;
  esac
done

log() { printf '\033[36m[install]\033[0m %s\n' "$*"; }
die() { printf '\033[31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

[[ "$(id -u)" == 0 ]] || die "run as root (or with sudo)"

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64)  NODE_ARCH=x64;   BORE_ARCH=x86_64-unknown-linux-musl ;;
  aarch64) NODE_ARCH=arm64; BORE_ARCH=aarch64-unknown-linux-musl ;;
  *) die "unsupported architecture: $ARCH" ;;
esac

# ---- system packages -------------------------------------------------------
log "installing system packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  ca-certificates curl git tar xz-utils python3 make g++ \
  lsof net-tools p7zip-full pv openssh-client >/dev/null

# ---- node 20 ---------------------------------------------------------------
if command -v node >/dev/null && [[ "$(node -p 'process.versions.node.split(".")[0]')" -ge 20 ]]; then
  log "node $(node -v) already installed"
else
  log "installing node ${NODE_VERSION}"
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/node.tar.xz" \
    "https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz"
  tar -xJf "$tmp/node.tar.xz" -C "$tmp"
  rm -rf /usr/local/node20
  mv "$tmp/node-${NODE_VERSION}-linux-${NODE_ARCH}" /usr/local/node20
  for b in node npm npx; do ln -sf "/usr/local/node20/bin/$b" "/usr/local/bin/$b"; done
  rm -rf "$tmp"
fi
log "node $(node -v) / npm $(npm -v)"

# ---- bore ------------------------------------------------------------------
if command -v bore >/dev/null; then
  log "$(bore --version) already installed"
else
  log "installing bore ${BORE_VERSION}"
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/bore.tar.gz" \
    "https://github.com/ekzhang/bore/releases/download/${BORE_VERSION}/bore-${BORE_VERSION}-${BORE_ARCH}.tar.gz"
  tar -xzf "$tmp/bore.tar.gz" -C "$tmp"
  install -m 0755 "$tmp/bore" /usr/local/bin/bore
  rm -rf "$tmp"
  log "$(bore --version)"
fi

# ---- pinokiod --------------------------------------------------------------
if [[ -d "$PINOKIO_DIR/.git" ]]; then
  log "updating $PINOKIO_DIR"
  git -C "$PINOKIO_DIR" pull --ff-only
else
  log "cloning $REPO -> $PINOKIO_DIR"
  mkdir -p "$(dirname "$PINOKIO_DIR")"
  git clone --depth 1 "$REPO" "$PINOKIO_DIR"
fi

log "installing npm dependencies (2-3 minutes)"
cd "$PINOKIO_DIR"
npm ci --omit=dev --no-audit --no-fund

# ---- launcher --------------------------------------------------------------
# install.sh may be run from a checkout or piped from curl, so handle both.
START_URL="${START_URL:-https://raw.githubusercontent.com/bkg-zig/bore.pub/main/start.sh}"
if [[ -n "$SELF" && -f "$SELF" && -f "$(dirname "$SELF")/start.sh" ]]; then
  for f in start.sh stop.sh status.sh; do
    [[ -f "$(dirname "$SELF")/$f" ]] && install -m 0755 "$(dirname "$SELF")/$f" "$PINOKIO_DIR/$f"
  done
  [[ -f "$(dirname "$SELF")/auth-proxy.js" ]] && \
    install -m 0644 "$(dirname "$SELF")/auth-proxy.js" "$PINOKIO_DIR/auth-proxy.js"
  log "installed start.sh, stop.sh, status.sh, auth-proxy.js from local checkout"
else
  for f in start.sh stop.sh status.sh; do
    curl -fsSL "${START_URL%/*}/$f" -o "$PINOKIO_DIR/$f" && chmod +x "$PINOKIO_DIR/$f"
  done
  curl -fsSL "${START_URL%/*}/auth-proxy.js" -o "$PINOKIO_DIR/auth-proxy.js"
  log "installed start.sh, stop.sh, status.sh, auth-proxy.js from ${START_URL%/*}"
fi

# ---- auto-tunnel plugin ----------------------------------------------------
# Tunnels every app port and lists the current (random) URLs in the dashboard.
PINOKIO_HOME="${PINOKIO_HOME:-$HOME/.pinokio}"
PLUGIN_DIR="$PINOKIO_HOME/plugin/bore-pinokio-auto"
PLUGIN_REPO="${PLUGIN_REPO:-https://github.com/bkg-zig/bore_pinokio_pluckin-bKG.git}"
PLUGIN_RAW="${PLUGIN_RAW:-https://raw.githubusercontent.com/bkg-zig/bore_pinokio_pluckin-bKG/main}"
mkdir -p "$PINOKIO_HOME/plugin"
if [[ -d "$PLUGIN_DIR/.git" ]]; then
  git -C "$PLUGIN_DIR" pull --ff-only -q || true
  log "auto-tunnel plugin already present"
else
  log "installing auto-tunnel plugin"
  git clone --depth 1 -q "$PLUGIN_REPO" "$PLUGIN_DIR" || log "warning: could not clone plugin"
fi

# Mark it installed in the Pinokio UI by seeding the binary it looks for.
if [[ -d "$PLUGIN_DIR" && ! -x "$PLUGIN_DIR/bore" ]]; then
  cp /usr/local/bin/bore "$PLUGIN_DIR/bore" 2>/dev/null && chmod +x "$PLUGIN_DIR/bore" || true
fi

# The app watcher runs from the pinokiod dir, started automatically by start.sh.
if [[ -f "$PLUGIN_DIR/auto-tunnel.sh" ]]; then
  install -m 0755 "$PLUGIN_DIR/auto-tunnel.sh" "$PINOKIO_DIR/auto-tunnel.sh"
else
  curl -fsSL "$PLUGIN_RAW/auto-tunnel.sh" -o "$PINOKIO_DIR/auto-tunnel.sh" \
    && chmod +x "$PINOKIO_DIR/auto-tunnel.sh" || log "warning: auto-tunnel.sh missing"
fi

# ---- credentials -----------------------------------------------------------
# Username is bkg; the password is generated on every start and written to
# url.md, so nothing secret is stored here.
AUTH_ENV="$PINOKIO_HOME/auth.env"
if [[ ! -f "$AUTH_ENV" ]]; then
  umask 077
  printf 'AUTH_USER=bkg\n' >"$AUTH_ENV"
  chmod 600 "$AUTH_ENV"
  umask 022
  log "wrote $AUTH_ENV (user bkg, random password at each start)"
fi

# ---- start -----------------------------------------------------------------
if [[ "$WANT_START" == 1 ]]; then
  if [[ -f "$PINOKIO_DIR/logs/start.pid" ]] && kill -0 "$(cat "$PINOKIO_DIR/logs/start.pid")" 2>/dev/null; then
    log "pinokiod is already running (pid $(cat "$PINOKIO_DIR/logs/start.pid"))"
  else
    log "starting pinokiod in the background"
    mkdir -p "$PINOKIO_DIR/logs"
    PINOKIO_DIR="$PINOKIO_DIR" PINOKIO_HOME="$PINOKIO_HOME" \
      setsid "$PINOKIO_DIR/start.sh" </dev/null >>"$PINOKIO_DIR/logs/install-start.log" 2>&1 &
    for _ in $(seq 1 120); do
      [[ -f "$PINOKIO_DIR/url.md" ]] && grep -q '^## http' "$PINOKIO_DIR/url.md" && break
      sleep 2
    done
  fi

  if [[ -f "$PINOKIO_DIR/url.md" ]] && grep -q '^## http' "$PINOKIO_DIR/url.md"; then
    url="$(grep -m1 '^## http' "$PINOKIO_DIR/url.md" | sed -E 's/^## //')"
    pass="$(grep -m1 '| Password' "$PINOKIO_DIR/url.md" | sed -E 's/.*`([^`]+)`.*/\1/' || true)"
    printf '\n  \033[1;32m=== PINOKIO IS LIVE ===\033[0m\n\n'
    printf '  URL  : \033[1m%s\033[0m\n' "$url"
    printf '  User : bkg\n'
    [[ -n "$pass" ]] && printf '  Pass : \033[1m%s\033[0m\n' "$pass"
    printf '\n  Logs   : %s/logs/\n' "$PINOKIO_DIR"
    printf '  Status : %s/status.sh\n' "$PINOKIO_DIR"
    printf '  Stop   : %s/stop.sh\n\n' "$PINOKIO_DIR"
  else
    log "warning: the tunnel did not come up yet - check $PINOKIO_DIR/logs/install-start.log"
    log "start it manually with $PINOKIO_DIR/start.sh"
  fi
  exit 0
fi

printf '\n'
log "done. start it with:"
printf '\n    %s/start.sh\n\n' "$PINOKIO_DIR"
log "or re-run this script with --start to install and launch in one step."
log "user is bkg; the random password is printed at start and saved in url.md."
