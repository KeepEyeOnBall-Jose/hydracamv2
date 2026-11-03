#!/usr/bin/env bash
# Starts the auth/viewer server and MediaMTX for the spike. MEDIAMTX=/path/to/mediamtx (v1.21.3).
set -euo pipefail
cd "$(dirname "$0")/.."
: "${MEDIAMTX:?set MEDIAMTX to the mediamtx v1.21.3 binary}"
mkdir -p .local
if [[ ! -f .local/server.crt ]]; then
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 30 \
    -subj "/CN=h8-spike-relay" -keyout .local/server.key -out .local/server.crt 2>/dev/null
fi
python3 relay_server.py & server=$!
trap 'kill $server 2>/dev/null' EXIT
"$MEDIAMTX" mediamtx.yml
