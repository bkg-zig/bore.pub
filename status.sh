#!/usr/bin/env bash
#
# status.sh - show what is running, the live URL and every app tunnel.
#
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -n "${PINOKIO_DIR:-}" ]]; then
  :
elif [[ -f "$SCRIPT_DIR/script/index.js" ]]; then
  PINOKIO_DIR="$SCRIPT_DIR"
else
  PINOKIO_DIR="$HOME/pinokiod"
fi

LOG_DIR="${LOG_DIR:-$PINOKIO_DIR/logs}"
PID_FILE="${PID_FILE:-$LOG_DIR/start.pid}"
STATE_DIR="${STATE_DIR:-${PINOKIO_HOME:-$HOME/.pinokio}/tunnels}"

ok()   { printf '  \033[32mup\033[0m   %s\n' "$*"; }
down() { printf '  \033[31mdown\033[0m %s\n' "$*"; }

if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  ok "start.sh (pid $(cat "$PID_FILE"))"
else
  down "start.sh"
fi

for name in pinokiod auth-proxy bore app-watcher; do
  pid=""
  case "$name" in
    bore)        pid="$(pgrep -f 'bore local .*--to' | head -1)" ;;
    app-watcher) [[ -f "$STATE_DIR/auto-tunnel.pid" ]] && pid="$(cat "$STATE_DIR/auto-tunnel.pid")" ;;
    *)           : ;;
  esac
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null && ok "$name (pid $pid)" || true
done

echo
echo "tunnels:"
if compgen -G "$STATE_DIR/*.json" >/dev/null; then
  for f in "$STATE_DIR"/*.json; do
    name="$(sed -n 's/.*"name": "\([^"]*\)".*/\1/p' "$f" | head -1)"
    url="$(sed -n 's/.*"url": "\([^"]*\)".*/\1/p' "$f" | head -1)"
    printf '  %-12s %s\n' "${name:-?}" "${url:-(none)}"
  done
else
  echo "  (none)"
fi

if [[ -f "$SCRIPT_DIR/url.md" ]]; then
  echo
  grep -E '^## |^\| (User|Password) ' "$SCRIPT_DIR/url.md" | sed 's/^/  /'
fi
