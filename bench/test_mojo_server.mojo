"""Mojo gRPC echo server for testing."""

from std.os import getenv
from mo_grpc import GrpcServer
from echo import PingRequest, PingReply, EchoServicer, add_EchoServicer_to_server


struct MyEcho(EchoServicer):
    fn __init__(out self):
        pass

    def Ping(self, request: PingRequest) raises -> PingReply:
        var reply = PingReply()
        reply.seq = request.seq
        if request.payload:
            reply.payload = request.payload.value().copy()
        return reply^


def main() raises:
    var port_s = getenv("MOJO_SERVER_PORT")
    if port_s == "":
        port_s = String("50553")

    var server = GrpcServer(
        String("127.0.0.1"), UInt16(atol(port_s)),
        String("bench/certs/server.crt"),
        String("bench/certs/server.key"),
    )
    var echo = MyEcho()
    add_EchoServicer_to_server(echo, server)

    print("mojo-server listening on 127.0.0.1:" + port_s, flush=True)
    server.serve_one()
