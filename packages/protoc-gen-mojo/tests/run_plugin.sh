#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKAGES="$(cd "$PLUGIN_DIR/.." && pwd)"
REPO="$(cd "$PACKAGES/.." && pwd)"
PIXI="$(command -v pixi || echo "$HOME/.pixi/bin/pixi")"
cd "$REPO"
exec "$PIXI" run mojo run \
  -I "$PACKAGES/mo_protobuf" \
  -I "$PACKAGES/mo_grpc" \
  -I "$PLUGIN_DIR" \
  "$PLUGIN_DIR/main.mojo" "$@"
