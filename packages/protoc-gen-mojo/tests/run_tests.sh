#!/bin/bash
# Run the full protoc-gen-mojo test suite.
# Usage: bash packages/protoc-gen-mojo/tests/run_tests.sh  (from any dir)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKAGES="$(cd "$PLUGIN_DIR/.." && pwd)"
REPO="$(cd "$PACKAGES/.." && pwd)"
PIXI="$(command -v pixi || echo "$HOME/.pixi/bin/pixi")"

NOISE='warning:|^ *var |^ *\^ |^from |^ *std\.|^Included|^/Users|^ *\^$'

# Every mojo invocation needs these -I paths so `from protobuf_runtime ...`
# and `from mgrpc ...` resolve.
MOJO_IPATH=(
  -I "$PACKAGES/protobuf-runtime"
  -I "$PACKAGES/mgrpc"
  -I "$PLUGIN_DIR"
)

run_mojo() {
  (cd "$REPO" && "$PIXI" run mojo run "${MOJO_IPATH[@]}" "$@")
}

PLUGIN_WRAPPER="$SCRIPT_DIR/run_plugin.sh"

cd "$PLUGIN_DIR"
OVERALL=0

# ── generate test protos ──────────────────────────────────────────────────────
echo "=== generating test protos ==="
for proto in person.proto oneof_test.proto; do
  if protoc -I tests/assets \
      --plugin=protoc-gen-mojo="$PLUGIN_WRAPPER" \
      --mojo_out=tests/gen \
      "$proto" 2>/dev/null; then
    echo "  PASS  generate $proto"
  else
    echo "  FAIL  generate $proto"
    OVERALL=1
  fi
done

# ── runtime tests ─────────────────────────────────────────────────────────────
echo ""
echo "=== runtime tests ==="
run_mojo "$PLUGIN_DIR/tests/test_runtime.mojo" 2>&1 | grep -Ev "$NOISE"
[ "${PIPESTATUS[0]}" -ne 0 ] && OVERALL=1

# ── codegen roundtrip tests ───────────────────────────────────────────────────
echo ""
echo "=== codegen roundtrip tests ==="
run_mojo -I "$PLUGIN_DIR/tests/gen" "$PLUGIN_DIR/tests/test_codegen.mojo" 2>&1 | grep -Ev "$NOISE"
[ "${PIPESTATUS[0]}" -ne 0 ] && OVERALL=1

echo ""
echo "=== oneof tests ==="
run_mojo -I "$PLUGIN_DIR/tests/gen" "$PLUGIN_DIR/tests/test_oneof.mojo" 2>&1 | grep -Ev "$NOISE"
[ "${PIPESTATUS[0]}" -ne 0 ] && OVERALL=1

echo ""
echo "=== grpc frame tests ==="
run_mojo "$PLUGIN_DIR/tests/test_grpc_frame.mojo" 2>&1 | grep -Ev "$NOISE"
[ "${PIPESTATUS[0]}" -ne 0 ] && OVERALL=1

echo ""
echo "=== grpc transport tests (network) ==="
run_mojo "$PLUGIN_DIR/tests/test_grpc_transport.mojo" 2>&1 | grep -Ev "$NOISE"
[ "${PIPESTATUS[0]}" -ne 0 ] && OVERALL=1

exit $OVERALL
