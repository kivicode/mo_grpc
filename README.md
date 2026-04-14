# mo_grpc

> ⚠️ **BETA.** This project is pre-1.0. APIs, generated-code layout, wire-format
> edge cases, and the gRPC client surface are still changing.

Monorepo for three tightly-coupled Mojo packages:

| Package           | Path                        | What it is                                                                                                                                                                                      |
| ----------------- | --------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `mo_protobuf`     | `packages/mo_protobuf/`     | Pure-Mojo protobuf wire-format runtime: `ProtoReader`, `ProtoWriter`, `ProtoSerializable` trait. Zero external deps.                                                                            |
| `mo_grpc`         | `packages/mo_grpc/`         | gRPC client + runtime. 5-byte frame codec, `GrpcChannel` with HTTP/2 + TLS over libcurl, server/client/bidi stream handles. Depends on `mo_protobuf`.                                           |
| `protoc-gen-mojo` | `packages/protoc-gen-mojo/` | `protoc` plugin: generates Mojo structs, oneof-union structs, and gRPC server traits + client stubs from `.proto` files. Depends on `mo_protobuf` at runtime (to parse `CodeGeneratorRequest`). |

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
| Unknown fields                               |   ✅   | Preserved via `skip_field` - round-trip-safe                                                         |
| `default_value` (proto2)                     |   ❌   | Ignored; fields use type zero defaults                                                               |
| `extensions` (proto2)                        |   ❌   | Field descriptors parsed but not generated                                                           |
| `group` (proto2, deprecated)                 |   ❌   |                                                                                                      |
| Well-known types (`Any`, `Duration`, …)      |   ⚠️   | Generate correctly as plain messages; no special JSON / reflection glue                              |
| JSON serialization                           |   ❌   | Binary wire format only                                                                              |
| Text format                                  |   ❌   |                                                                                                      |
| Reflection API                               |   ❌   |                                                                                                      |

### gRPC

| Feature                              | Status | Notes                                                                                                        |
| ------------------------------------ | :----: | ------------------------------------------------------------------------------------------------------------ |
| 5-byte frame codec (encode + decode) |   ✅   | `encode_grpc_frame`, `decode_grpc_frame`                                                                     |
| Client code generation               |   ✅   | `<Service>Stub` struct, one method per RPC                                                                   |
| Server trait generation              |   ✅   | `<Service>Servicer` trait with method stubs                                                                  |
| Unary ↔ unary                        |   ✅   | `GrpcChannel.unary_unary[Req, Resp]` - fully wired through libcurl                                           |
| HTTP/2                               |   ✅   | `CURL_HTTP_VERSION_2TLS` - negotiates HTTP/2 via ALPN, falls back to 1.1                                     |
| TLS / `https://`                     |   ✅   | Automatic via libcurl                                                                                        |
| Server-streaming RPC                 |   ❌   | Requires libcurl multi handle + incremental frame parsing (TODO)                                             |
| Client-streaming RPC                 |   ❌   | Requires libcurl read callback (TODO)                                                                        |
| Bidi-streaming RPC                   |   ❌   | Requires multi handle (TODO)                                                                                 |
| Server-side runtime (HTTP/2 server)  |   ❌   | Trait is generated; no server dispatcher yet                                                                 |
| gRPC status code / trailer parsing   |   ✅   | `grpc-status` + `grpc-message` parsed from trailers / trailers-only headers; non-OK raises typed `GrpcError` |
| Deadlines / timeouts                 |   ✅   | Per-call `timeout_ms` on every generated stub method; sets `CURLOPT_TIMEOUT_MS` and sends `grpc-timeout` for server enforcement; expiry → `GrpcError(DEADLINE_EXCEEDED)` |
| Cancellation                         |   ❌   |                                                                                                              |
| Metadata (headers) - send            |   ✅   | `metadata: Dict[String, String]` per call; lowercased + validated per gRPC spec; `grpc-*`, HTTP/2 pseudo-headers, transport-managed names rejected client-side |
| Metadata (headers) - receive         |   ❌   | Write callback only captures the body                                                                        |
| mTLS / client certs                  |   ❌   | libcurl supports it; not exposed on `GrpcChannel`                                                            |
| Auth (bearer tokens, OAuth2)         |   ✅   | Pass `authorization: Bearer <token>` (or any custom auth header) via the `metadata` parameter                |
| Compression (gzip, snappy)           |   ❌   | Frame codec always writes compression-flag = 0                                                               |
| Retry / reconnection                 |   ❌   |                                                                                                              |
| gRPC reflection                      |   ❌   |                                                                                                              |

## Benchmarks

`bench/run.sh` is an end-to-end harness: it generates the proto stubs (Python

- Mojo) from `bench/proto/*.proto`, builds the Mojo client binaries with
  `mojo build -O3`, brings up a local TLS gRPC echo server, and runs both the
  Python `grpcio` client and the `mo_grpc` client against the same server.
  Cleans up the server (and any stragglers `uv run` leaves behind) on any exit.

```bash
bash bench/run.sh
# overrides:
BENCH_N=10000 HEAVY_N=1000 BENCH_PORT=50443 bash bench/run.sh
```

There are two benches, both unary RPCs over loopback HTTP/2 + TLS:

- **tiny** — a 16-byte echo (`PingRequest{seq, payload}`), 5,000 iterations.
  Measures per-call overhead: framing, libcurl handle reuse, scheduler latency.
- **heavy** — a deeply nested ~14 KB `Document` with `optional`, `repeated`,
  `oneof`, `map`, nested messages, recursive `Span` tree (depth 3, fanout 3),
  500 iterations. Stresses the protobuf encoder + parser.

Numbers below are medians across 3 back-to-back runs of the harness.

**Hardware:** Apple M3 Max, 14 cores, 36 GB, macOS 15.6.1.
**Toolchain:** Mojo 0.26.2.0 (`mojo build -O3`), grpcio 1.80.0, Python 3.12.

| bench | client        | iterations | body size |      throughput |     median |        p95 |        p99 |
| ----- | ------------- | ---------- | --------: | --------------: | ---------: | ---------: | ---------: |
| tiny  | python grpcio | 5,000      |      16 B |     5,995 req/s |     161 µs |     217 µs |     247 µs |
| tiny  | **mo_grpc**   | 5,000      |      16 B | **6,577 req/s** | **148 µs** | **190 µs** | **228 µs** |
| heavy | python grpcio | 500        |  14,386 B |     3,520 req/s |     268 µs |     375 µs |     462 µs |
| heavy | **mo_grpc**   | 500        |  16,739 B |     3,382 req/s |     278 µs |     358 µs |     479 µs |

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
