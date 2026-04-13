#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO="$(cd "$PLUGIN_DIR/.." && pwd)"
PIXI="$(command -v pixi || echo "$HOME/.pixi/bin/pixi")"
cd "$REPO"
exec "$PIXI" run mojo run \
  -I "$REPO" \
  -I "$PLUGIN_DIR" \
  "$PLUGIN_DIR/main.mojo" "$@"
