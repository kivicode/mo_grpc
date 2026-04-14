"""Heavy-payload benchmark for mo_grpc.

Constructs a deeply nested Document with optionals, repeated, oneof, map and
nested messages. Mirrors bench_heavy_python.py field-for-field.
"""

from std.time import perf_counter_ns
from std.os import getenv
from mo_grpc import GrpcChannel
from mo_protobuf.common import Bytes
from mo_protobuf import ProtoWriter
from heavy import (
    HeavyStub,
    Document,
    Metric,
    MetricValue,
    Span,
    Tag,
    Vec3,
    Severity,
)


def parse_int(s: String, fallback: Int) -> Int:
    if len(s) == 0:
        return fallback
    try:
        return Int(atol(s))
    except:
        return fallback


def make_tag(k: String, v: String) -> Tag:
    var t = Tag()
    t.key = k
    t.value = v
    return t^


def build_span(depth: Int, fanout: Int, ix: Int) -> Span:
    var s = Span()
    s.trace_id = String("trace-") + String(depth) + String("-") + String(ix)
    s.name = String("span-d") + String(depth) + String("-i") + String(ix)
    s.start_ns = UInt64(1700000000000000000 + ix)
    s.end_ns = UInt64(1700000000000001000 + ix)
    s.severity = Optional[Severity](
        Severity.SEV_HIGH if (ix % 3 == 0) else Severity.SEV_LOW
    )
    s.attributes.append(make_tag("region", "us-west-2"))
    var host_str = String("node-")
    if ix < 10:
        host_str += "00"
    elif ix < 100:
        host_str += "0"
    host_str += String(ix)
    s.attributes.append(make_tag("host", host_str))
    s.attributes.append(make_tag("kind", "server"))
    if depth > 0:
        for c in range(fanout):
            s.children.append(build_span(depth - 1, fanout, c))
    return s^


def build_document(metric_count: Int, span_depth: Int, span_fanout: Int) raises -> Document:
    var doc = Document()
    doc.id = Int64(42)
    doc.title = String("payload-under-test")

    for i in range(metric_count):
        var m = Metric()
        m.name = String("metric-") + String(i)
        var bucket = i % 5
        if bucket == 0:
            m.value = Optional[MetricValue](MetricValue.dbl(3.14159 * Float64(i)))
        elif bucket == 1:
            m.value = Optional[MetricValue](MetricValue.i64(Int64(-i * 1000)))
        elif bucket == 2:
            m.value = Optional[MetricValue](MetricValue.flag(i % 2 == 0))
        elif bucket == 3:
            var v = Vec3()
            v.x = Float64(i) + 0.1
            v.y = Float64(i) + 0.2
            v.z = Float64(i) + 0.3
            m.value = Optional[MetricValue](MetricValue.vec(v^))
        else:
            m.value = Optional[MetricValue](
                MetricValue.text(String("value-text-") + String(i) + String("-with-some-padding"))
            )
        m.labels.append(make_tag("unit", "ms"))
        m.labels.append(make_tag("source", "bench"))
        doc.metrics.append(m^)

    for s in range(span_fanout):
        doc.spans.append(build_span(span_depth, span_fanout, s))

    for i in range(8):
        var key = String("k") + String(i)
        var t = Tag()
        t.key = key
        t.value = String("annotation-value-") + String(i)
        doc.annotations[key] = t^

    for i in range(4):
        var blob = Bytes()
        for _ in range(64):
            blob.append(UInt8(i))
        doc.blobs.append(blob^)

    return doc^


def main() raises:
    var n = parse_int(getenv("BENCH_N", "500"), 500)
    var port_s = getenv("BENCH_PORT", "50443")
    var metric_count = parse_int(getenv("BENCH_METRICS", "32"), 32)
    var span_depth = parse_int(getenv("BENCH_DEPTH", "3"), 3)
    var span_fanout = parse_int(getenv("BENCH_FANOUT", "3"), 3)

    var doc = build_document(metric_count, span_depth, span_fanout)

    # Compute serialized size for reporting (mirrors what goes on the wire).
    var size_w = ProtoWriter()
    doc.serialize(size_w)
    var body_size = len(size_w.flush())

    var url = String("https://localhost:") + port_s
    var stub = HeavyStub(GrpcChannel(url))

    for _ in range(20):
        _ = stub.Echo(doc)

    var samples = List[Int](capacity=n)
    var t_total = Int(perf_counter_ns())
    for _ in range(n):
        var t0 = Int(perf_counter_ns())
        var reply = stub.Echo(doc)
        samples.append(Int(perf_counter_ns()) - t0)
        if reply.id.value() != Int64(42):
            raise Error("id mismatch")
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

    print("=== heavy: mo_grpc (release, single channel, persistent libcurl handle) ===")
    print("  iterations  : " + String(n))
    print("  body size   : " + String(body_size) + " bytes (uncompressed)")
    print("  metrics     : " + String(metric_count))
    print("  span tree   : depth=" + String(span_depth) + " fanout=" + String(span_fanout))
    print("  total       : " + String(elapsed_ms) + " ms")
    print("  throughput  : " + String(rps) + " req/s")
    print("  mean        : " + String(mean_us) + " us")
    print("  median      : " + String(median_us) + " us")
    print("  p95         : " + String(p95_us) + " us")
    print("  p99         : " + String(p99_us) + " us")
