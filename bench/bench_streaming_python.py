# /// script
# requires-python = ">=3.10"
# dependencies = ["grpcio>=1.60", "protobuf>=4.25"]
# ///
"""Benchmark Python grpcio streaming RPCs against the local TLS server."""
import os
import sys
import time
import statistics

import grpc

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "gen"))
import streaming_pb2
import streaming_pb2_grpc

HERE = os.path.dirname(os.path.abspath(__file__))
CERT = os.path.join(HERE, "certs", "server.crt")


def main():
    n = int(os.environ.get("BENCH_N", "1000"))
    port = int(os.environ.get("BENCH_PORT", "50443"))
    stream_count = int(os.environ.get("STREAM_COUNT", "10"))

    with open(CERT, "rb") as f:
        crt = f.read()
    creds = grpc.ssl_channel_credentials(root_certificates=crt)
    options = (
        ("grpc.ssl_target_name_override", "localhost"),
        ("grpc.default_authority", "localhost"),
    )
    channel = grpc.secure_channel(f"127.0.0.1:{port}", creds, options=options)
    grpc.channel_ready_future(channel).result(timeout=5.0)
    stub = streaming_pb2_grpc.StreamBenchStub(channel)

    payload = b"x" * 16

    # --- server-streaming ---
    for _ in range(10):
        list(stub.ServerStream(streaming_pb2.Item(seq=0, payload=payload)))

    samples = []
    t_total = time.perf_counter()
    for i in range(n):
        t0 = time.perf_counter_ns()
        items = list(stub.ServerStream(streaming_pb2.Item(seq=i, payload=payload)))
        samples.append(time.perf_counter_ns() - t0)
    elapsed = time.perf_counter() - t_total

    samples.sort()
    median_us = samples[len(samples) // 2] / 1000
    p95_us = samples[int(len(samples) * 0.95)] / 1000
    p99_us = samples[int(len(samples) * 0.99)] / 1000
    rps = n / elapsed

    print(f"=== python grpcio server-streaming ({stream_count} items/call) ===")
    print(f"  iterations  : {n}")
    print(f"  items/call  : {stream_count}")
    print(f"  total       : {elapsed*1000:.1f} ms")
    print(f"  throughput  : {rps:,.0f} calls/s")
    print(f"  median      : {median_us:.1f} us")
    print(f"  p95         : {p95_us:.1f} us")
    print(f"  p99         : {p99_us:.1f} us")

    # --- client-streaming ---
    def gen_items(count):
        for j in range(count):
            yield streaming_pb2.Item(seq=j, payload=payload)

    for _ in range(10):
        stub.ClientStream(gen_items(5))

    samples = []
    t_total = time.perf_counter()
    for i in range(n):
        t0 = time.perf_counter_ns()
        stub.ClientStream(gen_items(5))
        samples.append(time.perf_counter_ns() - t0)
    elapsed = time.perf_counter() - t_total

    samples.sort()
    median_us = samples[len(samples) // 2] / 1000
    p95_us = samples[int(len(samples) * 0.95)] / 1000
    p99_us = samples[int(len(samples) * 0.99)] / 1000
    rps = n / elapsed

    print(f"\n=== python grpcio client-streaming (5 items/call) ===")
    print(f"  iterations  : {n}")
    print(f"  items/call  : 5")
    print(f"  total       : {elapsed*1000:.1f} ms")
    print(f"  throughput  : {rps:,.0f} calls/s")
    print(f"  median      : {median_us:.1f} us")
    print(f"  p95         : {p95_us:.1f} us")
    print(f"  p99         : {p99_us:.1f} us")

    # --- bidi-streaming ---
    for _ in range(10):
        list(stub.BidiStream(gen_items(5)))

    samples = []
    t_total = time.perf_counter()
    for i in range(n):
        t0 = time.perf_counter_ns()
        list(stub.BidiStream(gen_items(5)))
        samples.append(time.perf_counter_ns() - t0)
    elapsed = time.perf_counter() - t_total

    samples.sort()
    median_us = samples[len(samples) // 2] / 1000
    p95_us = samples[int(len(samples) * 0.95)] / 1000
    p99_us = samples[int(len(samples) * 0.99)] / 1000
    rps = n / elapsed

    print(f"\n=== python grpcio bidi-streaming (5 items each way) ===")
    print(f"  iterations  : {n}")
    print(f"  items/call  : 5 send + 5 recv")
    print(f"  total       : {elapsed*1000:.1f} ms")
    print(f"  throughput  : {rps:,.0f} calls/s")
    print(f"  median      : {median_us:.1f} us")
    print(f"  p95         : {p95_us:.1f} us")
    print(f"  p99         : {p99_us:.1f} us")

    channel.close()


if __name__ == "__main__":
    main()
