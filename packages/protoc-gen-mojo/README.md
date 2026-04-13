# protoc-gen-mojo

A [protoc](https://protobuf.dev/reference/protobuf/proto3-spec/) plugin that generates Mojo code from `.proto` files.

## Features

- All 15 protobuf scalar types (int32/64, uint32/64, sint32/64, fixed32/64, sfixed32/64, float, double, bool, string, bytes)
- `optional`, `repeated` (packed + unpacked), and required fields
- Nested messages and enums
- `map<K, V>` → `Dict[K, V]`
- Cross-file imports with `--mojo_opt=module_prefix=...`
- `oneof` — generates a discriminant-tagged union struct with type-safe factories and accessors
- gRPC services — emits a server trait and a client stub for each `service` in the file, supporting all four streaming combinations

Output is plain Mojo structs implementing [`protobuf-runtime`](https://github.com/KiviCode/ouroboros/tree/main/packages/protobuf-runtime)'s `ProtoSerializable` trait. gRPC stubs link against [`mgrpc`](https://github.com/KiviCode/ouroboros/tree/main/packages/mgrpc).

## Install

```bash
pixi add protoc-gen-mojo
```

## Usage

```bash
pixi run protoc \
  --plugin=protoc-gen-mojo=$(pixi run which protoc-gen-mojo) \
  --mojo_out=gen \
  my_service.proto
```

For nested package outputs:

```bash
pixi run protoc \
  --plugin=protoc-gen-mojo=$(pixi run which protoc-gen-mojo) \
  --mojo_opt=module_prefix=my.pkg.gen. \
  --mojo_out=my/pkg/gen \
  my_service.proto
```

## Testing

```bash
bash packages/protoc-gen-mojo/tests/run_tests.sh
```

Runs 51 tests across runtime, codegen roundtrip, oneof, gRPC frame codec, and a live HTTPS transport smoke test.
