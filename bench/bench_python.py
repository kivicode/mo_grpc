# /// script
# requires-python = ">=3.10"
# dependencies = ["grpcio>=1.60", "protobuf>=4.25"]
# ///
"""Benchmark the standard Python grpcio client against the local TLS echo server."""
import os
import sys
import time
import statistics

import grpc

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "gen"))
import echo_pb2
import echo_pb2_grpc

HERE = os.path.dirname(os.path.abspath(__file__))
CERT = os.path.join(HERE, "certs", "server.crt")


def main():
    n = int(os.environ.get("BENCH_N", "2000"))
    port = int(os.environ.get("BENCH_PORT", "50443"))
    payload_size = int(os.environ.get("BENCH_PAYLOAD", "16"))
    payload = b"x" * payload_size

    with open(CERT, "rb") as f:
        crt = f.read()
    creds = grpc.ssl_channel_credentials(root_certificates=crt)

    options = (
        ("grpc.ssl_target_name_override", "localhost"),
        ("grpc.default_authority", "localhost"),
    )
    channel = grpc.secure_channel(f"127.0.0.1:{port}", creds, options=options)
    grpc.channel_ready_future(channel).result(timeout=5.0)
    stub = echo_pb2_grpc.EchoStub(channel)

    # warmup
    for i in range(50):
        stub.Ping(echo_pb2.PingRequest(seq=i, payload=payload))

    samples = []
    t_total = time.perf_counter()
    for i in range(n):
        t0 = time.perf_counter_ns()
        reply = stub.Ping(echo_pb2.PingRequest(seq=i, payload=payload))
        samples.append(time.perf_counter_ns() - t0)
        assert reply.seq == i
    elapsed = time.perf_counter() - t_total

    samples.sort()
    median_us = samples[len(samples) // 2] / 1000
    p95_us = samples[int(len(samples) * 0.95)] / 1000
    p99_us = samples[int(len(samples) * 0.99)] / 1000
    mean_us = statistics.mean(samples) / 1000
    rps = n / elapsed

    print("=== python grpcio (sync stub, single channel) ===")
    print(f"  iterations  : {n}")
    print(f"  payload     : {payload_size} bytes")
    print(f"  total       : {elapsed*1000:.1f} ms")
    print(f"  throughput  : {rps:,.0f} req/s")
    print(f"  mean        : {mean_us:.1f} us")
    print(f"  median      : {median_us:.1f} us")
    print(f"  p95         : {p95_us:.1f} us")
    print(f"  p99         : {p99_us:.1f} us")

    channel.close()


if __name__ == "__main__":
    main()
