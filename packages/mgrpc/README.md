# mgrpc

gRPC client + runtime for Mojo.

## Contents

- `encode_grpc_frame` / `decode_grpc_frame` — 5-byte gRPC DATA frame codec
- `GrpcChannel.unary_unary[Req, Resp]` — fully working HTTP/2 + TLS client via libcurl
- `GrpcServerStream`, `GrpcClientStream`, `GrpcBidiStream` — stream handle types (unary is implemented; streaming variants require the libcurl multi handle and are TODO)
- `http_post(url, body) -> Bytes` — low-level HTTPS POST helper

Depends on [`protobuf-runtime`](https://github.com/KiviCode/ouroboros/tree/main/packages/protobuf-runtime), `mojo-curl`, and the `curl_wrapper` C shim.

## Install

```bash
pixi add mgrpc
```

## Example

```mojo
from mgrpc import GrpcChannel
from my.generated.helloworld import HelloRequest, HelloReply, GreeterStub

var channel = GrpcChannel("https://api.example.com:443")
var stub    = GreeterStub(channel)

var req = HelloRequest()
req.name = Optional[String]("world")

var reply = stub.SayHello(req)
print(reply.message.value())
```
