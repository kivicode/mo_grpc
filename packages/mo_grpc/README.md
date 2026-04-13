# mo_grpc

gRPC client + runtime for Mojo.

## Contents

- `encode_grpc_frame` / `decode_grpc_frame` — 5-byte gRPC DATA frame codec
- `GrpcChannel.unary_unary[Req, Resp]` — fully working HTTP/2 + TLS client via libcurl
- `GrpcServerStream`, `GrpcClientStream`, `GrpcBidiStream` — stream handle types (unary is implemented; streaming variants require the libcurl multi handle and are TODO)
- `http_post(url, body) -> Bytes` — low-level HTTPS POST helper

Depends on [`mo_protobuf`](https://github.com/kivicode/mo_grpc/tree/main/packages/mo_protobuf), `mojo-curl`, and the `curl_wrapper` C shim.

## Install

```bash
pixi add mo_grpc
```

## Example

```mojo
from mo_grpc import GrpcChannel
from my.generated.helloworld import HelloRequest, HelloReply, GreeterStub

var channel = GrpcChannel("https://api.example.com:443")
var stub    = GreeterStub(channel)

var req = HelloRequest()
req.name = Optional[String]("world")

var reply = stub.SayHello(req)
print(reply.message.value())
```
