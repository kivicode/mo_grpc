"""End-to-end tests for streaming RPCs (server, client, bidi)."""

from std.os import getenv
from mo_grpc import GrpcChannel
from streaming import StreamBenchStub, Item, StreamSummary


def make_item(seq: Int, payload_size: Int) -> Item:
    var item = Item()
    item.seq = Int32(seq)
    var p = List[UInt8]()
    p.resize(payload_size, UInt8(0x42))
    item.payload = p^
    return item^


def test_server_stream(mut stub: StreamBenchStub) raises:
    var request = make_item(0, 16)
    var stream = stub.ServerStream(request)
    var count = 0
    while True:
        var msg = stream.recv()
        if not msg:
            break
        var item = msg.value().copy()
        var got_seq = Int(item.seq.value()) if item.seq else 0
        if got_seq != count:
            raise Error("expected seq=" + String(count) + " got=" + String(Int(item.seq.value())))
        count += 1
    if count != 10:
        raise Error("expected 10 items, got " + String(count))
    print("  PASS server-streaming: received " + String(count) + " items")


def test_client_stream(mut stub: StreamBenchStub) raises:
    var stream = stub.ClientStream()
    for i in range(5):
        stream.send(make_item(i, 32))
    var summary = stream.close_and_recv()
    var got_count = Int(summary.count.value()) if summary.count else 0
    var got_bytes = Int(summary.total_bytes.value()) if summary.total_bytes else 0
    if got_count != 5:
        raise Error("expected count=5, got " + String(got_count))
    if got_bytes != 160:
        raise Error("expected total_bytes=160, got " + String(got_bytes))
    print("  PASS client-streaming: sent 5 items, summary count=" + String(got_count) + " bytes=" + String(got_bytes))


def test_bidi_stream(mut stub: StreamBenchStub) raises:
    var stream = stub.BidiStream()
    for i in range(5):
        stream.send(make_item(i, 16))
    stream.close_send()
    var count = 0
    while True:
        var msg = stream.recv()
        if not msg:
            break
        var item = msg.value().copy()
        var got_seq = Int(item.seq.value()) if item.seq else 0
        if got_seq != count:
            raise Error("expected seq=" + String(count) + " got=" + String(Int(item.seq.value())))
        count += 1
    if count != 5:
        raise Error("expected 5 echoed items, got " + String(count))
    print("  PASS bidi-streaming: sent 5, received " + String(count) + " echoes")


def main() raises:
    var port = getenv("BENCH_PORT")
    if port == "":
        port = String("50443")
    var url = String("https://localhost:") + port
    var channel = GrpcChannel(url)
    var stub = StreamBenchStub(channel^)

    print("=== streaming RPC tests ===")

    test_server_stream(stub)
    test_client_stream(stub)
    test_bidi_stream(stub)

    print("all streaming tests passed")
