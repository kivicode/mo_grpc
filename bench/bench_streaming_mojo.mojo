"""Benchmark mo_grpc streaming RPCs against the local TLS server."""

from std.time import perf_counter_ns
from std.os import getenv
from mo_grpc import GrpcChannel
from mo_protobuf.common import Bytes
from streaming import StreamBenchStub, Item, StreamSummary


def parse_int(s: String, fallback: Int) -> Int:
    if len(s) == 0:
        return fallback
    try:
        return Int(atol(s))
    except:
        return fallback


def make_item(seq: Int, payload_size: Int) -> Item:
    var item = Item()
    item.seq = Int32(seq)
    var p = List[UInt8]()
    p.resize(payload_size, UInt8(0x78))
    item.payload = p^
    return item^


def main() raises:
    var n = parse_int(getenv("BENCH_N", "1000"), 1000)
    var port_s = getenv("BENCH_PORT", "50443")
    var stream_count = parse_int(getenv("STREAM_COUNT", "10"), 10)

    var url = String("https://localhost:") + port_s
    var stub = StreamBenchStub(GrpcChannel(url))

    # --- server-streaming bench ---
    # warmup
    for _ in range(10):
        var stream = stub.ServerStream(make_item(0, 16))
        while True:
            var msg = stream.recv()
            if not msg:
                break

    var ss_samples = List[Int](capacity=n)
    var ss_total = Int(perf_counter_ns())
    for i in range(n):
        var t0 = Int(perf_counter_ns())
        var stream = stub.ServerStream(make_item(i, 16))
        var count = 0
        while True:
            var msg = stream.recv()
            if not msg:
                break
            count += 1
        ss_samples.append(Int(perf_counter_ns()) - t0)
    var ss_elapsed_ns = Int(perf_counter_ns()) - ss_total

    sort(ss_samples)
    var ss_median = Float64(ss_samples[len(ss_samples) // 2]) / 1000.0
    var ss_p95 = Float64(ss_samples[Int(Float64(len(ss_samples)) * 0.95)]) / 1000.0
    var ss_p99 = Float64(ss_samples[Int(Float64(len(ss_samples)) * 0.99)]) / 1000.0
    var ss_rps = Float64(n) / (Float64(ss_elapsed_ns) / 1_000_000_000.0)

    print("=== mo_grpc server-streaming (release, " + String(stream_count) + " items/call) ===")
    print("  iterations  : " + String(n))
    print("  items/call  : " + String(stream_count))
    print("  total       : " + String(Float64(ss_elapsed_ns) / 1_000_000.0) + " ms")
    print("  throughput  : " + String(ss_rps) + " calls/s")
    print("  median      : " + String(ss_median) + " us")
    print("  p95         : " + String(ss_p95) + " us")
    print("  p99         : " + String(ss_p99) + " us")

    # --- client-streaming bench ---
    for _ in range(10):
        var stream = stub.ClientStream()
        for j in range(5):
            stream.send(make_item(j, 16))
        _ = stream.close_and_recv()

    var cs_samples = List[Int](capacity=n)
    var cs_total = Int(perf_counter_ns())
    for i in range(n):
        var t0 = Int(perf_counter_ns())
        var stream = stub.ClientStream()
        for j in range(5):
            stream.send(make_item(j, 16))
        _ = stream.close_and_recv()
        cs_samples.append(Int(perf_counter_ns()) - t0)
    var cs_elapsed_ns = Int(perf_counter_ns()) - cs_total

    sort(cs_samples)
    var cs_median = Float64(cs_samples[len(cs_samples) // 2]) / 1000.0
    var cs_p95 = Float64(cs_samples[Int(Float64(len(cs_samples)) * 0.95)]) / 1000.0
    var cs_p99 = Float64(cs_samples[Int(Float64(len(cs_samples)) * 0.99)]) / 1000.0
    var cs_rps = Float64(n) / (Float64(cs_elapsed_ns) / 1_000_000_000.0)

    print("\n=== mo_grpc client-streaming (release, 5 items/call) ===")
    print("  iterations  : " + String(n))
    print("  items/call  : 5")
    print("  total       : " + String(Float64(cs_elapsed_ns) / 1_000_000.0) + " ms")
    print("  throughput  : " + String(cs_rps) + " calls/s")
    print("  median      : " + String(cs_median) + " us")
    print("  p95         : " + String(cs_p95) + " us")
    print("  p99         : " + String(cs_p99) + " us")

    # --- bidi-streaming bench ---
    for _ in range(10):
        var stream = stub.BidiStream()
        for j in range(5):
            stream.send(make_item(j, 16))
        stream.close_send()
        while True:
            var msg = stream.recv()
            if not msg:
                break

    var bi_samples = List[Int](capacity=n)
    var bi_total = Int(perf_counter_ns())
    for i in range(n):
        var t0 = Int(perf_counter_ns())
        var stream = stub.BidiStream()
        for j in range(5):
            stream.send(make_item(j, 16))
        stream.close_send()
        while True:
            var msg = stream.recv()
            if not msg:
                break
        bi_samples.append(Int(perf_counter_ns()) - t0)
    var bi_elapsed_ns = Int(perf_counter_ns()) - bi_total

    sort(bi_samples)
    var bi_median = Float64(bi_samples[len(bi_samples) // 2]) / 1000.0
    var bi_p95 = Float64(bi_samples[Int(Float64(len(bi_samples)) * 0.95)]) / 1000.0
    var bi_p99 = Float64(bi_samples[Int(Float64(len(bi_samples)) * 0.99)]) / 1000.0
    var bi_rps = Float64(n) / (Float64(bi_elapsed_ns) / 1_000_000_000.0)

    print("\n=== mo_grpc bidi-streaming (release, 5 items each way) ===")
    print("  iterations  : " + String(n))
    print("  items/call  : 5 send + 5 recv")
    print("  total       : " + String(Float64(bi_elapsed_ns) / 1_000_000.0) + " ms")
    print("  throughput  : " + String(bi_rps) + " calls/s")
    print("  median      : " + String(bi_median) + " us")
    print("  p95         : " + String(bi_p95) + " us")
    print("  p99         : " + String(bi_p99) + " us")
