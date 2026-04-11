#!/bin/bash
# Run the full protoc-gen-mojo test suite.
# Usage:  cd /path/to/ouroboros/protoc-gen-mojo && bash tests/run_tests.sh
# Or:     cd /path/to/ouroboros && bash protoc-gen-mojo/tests/run_tests.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO="$(cd "$PLUGIN_DIR/.." && pwd)"
MOJO="$REPO/.venv/bin/mojo"

NOISE='warning:|^ *var |^ *\^ |^from |^ *std\.|^Included|^/Users|^ *\^$'

# ── one-shot plugin wrapper ───────────────────────────────────────────────────
PLUGIN_WRAPPER="$SCRIPT_DIR/run_plugin.sh"
cat > "$PLUGIN_WRAPPER" << EOF
#!/bin/bash
exec "$MOJO" run \\
  -I "$REPO" \\
  -I "$PLUGIN_DIR" \\
  "$PLUGIN_DIR/main.mojo" "\$@"
EOF
chmod +x "$PLUGIN_WRAPPER"

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
"$MOJO" run -I "$REPO" tests/test_runtime.mojo 2>&1 | grep -Ev "$NOISE"
[ "${PIPESTATUS[0]}" -ne 0 ] && OVERALL=1

# ── codegen roundtrip tests ───────────────────────────────────────────────────
echo ""
echo "=== codegen roundtrip tests ==="
"$MOJO" run -I "$REPO" -I tests/gen tests/test_codegen.mojo 2>&1 | grep -Ev "$NOISE"
[ "${PIPESTATUS[0]}" -ne 0 ] && OVERALL=1

echo ""
echo "=== oneof tests ==="
"$MOJO" run -I "$REPO" -I tests/gen tests/test_oneof.mojo 2>&1 | grep -Ev "$NOISE"
[ "${PIPESTATUS[0]}" -ne 0 ] && OVERALL=1

exit $OVERALL
