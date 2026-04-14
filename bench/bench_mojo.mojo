"""Benchmark mo_grpc against the local TLS echo server."""

from std.time import perf_counter_ns
from std.os import getenv
from mo_grpc import GrpcChannel
from mo_protobuf.common import Bytes
from echo import EchoStub, PingRequest, PingReply


def parse_int(s: String, fallback: Int) -> Int:
    if len(s) == 0:
        return fallback
    try:
        return Int(atol(s))
    except:
        return fallback


def main() raises:
    var n = parse_int(getenv("BENCH_N", "2000"), 2000)
    var port_s = getenv("BENCH_PORT", "50443")
    var payload_size = parse_int(getenv("BENCH_PAYLOAD", "16"), 16)

    var url = String("https://localhost:") + port_s
    var stub = EchoStub(GrpcChannel(url))

    var payload = Bytes()
    payload.reserve(payload_size)
    for _ in range(payload_size):
        payload.append(UInt8(120))  # 'x'

    # warmup
    for i in range(50):
        var req = PingRequest(Int32(i), payload.copy())
        _ = stub.Ping(req)

    var samples = List[Int](capacity=n)
    var t_total = Int(perf_counter_ns())
    for i in range(n):
        var req = PingRequest(Int32(i), payload.copy())
        var t0 = Int(perf_counter_ns())
        var reply = stub.Ping(req)
        samples.append(Int(perf_counter_ns()) - t0)
        if reply.seq.value() != Int32(i):
            raise Error("seq mismatch")
    var elapsed_ns = Int(perf_counter_ns()) - t_total

    sort(samples)
    var median_us = Float64(samples[len(samples) // 2]) / 1000.0
    var p95_us = Float64(samples[Int(Float64(len(samples)) * 0.95)]) / 1000.0
    var p99_us = Float64(samples[Int(Float64(len(samples)) * 0.99)]) / 1000.0
    var sum_ns = 0
    for v in samples:
        sum_ns += v
    var mean_us = Float64(sum_ns) / Float64(len(samples)) / 1000.0
    var elapsed_ms = Float64(elapsed_ns) / 1_000_000.0
    var rps = Float64(n) / (Float64(elapsed_ns) / 1_000_000_000.0)

    print("=== mo_grpc (release, single channel, persistent libcurl handle) ===")
    print("  iterations  : " + String(n))
    print("  payload     : " + String(payload_size) + " bytes")
    print("  total       : " + String(elapsed_ms) + " ms")
    print("  throughput  : " + String(rps) + " req/s")
    print("  mean        : " + String(mean_us) + " us")
    print("  median      : " + String(median_us) + " us")
    print("  p95         : " + String(p95_us) + " us")
    print("  p99         : " + String(p99_us) + " us")
