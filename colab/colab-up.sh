#!/usr/bin/env bash
#
# colab-up.sh - run Pinokio on a GPU Colab runtime, published through the
# private bore server on eysho.info.
#
#   pip install google-colab-cli        # or: uv tool install google-colab-cli
#   colab new -s pinokio --gpu T4       # one-time, or let this script do it
#
#   BORE_SECRET=... ./colab/colab-up.sh
#
# Then:
#   https://pinokio.eysho.info            Pinokio UI (Basic Auth bkg / password)
#   https://<app-name>.eysho.info         each app you start in Pinokio
#
# Env:
#   SESSION       Colab session name          (default pinokio)
#   GPU           accelerator                 (default T4)
#   DOMAIN        base domain                 (default eysho.info)
#   BORE_SERVER   bore server host            (default $DOMAIN)
#   BORE_SECRET   private bore secret         (required)
#   BORE_PORT     public port for the UI      (default 42000)
#   RECREATE      1 = stop and recreate the session first
#
set -Eeuo pipefail

SESSION="${SESSION:-pinokio}"
GPU="${GPU:-T4}"
DOMAIN="${DOMAIN:-eysho.info}"
BORE_SERVER="${BORE_SERVER:-$DOMAIN}"
BORE_SECRET="${BORE_SECRET:-}"
BORE_PORT="${BORE_PORT:-42000}"
PORT_BASE="${PORT_BASE:-43000}"
PORT_RANGE="${PORT_RANGE:-1000}"
RECREATE="${RECREATE:-0}"
INSTALL_URL="${INSTALL_URL:-https://raw.githubusercontent.com/bkg-zig/bore.pub/main/install.sh}"

log() { printf '\033[36m[colab]\033[0m %s\n' "$*"; }
die() { printf '\033[31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

command -v colab >/dev/null || die "colab CLI missing: pip install google-colab-cli"

if [[ "$RECREATE" == 1 ]] && colab status -s "$SESSION" >/dev/null 2>&1; then
  log "stopping old session $SESSION"
  colab stop -s "$SESSION" || true
fi

if colab status -s "$SESSION" >/dev/null 2>&1; then
  log "reusing session $SESSION"
else
  log "creating session $SESSION with $GPU"
  colab new -s "$SESSION" --gpu "$GPU"
fi

colab status -s "$SESSION" | sed 's/^/    /'

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
script="$tmp/pinokio_bootstrap.py"

cat >"$script" <<PY
import os, subprocess, time, pathlib

ENV = dict(
    os.environ,
    BORE_SERVER=${BORE_SERVER@Q},
    BORE_SECRET=${BORE_SECRET@Q},
    BORE_PORT=${BORE_PORT@Q},
    PUBLIC_DOMAIN=${DOMAIN@Q},
    PORT_BASE=${PORT_BASE@Q},
    PORT_RANGE=${PORT_RANGE@Q},
    AUTO_APPS="1",
)

print("gpu:", subprocess.run("nvidia-smi --query-gpu=name,memory.total --format=csv,noheader",
                             shell=True, capture_output=True, text=True).stdout.strip() or "none")

cmd = "curl -fsSL ${INSTALL_URL} | bash -s -- --start"
print("running:", cmd)
subprocess.run(cmd, shell=True, env=ENV)

url_md = pathlib.Path.home() / "pinokiod" / "url.md"
for _ in range(60):
    if url_md.exists() and "## http" in url_md.read_text():
        text = url_md.read_text()
        url = [l for l in text.splitlines() if l.startswith("## ")][0][3:].strip()
        pw = [l for l in text.splitlines() if l.startswith("| Password")][0].split("\`")[1]
        print()
        print("=== PINOKIO IS LIVE ===")
        print("URL :", url)
        print("User: bkg")
        print("Pass:", pw)
        print()
        print("apps:", url.replace("pinokio", "<app-name>"))
        break
    time.sleep(2)
else:
    print("tunnel not up yet - check ~/pinokiod/logs/install-start.log")

# keep the kernel busy so the runtime is not reclaimed while apps install
pathlib.Path("/content/pinokio-keepalive").write_text(str(time.time()))
PY

log "installing Pinokio on $SESSION and opening the tunnel"
colab exec -s "$SESSION" -f "$script"

printf '\n'
log "Pinokio UI : https://pinokio.${DOMAIN}"
log "apps       : https://<app-name>.${DOMAIN}"
printf '\n'
log "the runtime stays alive while the kernel is active; keep this open:"
printf '    colab console -s %s\n\n' "$SESSION"
log "stop everything with: colab stop -s $SESSION"
