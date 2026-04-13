# ouroboros

Monorepo for three tightly-coupled Mojo packages:

| Package             | Path                                  | What it is |
|---------------------|---------------------------------------|------------|
| `mo_protobuf`  | `packages/mo_protobuf/`          | Pure-Mojo protobuf wire-format runtime: `ProtoReader`, `ProtoWriter`, `ProtoSerializable` trait. Zero external deps. |
| `mo_grpc`             | `packages/mo_grpc/`                     | gRPC client + runtime. 5-byte frame codec, `GrpcChannel` with HTTP/2 + TLS over libcurl, server/client/bidi stream handles. Depends on `mo_protobuf`. |
| `protoc-gen-mojo`   | `packages/protoc-gen-mojo/`           | `protoc` plugin: generates Mojo structs, oneof-union structs, and gRPC server traits + client stubs from `.proto` files. Depends on `mo_protobuf` at runtime (to parse `CodeGeneratorRequest`). |

Named after the [ouroboros](https://en.wikipedia.org/wiki/Ouroboros) because the generator bootstraps itself: it reads `google/protobuf/descriptor.proto` using the Mojo runtime it generates, then regenerates its own descriptor bindings.

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

## Per-package layout

Each `packages/*/pixi.toml` declares a publishable `[package]` using the `pixi-build-mojo` backend. Cross-package deps inside the monorepo use `path = "../other-package"` so source changes are picked up immediately.

## Building & publishing

The pattern follows [`mojo-curl`](https://github.com/thatstoasty/mojo-curl):

```bash
# build all three packages into .conda artifacts
pixi run build-all

# or build one at a time
cd packages/mo_protobuf && pixi run build
cd packages/mo_grpc            && pixi run build
cd packages/protoc-gen-mojo  && pixi run build
```

This produces a `.conda` file in each package directory. To publish to the [`mojo-community`](https://prefix.dev/channels/mojo-community) channel on prefix.dev:

```bash
# one-time: get an API token from https://prefix.dev/settings/api-keys
pixi auth login prefix.dev --token <YOUR_TOKEN>

# publish each package
cd packages/mo_protobuf && pixi run publish
cd packages/mo_grpc            && pixi run publish
cd packages/protoc-gen-mojo  && pixi run publish
```

Once published, consumers in any pixi project add them with:

```bash
# ensure the channel is in pixi.toml:
#   channels = [..., "https://repo.prefix.dev/mojo-community"]
pixi add mo_protobuf
pixi add mo_grpc
pixi add protoc-gen-mojo
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
# protoc-gen-mojo (51 tests: runtime, codegen, oneof, gRPC frame, transport)
bash packages/protoc-gen-mojo/tests/run_tests.sh
```
