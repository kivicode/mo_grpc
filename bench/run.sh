#!/bin/bash
# Local bench harness: brings up a TLS gRPC echo server and runs the Python +
# Mojo clients against it. Prints both result blocks to stdout.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
N="${BENCH_N:-5000}"
PORT="${BENCH_PORT:-50443}"
CACERT="$REPO/.pixi/envs/default/ssl/cacert.pem"

# Self-signed cert for 127.0.0.1 / localhost.
if [ ! -f "$HERE/certs/server.crt" ]; then
  mkdir -p "$HERE/certs"
  openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout "$HERE/certs/server.key" \
    -out "$HERE/certs/server.crt" \
    -days 30 -subj "/CN=localhost" \
    -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" >/dev/null 2>&1
fi

# libcurl in this pixi env is built with a baked-in CAINFO and ignores
# SSL_CERT_FILE / CURL_CA_BUNDLE, so the only way to make it trust the
# self-signed cert is to append it to the bundled file. Idempotent.
MARKER="# === mo_grpc bench self-signed cert ==="
if ! grep -qF "$MARKER" "$CACERT" 2>/dev/null; then
  { echo ""; echo "$MARKER"; cat "$HERE/certs/server.crt"; } >> "$CACERT"
fi

# Start the server. Trap kills it on exit.
uv run "$HERE/server.py" >"$HERE/.server.log" 2>&1 &
SERVER_PID=$!
trap "kill $SERVER_PID 2>/dev/null || true" EXIT
# wait for ready
for _ in $(seq 1 50); do
  if grep -q "server listening" "$HERE/.server.log" 2>/dev/null; then break; fi
  sleep 0.1
done

cd "$HERE"
BENCH_N="$N" BENCH_PORT="$PORT" uv run bench_python.py
echo
cd "$REPO"
BENCH_N="$N" BENCH_PORT="$PORT" "$HERE/bench_mojo"

echo
HEAVY_N="${HEAVY_N:-500}"
cd "$HERE"
BENCH_N="$HEAVY_N" BENCH_PORT="$PORT" uv run bench_heavy_python.py
echo
cd "$REPO"
BENCH_N="$HEAVY_N" BENCH_PORT="$PORT" "$HERE/bench_heavy_mojo"
