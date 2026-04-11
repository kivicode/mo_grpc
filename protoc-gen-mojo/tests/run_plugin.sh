#!/bin/bash
exec "/Users/kivicode/Documents/GitHub/ouroboros/.venv/bin/mojo" run \
  -I "/Users/kivicode/Documents/GitHub/ouroboros" \
  -I "/Users/kivicode/Documents/GitHub/ouroboros/protoc-gen-mojo" \
  "/Users/kivicode/Documents/GitHub/ouroboros/protoc-gen-mojo/main.mojo" "$@"
