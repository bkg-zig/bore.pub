#!/usr/bin/env bash
#
# start.sh - run pinokiod locally and expose it through a bore tunnel.
#
#   ./start.sh                     # pinokiod on :42000 + public bore.pub URL
#   PORT=8080 ./start.sh           # different local port
#   BORE_PORT=12345 ./start.sh     # ask for a specific public port (best effort)
#   BORE_SERVER=tunnel.example.com BORE_SECRET=xyz ./start.sh   # self-hosted bore
#   NO_TUNNEL=1 ./start.sh         # local only, no tunnel
#   PINOKIO_DIR=/opt/pinokiod ./start.sh
#
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

PORT="${PORT:-42000}"
BORE_SERVER="${BORE_SERVER:-bore.pub}"
BORE_PORT="${BORE_PORT:-0}"
BORE_SECRET="${BORE_SECRET:-}"
NO_TUNNEL="${NO_TUNNEL:-0}"

# Where pinokiod lives. Defaults to this directory if it is a checkout,
# otherwise $HOME/pinokiod (install.sh default).
if [[ -n "${PINOKIO_DIR:-}" ]]; then
  :
elif [[ -f "$SCRIPT_DIR/script/index.js" ]]; then
  PINOKIO_DIR="$SCRIPT_DIR"
else
  PINOKIO_DIR="$HOME/pinokiod"
fi
[[ -f "$PINOKIO_DIR/script/index.js" ]] || {
  printf '\033[31m[error]\033[0m pinokiod not found at %s - run install.sh first\n' "$PINOKIO_DIR" >&2
  exit 1
}
cd "$PINOKIO_DIR"

# Pinokio's state dir (downloads, installed apps, env).
PINOKIO_HOME="${PINOKIO_HOME:-$HOME/.pinokio}"
export PINOKIO_HOME
mkdir -p "$PINOKIO_HOME"

LOG_DIR="${LOG_DIR:-$PINOKIO_DIR/logs}"
mkdir -p "$LOG_DIR"
APP_LOG="$LOG_DIR/pinokiod.log"
BORE_LOG="$LOG_DIR/bore.log"
: >"$BORE_LOG"

BORE_PID=""
APP_PID=""
TAIL_PIDS=()

log()  { printf '\033[36m[start]\033[0m %s\n' "$*"; }
fail() { printf '\033[31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

cleanup() {
  local code=$?
  trap - EXIT INT TERM
  log "shutting down"
  for p in "${TAIL_PIDS[@]:-}"; do [[ -n "$p" ]] && kill "$p" 2>/dev/null || true; done
  [[ -n "$BORE_PID" ]] && kill "$BORE_PID" 2>/dev/null || true
  if [[ -n "$APP_PID" ]]; then
    kill -TERM "$APP_PID" 2>/dev/null || true
    for _ in {1..30}; do kill -0 "$APP_PID" 2>/dev/null || break; sleep 0.2; done
    kill -KILL "$APP_PID" 2>/dev/null || true
  fi
  wait 2>/dev/null || true
  exit "$code"
}
trap cleanup EXIT INT TERM

# ---- preflight -------------------------------------------------------------
command -v node >/dev/null || fail "node not found - run install.sh first"
[[ -d "$PINOKIO_DIR/node_modules" ]] || fail "node_modules missing - run install.sh first"

if curl -fsS -o /dev/null --max-time 2 "http://127.0.0.1:${PORT}/" 2>/dev/null; then
  fail "something is already listening on port ${PORT}"
fi

# ---- pinokiod --------------------------------------------------------------
log "starting pinokiod (dir ${PINOKIO_DIR}, port ${PORT}, home ${PINOKIO_HOME})"
node script/index >>"$APP_LOG" 2>&1 &
APP_PID=$!

log "waiting for pinokiod to come up..."
ready=0
for _ in {1..180}; do
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    tail -n 40 "$APP_LOG" >&2
    fail "pinokiod exited during startup (see $APP_LOG)"
  fi
  if curl -fsS -o /dev/null --max-time 2 "http://127.0.0.1:${PORT}/" 2>/dev/null; then
    ready=1
    break
  fi
  sleep 1
done
[[ "$ready" == 1 ]] || { tail -n 40 "$APP_LOG" >&2; fail "pinokiod did not become ready in time"; }

log "pinokiod ready: http://localhost:${PORT}"
tail -n 0 -F "$APP_LOG" 2>/dev/null | sed -u "s/^/    [app] /" &
TAIL_PIDS+=($!)

if [[ "$NO_TUNNEL" == 1 ]]; then
  log "NO_TUNNEL=1 - skipping bore"
  wait "$APP_PID"
  exit 0
fi

# ---- bore tunnel -----------------------------------------------------------
command -v bore >/dev/null || fail "bore not found - run install.sh first"

# Canonical form: bore local <port> --to <server> [--port N] [--secret X]
BORE_ARGS=(--to "$BORE_SERVER")
[[ "$BORE_PORT" != 0 ]] && BORE_ARGS+=(--port "$BORE_PORT")
[[ -n "$BORE_SECRET" ]] && BORE_ARGS+=(--secret "$BORE_SECRET")

log "opening bore tunnel to ${BORE_SERVER}"
bore local "$PORT" "${BORE_ARGS[@]}" >>"$BORE_LOG" 2>&1 &
BORE_PID=$!

URL=""
for _ in {1..60}; do
  URL="$(sed -e 's/\x1b\[[0-9;]*m//g' "$BORE_LOG" 2>/dev/null \
        | grep -oE 'listening at [A-Za-z0-9._-]+:[0-9]+' | tail -n 1 | awk '{print $3}' || true)"
  [[ -n "$URL" ]] && break
  kill -0 "$BORE_PID" 2>/dev/null || break
  sleep 1
done

if [[ -z "$URL" ]]; then
  sed -e 's/\x1b\[[0-9;]*m//g' "$BORE_LOG" >&2
  fail "bore tunnel did not come up (see $BORE_LOG)"
fi

printf '\n'
printf '  \033[1;32m=== PINOKIO IS LIVE ===\033[0m\n\n'
printf '  Local : http://localhost:%s\n' "$PORT"
printf '  Public: \033[1mhttp://%s\033[0m\n\n' "$URL"
printf '  Anyone with that URL controls this machine (shell + files).\n'
printf '  Ctrl-C to stop the tunnel and the server.\n\n'

tail -n 0 -F "$BORE_LOG" 2>/dev/null | sed -u -e 's/\x1b\[[0-9;]*m//g' -e "s/^/    [bore] /" &
TAIL_PIDS+=($!)

wait "$APP_PID"
