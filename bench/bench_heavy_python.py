# /// script
# requires-python = ">=3.10"
# dependencies = ["grpcio>=1.60", "protobuf>=4.25"]
# ///
"""Heavy-payload benchmark for Python grpcio.

Builds a deeply nested Document with optionals, repeated, oneofs, maps and
nested messages, then round-trips it N times. Mirrors bench_heavy_mojo.mojo
exactly so both clients pump identical wire bytes.
"""
import os
import sys
import time
import statistics

import grpc

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "gen"))
import heavy_pb2
import heavy_pb2_grpc

HERE = os.path.dirname(os.path.abspath(__file__))
CERT = os.path.join(HERE, "certs", "server.crt")


def build_span(depth: int, fanout: int, ix: int) -> heavy_pb2.Span:
    s = heavy_pb2.Span(
        trace_id=f"trace-{depth}-{ix}",
        name=f"span-d{depth}-i{ix}",
        start_ns=1_700_000_000_000_000_000 + ix,
        end_ns=1_700_000_000_000_001_000 + ix,
        severity=heavy_pb2.SEV_HIGH if ix % 3 == 0 else heavy_pb2.SEV_LOW,
    )
    s.attributes.add(key="region", value="us-west-2")
    s.attributes.add(key="host", value=f"node-{ix:03d}")
    s.attributes.add(key="kind", value="server")
    if depth > 0:
        for c in range(fanout):
            s.children.append(build_span(depth - 1, fanout, c))
    return s


def build_document(metric_count: int, span_depth: int, span_fanout: int) -> heavy_pb2.Document:
    doc = heavy_pb2.Document(id=42, title="payload-under-test")
    for i in range(metric_count):
        m = heavy_pb2.Metric(name=f"metric-{i}")
        if i % 5 == 0:
            m.dbl = 3.14159 * i
        elif i % 5 == 1:
            m.i64 = -i * 1000
        elif i % 5 == 2:
            m.flag = (i % 2 == 0)
        elif i % 5 == 3:
            m.vec.x = i + 0.1
            m.vec.y = i + 0.2
            m.vec.z = i + 0.3
        else:
            m.text = f"value-text-{i}-with-some-padding"
        m.labels.add(key="unit", value="ms")
        m.labels.add(key="source", value="bench")
        doc.metrics.append(m)

    for s in range(span_fanout):
        doc.spans.append(build_span(span_depth, span_fanout, s))

    for i in range(8):
        t = doc.annotations[f"k{i}"]
        t.key = f"k{i}"
        t.value = f"annotation-value-{i}"

    for i in range(4):
        doc.blobs.append(bytes([i % 256]) * 64)

    return doc


def main():
    n = int(os.environ.get("BENCH_N", "500"))
    port = int(os.environ.get("BENCH_PORT", "50443"))
    metric_count = int(os.environ.get("BENCH_METRICS", "32"))
    span_depth = int(os.environ.get("BENCH_DEPTH", "3"))
    span_fanout = int(os.environ.get("BENCH_FANOUT", "3"))

    doc = build_document(metric_count, span_depth, span_fanout)
    body_size = len(doc.SerializeToString())

    with open(CERT, "rb") as f:
        crt = f.read()
    creds = grpc.ssl_channel_credentials(root_certificates=crt)
    options = (
        ("grpc.ssl_target_name_override", "localhost"),
        ("grpc.default_authority", "localhost"),
        ("grpc.max_send_message_length", 64 * 1024 * 1024),
        ("grpc.max_receive_message_length", 64 * 1024 * 1024),
    )
    channel = grpc.secure_channel(f"127.0.0.1:{port}", creds, options=options)
    grpc.channel_ready_future(channel).result(timeout=5.0)
    stub = heavy_pb2_grpc.HeavyStub(channel)

    for _ in range(20):
        stub.Echo(doc)

    samples = []
    t_total = time.perf_counter()
    for _ in range(n):
        t0 = time.perf_counter_ns()
        reply = stub.Echo(doc)
        samples.append(time.perf_counter_ns() - t0)
        assert reply.id == 42
    elapsed = time.perf_counter() - t_total

    samples.sort()
    median_us = samples[len(samples) // 2] / 1000
    p95_us = samples[int(len(samples) * 0.95)] / 1000
    p99_us = samples[int(len(samples) * 0.99)] / 1000
    mean_us = statistics.mean(samples) / 1000
    rps = n / elapsed

    print("=== heavy: python grpcio (sync stub, single channel) ===")
    print(f"  iterations  : {n}")
    print(f"  body size   : {body_size:,} bytes (uncompressed)")
    print(f"  metrics     : {metric_count}")
    print(f"  span tree   : depth={span_depth} fanout={span_fanout} (~{(span_fanout ** (span_depth + 1) - 1) // (span_fanout - 1) if span_fanout != 1 else span_depth + 1} spans)")
    print(f"  total       : {elapsed*1000:.1f} ms")
    print(f"  throughput  : {rps:,.0f} req/s")
    print(f"  mean        : {mean_us:.1f} us")
    print(f"  median      : {median_us:.1f} us")
    print(f"  p95         : {p95_us:.1f} us")
    print(f"  p99         : {p99_us:.1f} us")

    channel.close()


if __name__ == "__main__":
    main()
