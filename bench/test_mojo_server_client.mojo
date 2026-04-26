"""Test: Mojo client → Mojo server round-trip."""

from std.os import getenv
from mo_grpc import GrpcChannel
from echo import EchoStub, PingRequest


def main() raises:
    var port_s = getenv("MOJO_SERVER_PORT")
    if port_s == "":
        port_s = String("50553")
    var url = String("https://localhost:") + port_s
    var stub = EchoStub(GrpcChannel(url))

    print("=== Mojo server tests (Mojo client → Mojo server) ===")

    # Test 1: basic echo
    var req1 = PingRequest()
    req1.seq = Int32(42)
    var reply1 = stub.Ping(req1)
    var got_seq = Int(reply1.seq.value()) if reply1.seq else -1
    if got_seq != 42:
        raise Error("FAIL echo: expected seq=42, got " + String(got_seq))
    print("  PASS echo round-trip (seq=42)")

    # Test 2: multiple requests
    for i in range(10):
        var req = PingRequest()
        req.seq = Int32(i)
        var reply = stub.Ping(req)
        var s = Int(reply.seq.value()) if reply.seq else -1
        if s != i:
            raise Error("FAIL sequential: expected " + String(i) + " got " + String(s))
    print("  PASS 10 sequential requests on same connection")

    # Test 3: with payload
    var req3 = PingRequest()
    req3.seq = Int32(99)
    var payload = List[UInt8]()
    payload.resize(256, UInt8(0x42))
    req3.payload = payload^
    var reply3 = stub.Ping(req3)
    var got3 = Int(reply3.seq.value()) if reply3.seq else -1
    if got3 != 99:
        raise Error("FAIL payload: expected seq=99, got " + String(got3))
    var got_len = len(reply3.payload.value()) if reply3.payload else 0
    if got_len != 256:
        raise Error("FAIL payload length: expected 256, got " + String(got_len))
    print("  PASS echo with 256-byte payload")

    print("all Mojo server tests passed")
