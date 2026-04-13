# mo_grpc

> ⚠️ **BETA.** This project is pre-1.0. APIs, generated-code layout, wire-format
> edge cases, and the gRPC client surface are still changing.

Monorepo for three tightly-coupled Mojo packages:

| Package           | Path                        | What it is                                                                                                                                                                                      |
| ----------------- | --------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `mo_protobuf`     | `packages/mo_protobuf/`     | Pure-Mojo protobuf wire-format runtime: `ProtoReader`, `ProtoWriter`, `ProtoSerializable` trait. Zero external deps.                                                                            |
| `mo_grpc`         | `packages/mo_grpc/`         | gRPC client + runtime. 5-byte frame codec, `GrpcChannel` with HTTP/2 + TLS over libcurl, server/client/bidi stream handles. Depends on `mo_protobuf`.                                           |
| `protoc-gen-mojo` | `packages/protoc-gen-mojo/` | `protoc` plugin: generates Mojo structs, oneof-union structs, and gRPC server traits + client stubs from `.proto` files. Depends on `mo_protobuf` at runtime (to parse `CodeGeneratorRequest`). |

`protoc-gen-mojo` bootstraps itself: it reads `google/protobuf/descriptor.proto` using the Mojo runtime it generates, then regenerates its own descriptor bindings.

## Feature support

Legend: ✅ implemented and tested · ⚠️ partial · ❌ not implemented

### Protobuf

| Feature                                      | Status | Notes                                                                                                |
| -------------------------------------------- | :----: | ---------------------------------------------------------------------------------------------------- |
| All 15 scalar types                          |   ✅   | int32/64, uint32/64, sint32/64 (zigzag), fixed32/64, sfixed32/64, float, double, bool, string, bytes |
| Messages + nested messages                   |   ✅   |                                                                                                      |
| Enums (file-level + nested)                  |   ✅   | `ProtoSerializable`, `parse` / `serialize`, `==` / `!=`                                              |
| `optional` fields (proto2 + proto3 optional) |   ✅   | Synthetic proto3 oneofs are detected and stay as `Optional[T]`                                       |
| `required` fields (proto2)                   |   ✅   | Type zero defaults in `__init__`                                                                     |
| `repeated` (unpacked)                        |   ✅   |                                                                                                      |
| `repeated` (packed)                          |   ✅   | Auto-detected via wire type at parse time                                                            |
| `map<K, V>`                                  |   ✅   | → `Dict[K, V]`, works for scalar/enum/message values                                                 |
| `oneof` enforcement                          |   ✅   | Discriminant-tagged union struct with typed factories + `is_X()` / `get_X()` accessors               |
| Cross-file imports                           |   ✅   | `--mojo_opt=module_prefix=...` for nested package layouts                                            |
| `reserved` fields / ranges                   |   ✅   | Silently skipped via `reader.skip_field`                                                             |
| Unknown fields                               |   ✅   | Preserved via `skip_field` — round-trip-safe                                                         |
| `default_value` (proto2)                     |   ❌   | Ignored; fields use type zero defaults                                                               |
| `extensions` (proto2)                        |   ❌   | Field descriptors parsed but not generated                                                           |
| `group` (proto2, deprecated)                 |   ❌   |                                                                                                      |
| Well-known types (`Any`, `Duration`, …)      |   ⚠️   | Generate correctly as plain messages; no special JSON / reflection glue                              |
| JSON serialization                           |   ❌   | Binary wire format only                                                                              |
| Text format                                  |   ❌   |                                                                                                      |
| Reflection API                               |   ❌   |                                                                                                      |

### gRPC

| Feature                              | Status | Notes                                                                        |
| ------------------------------------ | :----: | ---------------------------------------------------------------------------- |
| 5-byte frame codec (encode + decode) |   ✅   | `encode_grpc_frame`, `decode_grpc_frame`                                     |
| Client code generation               |   ✅   | `<Service>Stub` struct, one method per RPC                                   |
| Server trait generation              |   ✅   | `<Service>Servicer` trait with method stubs                                  |
| Unary ↔ unary                        |   ✅   | `GrpcChannel.unary_unary[Req, Resp]` — fully wired through libcurl           |
| HTTP/2                               |   ✅   | `CURL_HTTP_VERSION_2TLS` — negotiates HTTP/2 via ALPN, falls back to 1.1     |
| TLS / `https://`                     |   ✅   | Automatic via libcurl                                                        |
| Server-streaming RPC                 |   ❌   | Requires libcurl multi handle + incremental frame parsing (TODO)             |
| Client-streaming RPC                 |   ❌   | Requires libcurl read callback (TODO)                                        |
| Bidi-streaming RPC                   |   ❌   | Requires multi handle (TODO)                                                 |
| Server-side runtime (HTTP/2 server)  |   ❌   | Trait is generated; no server dispatcher yet                                 |
| gRPC status code / trailer parsing   |   ❌   | Transport raises on HTTP error; does not parse `grpc-status` trailer         |
| Deadlines / timeouts                 |   ❌   |                                                                              |
| Cancellation                         |   ❌   |                                                                              |
| Metadata (headers) — send            |   ⚠️   | Hard-coded to `Content-Type: application/grpc`, `TE: trailers`, `User-Agent` |
| Metadata (headers) — receive         |   ❌   | Write callback only captures the body                                        |
| mTLS / client certs                  |   ❌   | libcurl supports it; not exposed on `GrpcChannel`                            |
| Auth (bearer tokens, OAuth2)         |   ❌   |                                                                              |
| Compression (gzip, snappy)           |   ❌   | Frame codec always writes compression-flag = 0                               |
| Retry / reconnection                 |   ❌   |                                                                              |
| gRPC reflection                      |   ❌   |                                                                              |

## Dev workflow

The root `pixi.toml` is a dev workspace that pins `modular`, `mojo-curl`, and `curl_wrapper` for running everything out of a source checkout.

```bash
# install pixi if needed
curl -fsSL https://pixi.sh/install.sh | sh

# install the workspace deps
pixi install

# run the full test suite (51 tests)
pixi run test
```

## Building local `.conda` artifacts

Each `packages/*/pixi.toml` declares a publishable `[package]` using the `pixi-build-mojo` backend. Cross-package deps inside the monorepo use `path = "../other-package"` so source changes are picked up immediately. Build a single package locally with:

```bash
cd packages/mo_protobuf && pixi run build
# produces mo_protobuf-0.1.0-<hash>_0.conda in the package directory
```

## Using `protoc-gen-mojo`

Once installed, the plugin binary is on `PATH` inside the pixi env:

```bash
pixi run protoc \
  --plugin=protoc-gen-mojo=$(pixi run which protoc-gen-mojo) \
  --mojo_out=gen \
  my_service.proto
```

For multi-file outputs rooted under an existing package, pass `--mojo_opt=module_prefix=my.pkg.gen.`.

## Running the test suite for a specific package

```bash
bash packages/protoc-gen-mojo/tests/run_tests.sh
```
