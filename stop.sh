#!/usr/bin/env bash
#
# stop.sh - stop a running start.sh cleanly (by pidfile, never by pattern).
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

PID_FILE="${PID_FILE:-$PINOKIO_DIR/logs/start.pid}"
STATE_DIR="${STATE_DIR:-${PINOKIO_HOME:-$HOME/.pinokio}/tunnels}"

if [[ ! -f "$PID_FILE" ]]; then
  echo "no pidfile at $PID_FILE - start.sh is not running"
  # clean up an orphaned watcher, if any
  if [[ -f "$STATE_DIR/auto-tunnel.pid" ]]; then
    kill "$(cat "$STATE_DIR/auto-tunnel.pid")" 2>/dev/null && echo "stopped orphaned app watcher"
  fi
  exit 0
fi

pid="$(cat "$PID_FILE")"
if ! kill -0 "$pid" 2>/dev/null; then
  echo "pid $pid is not running - removing stale pidfile"
  rm -f "$PID_FILE"
  exit 0
fi

echo "stopping start.sh (pid $pid)"
kill -TERM "$pid" 2>/dev/null

for _ in $(seq 1 40); do
  kill -0 "$pid" 2>/dev/null || { echo "stopped"; exit 0; }
  sleep 0.25
done

echo "did not exit in 10s - sending SIGKILL"
kill -KILL "$pid" 2>/dev/null
rm -f "$PID_FILE"
exit 0
