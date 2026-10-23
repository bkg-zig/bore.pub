#!/usr/bin/env bash
#
# install.sh - install pinokiod and expose it with a bore tunnel.
#
#   curl -fsSL https://raw.githubusercontent.com/bkg-zig/bore.pub/main/install.sh | sudo bash
#
# Environment:
#   PINOKIO_DIR     where pinokiod is cloned        (default: $HOME/pinokiod)
#   NODE_VERSION    Node.js version to install      (default: v20.19.5)
#   BORE_VERSION    bore release to install         (default: v0.6.0)
#   REPO            pinokiod git remote             (default: upstream)
#
set -Eeuo pipefail

REPO="${REPO:-https://github.com/pinokiocomputer/pinokiod.git}"
PINOKIO_DIR="${PINOKIO_DIR:-$HOME/pinokiod}"
NODE_VERSION="${NODE_VERSION:-v20.19.5}"
BORE_VERSION="${BORE_VERSION:-v0.6.0}"

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
SELF="${BASH_SOURCE[0]:-}"
if [[ -n "$SELF" && -f "$SELF" && -f "$(dirname "$SELF")/start.sh" ]]; then
  install -m 0755 "$(dirname "$SELF")/start.sh" "$PINOKIO_DIR/start.sh"
  log "installed start.sh from local checkout"
else
  curl -fsSL "$START_URL" -o "$PINOKIO_DIR/start.sh"
  chmod +x "$PINOKIO_DIR/start.sh"
  log "installed start.sh from $START_URL"
fi

printf '\n'
log "done. start it with:"
printf '\n    %s/start.sh\n\n' "$PINOKIO_DIR"
