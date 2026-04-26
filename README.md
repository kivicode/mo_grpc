<a name="readme-top"></a>
<br />

<div align="center">
    <img src="assets/image.png" alt="Logo" width="300" height="300">

  <h3 align="center">MoGRPC / MoProtobuf</h3>

  <p align="center">
    🔥 A pure-Mojo implementation of protobuf and gRPC 🔥
    <br/>

![Written in Mojo][language-shield]
[![MIT License][license-shield]][license-url]
[![CodeQL](https://github.com/kivicode/mo_grpc/actions/workflows/github-code-scanning/codeql/badge.svg)](https://github.com/kivicode/mo_grpc/actions/workflows/github-code-scanning/codeql)

<br/>

[![Contributors Welcome][contributors-shield]][contributors-url]

  </p>
</div>

> ⚠️ **BETA.** This project is pre-1.0. APIs, generated-code layout, wire-format
> edge cases, and the gRPC client surface are still changing.

Monorepo for three tightly-coupled Mojo packages:

| Package           | Path                        | What it is                                                                                                                                                                                      |
| ----------------- | --------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `mo_protobuf`     | `packages/mo_protobuf/`     | Pure-Mojo protobuf wire-format runtime: `ProtoReader`, `ProtoWriter`, `ProtoSerializable` trait. Zero external deps.                                                                            |
| `mo_grpc`         | `packages/mo_grpc/`         | gRPC client + runtime. 5-byte frame codec, `GrpcChannel` with HTTP/2 + TLS via native sockets + OpenSSL. Unary + server/client/bidi streaming. Depends on `mo_protobuf`.                        |
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

| Feature                              | Status | Notes                                                                                                                                                          |
| ------------------------------------ | :----: | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 5-byte frame codec (encode + decode) |   ✅   | `encode_grpc_frame`, `decode_grpc_frame`                                                                                                                       |
| Client code generation               |   ✅   | `<Service>Stub` struct, one method per RPC                                                                                                                     |
| Server trait generation              |   ✅   | `<Service>Servicer` trait with method stubs                                                                                                                    |
| Unary <-> unary                      |   ✅   | `GrpcChannel.unary_unary[Req, Resp]` - fully wired, HTTP/2 + TLS                                                                                               |
| HTTP/2                               |   ✅   | Pure-Mojo HTTP/2 client: connection preface, SETTINGS, HPACK, DATA, WINDOW_UPDATE, PING, GOAWAY                                                                |
| TLS / `https://`                     |   ✅   | OpenSSL FFI via `DLHandle.get_function`; ALPN `h2` negotiation, SNI, system CA store                                                                           |
| Server-streaming RPC                 |   ✅   | `GrpcChannel.unary_stream` → `GrpcServerStream[Resp]` with `recv()` iterator                                                                                   |
| Client-streaming RPC                 |   ✅   | `GrpcChannel.stream_unary` → `GrpcClientStream[Req, Resp]` with `send()` + `close_and_recv()`                                                                  |
| Bidi-streaming RPC                   |   ✅   | `GrpcChannel.bidi` → `GrpcBidiStream[Req, Resp]` with `send()` + `recv()` + `close_send()`                                                                     |
| Server-side runtime (HTTP/2 server)  |   ✅   | `GrpcServer` with `H2ServerConnection`, `serve_unary`, `ServerStreamWriter`; single-threaded accept loop                                                       |
| gRPC status code / trailer parsing   |   ✅   | `grpc-status` + `grpc-message` parsed from trailers / trailers-only headers; non-OK raises typed `GrpcError`                                                   |
| Deadlines / timeouts                 |   ✅   | Per-call `timeout_ms`; sets `SO_RCVTIMEO` + `grpc-timeout` header; expiry → `GrpcError(DEADLINE_EXCEEDED)`                                                     |
| Cancellation                         |   ✅   | `stream.cancel()` sends RST_STREAM; incoming RST_STREAM raises `GrpcError(CANCELLED)`                                                                          |
| Metadata (headers) - send            |   ✅   | `metadata: Dict[String, String]` per call; lowercased + validated per gRPC spec; `grpc-*`, HTTP/2 pseudo-headers, transport-managed names rejected client-side |
| Metadata (headers) - receive         |   ✅   | Response headers + trailers parsed from HPACK-encoded HTTP/2 HEADERS frames                                                                                    |
| mTLS / client certs                  |   ✅   | `ServerTlsSocket` with `ca_path` for client cert verification; `TlsSocket` with client cert/key params                                                         |
| Auth (bearer tokens, OAuth2)         |   ✅   | Pass `authorization: Bearer <token>` (or any custom auth header) via the `metadata` parameter                                                                  |
| Compression (gzip, snappy)           |   ❌   | Frame codec always writes compression-flag = 0                                                                                                                 |
| Retry / reconnection                 |   ❌   |                                                                                                                                                                |
| gRPC reflection                      |   ❌   |                                                                                                                                                                |

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

There are four bench categories, all over loopback HTTP/2 + TLS:

- **tiny** — 16-byte echo (`PingRequest{seq, payload}`), 5,000 iterations.
  Measures per-call overhead: framing, connection reuse, scheduler latency.
- **heavy** — deeply nested ~14 KB `Document` with `optional`, `repeated`,
  `oneof`, `map`, nested messages, recursive `Span` tree (depth 3, fanout 3),
  500 iterations. Stresses the protobuf encoder + parser.
- **streaming** — server/client/bidi streaming RPCs, 5,000 iterations each.
  Measures streaming frame overhead and incremental read/write performance.

Numbers below are medians across 3 back-to-back runs of the harness.

**Hardware:** Apple M3 Max, 14 cores, 36 GB, macOS 15.6.1.
**Toolchain:** Mojo 0.26.2.0 (`mojo build -O3`), grpcio 1.80.0, Python 3.12.
**Transport:** Pure-Mojo HTTP/2 + OpenSSL (no libcurl, no nghttp2).

#### Unary RPCs

| bench | client        | iterations | body size |      throughput |     median |        p95 |        p99 |
| ----- | ------------- | ---------- | --------: | --------------: | ---------: | ---------: | ---------: |
| tiny  | python grpcio | 5,000      |      16 B |     5,890 req/s |     164 µs |     221 µs |     254 µs |
| tiny  | **mo_grpc**   | 5,000      |      16 B | **9,117 req/s** | **104 µs** | **146 µs** | **174 µs** |
| heavy | python grpcio | 500        |  14,386 B |     3,532 req/s |     275 µs |     346 µs |     414 µs |
| heavy | **mo_grpc**   | 500        |  16,739 B | **3,771 req/s** | **249 µs** | **304 µs** | **329 µs** |

#### Streaming RPCs

| bench         | client        | iterations |    items/call |        throughput |     median |        p95 |        p99 |
| ------------- | ------------- | ---------- | ------------: | ----------------: | ---------: | ---------: | ---------: |
| server-stream | python grpcio | 5,000      |       10 recv |     1,782 calls/s |     553 µs |     655 µs |     743 µs |
| server-stream | **mo_grpc**   | 5,000      |       10 recv | **1,992 calls/s** | **448 µs** | **537 µs** | **609 µs** |
| client-stream | python grpcio | 5,000      |        5 send |     2,611 calls/s |     377 µs |     445 µs |     603 µs |
| client-stream | **mo_grpc**   | 5,000      |        5 send | **5,148 calls/s** | **184 µs** | **264 µs** | **326 µs** |
| bidi-stream   | python grpcio | 5,000      | 5 send+5 recv |     1,559 calls/s |     638 µs |     715 µs |     762 µs |
| bidi-stream   | **mo_grpc**   | 5,000      | 5 send+5 recv | **1,776 calls/s** | **399 µs** | **508 µs** | **670 µs** |

## Dev workflow

The root `pixi.toml` is a dev workspace that pins `modular` and `openssl` for running everything out of a source checkout.

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

<!-- MARKDOWN LINKS & IMAGES -->
<!-- https://www.markdownguide.org/basic-syntax/#reference-style-links -->

[language-shield]: https://img.shields.io/badge/language-mojo-orange
[license-shield]: https://img.shields.io/github/license/kivicode/mo_grpc?logo=github
[license-url]: https://github.com/kivicode/mo_grpc/blob/main/LICENSE
[contributors-shield]: https://img.shields.io/badge/contributors-welcome!-blue
[contributors-url]: https://github.com/kivicode/mo_grpc#contributing
