#!/usr/bin/env bash
#
# keepalive.sh - keep a Colab runtime from being reclaimed while Pinokio runs.
#
#   ./colab/keepalive.sh            # every 4 minutes, forever
#   INTERVAL=120 ./colab/keepalive.sh
#
# Colab reclaims a runtime whose kernel has been idle. The tunnel and the apps
# keep running as detached processes, but the VM is only kept while the kernel
# is active, so this pokes it on a timer. Run it in a second terminal.
#
set -uo pipefail

SESSION="${SESSION:-pinokio}"
INTERVAL="${INTERVAL:-240}"

command -v colab >/dev/null || { echo "colab CLI missing: pip install google-colab-cli" >&2; exit 1; }

while true; do
  status="$(colab status -s "$SESSION" 2>/dev/null | head -1)"
  if [[ -z "$status" ]]; then
    echo "[keepalive] session $SESSION is gone"
    exit 1
  fi
  printf '[%s] %s\n' "$(date +%H:%M:%S)" "$status"
  echo 'print("keepalive")' | colab exec -s "$SESSION" >/dev/null 2>&1
  sleep "$INTERVAL"
done
