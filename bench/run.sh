#!/bin/bash
# Local bench harness: regenerates the proto stubs, rebuilds the Mojo client
# binaries, brings up a TLS gRPC echo server, and runs the Python + Mojo
# clients against it. Prints all four result blocks to stdout.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
TINY_N="${BENCH_N:-5000}"
HEAVY_N="${HEAVY_N:-500}"
PORT="${BENCH_PORT:-50443}"
CACERT="$REPO/.pixi/envs/default/ssl/cacert.pem"

PROTOS=(echo heavy)

step() {
  printf '\n>>> %s\n' "$*"
}

# -- 1. self-signed TLS cert + libcurl trust -----------------------------------
# We need *some* cert because mo_grpc forces HTTP/2 over TLS (libcurl falls back to HTTP/1.1 over plaintext, which gRPC servers reject).
if [ ! -f "$HERE/certs/server.crt" ]; then
  step "generating self-signed TLS cert"
  mkdir -p "$HERE/certs"
  openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout "$HERE/certs/server.key" \
    -out "$HERE/certs/server.crt" \
    -days 30 -subj "/CN=localhost" \
    -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" >/dev/null 2>&1
fi

# libcurl in this pixi env is built with a baked-in CAINFO and ignores both
# SSL_CERT_FILE and CURL_CA_BUNDLE, so the only way to make it trust the
# self-signed cert is to append it to the bundled file. Idempotent.
MARKER="# === mo_grpc bench self-signed cert ==="
if ! grep -qF "$MARKER" "$CACERT" 2>/dev/null; then
  step "trusting bench cert in $CACERT"
  { echo ""; echo "$MARKER"; cat "$HERE/certs/server.crt"; } >> "$CACERT"
fi

# -- 2. (re)generate proto stubs -----------------------------------------------
mkdir -p "$HERE/gen"
PLUGIN="$REPO/packages/protoc-gen-mojo/tests/run_plugin.sh"

for proto in "${PROTOS[@]}"; do
  step "generating $proto.proto stubs (python + mojo)"
  uv run --quiet --with grpcio-tools --with protobuf python -m grpc_tools.protoc \
    -I "$HERE/proto" \
    --python_out="$HERE/gen" \
    --grpc_python_out="$HERE/gen" \
    "$HERE/proto/$proto.proto"
  ( cd "$REPO" && protoc \
      -I bench/proto \
      --plugin=protoc-gen-mojo="$PLUGIN" \
      --mojo_out=bench/gen \
      "bench/proto/$proto.proto" )
done

# -- 3. (re)build the Mojo client binaries -------------------------------------
build_mojo() {
  local source="$1"
  local output="$2"
  step "building $output"
  ( cd "$REPO" && pixi run mojo build -O3 \
      -I packages/mo_protobuf \
      -I packages/mo_grpc \
      -I bench/gen \
      -o "$output" \
      "$source" )
}

build_mojo "$HERE/bench_mojo.mojo"       "$HERE/bench_mojo"
build_mojo "$HERE/bench_heavy_mojo.mojo" "$HERE/bench_heavy_mojo"

# -- 4. start the gRPC echo server ---------------------------------------------
# We don't use a separate process group (`set -m`) because we *want* Ctrl-C to
# land on both the bench step and the server simultaneously: the user's
# terminal will deliver SIGINT to the whole foreground process group, and the
# EXIT trap below will mop up afterwards.
step "starting echo server on 127.0.0.1:$PORT"
uv run "$HERE/server.py" >"$HERE/.server.log" 2>&1 &
SERVER_PID=$!

# Always run cleanup on script exit, no matter how we got there (normal exit,
# `exit 1` on failure, Ctrl-C, SIGTERM, …). `uv run` spawns a python child
# that doesn't always die with its parent and the grpcio server has worker
# threads of its own, so we kill by both PID and command match.
cleanup() {
  kill "$SERVER_PID" 2>/dev/null || true
  pkill -f "$HERE/server.py" 2>/dev/null || true
  wait "$SERVER_PID" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

# Wait for the server to be ready (or fail fast if it crashed).
for _ in $(seq 1 50); do
  if grep -q "server listening" "$HERE/.server.log" 2>/dev/null; then break; fi
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "server failed to start; see $HERE/.server.log" >&2
    exit 1
  fi
  sleep 0.1
done

# -- 5. run all four benches ---------------------------------------------------
echo
cd "$HERE"
BENCH_N="$TINY_N" BENCH_PORT="$PORT" uv run bench_python.py
echo
cd "$REPO"
BENCH_N="$TINY_N" BENCH_PORT="$PORT" "$HERE/bench_mojo"
echo
cd "$HERE"
BENCH_N="$HEAVY_N" BENCH_PORT="$PORT" uv run bench_heavy_python.py
echo
cd "$REPO"
BENCH_N="$HEAVY_N" BENCH_PORT="$PORT" "$HERE/bench_heavy_mojo"
