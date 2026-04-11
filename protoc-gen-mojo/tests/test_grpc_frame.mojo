"""
Tests for the gRPC frame codec (5-byte header + length-prefixed body).
Pure frame/byte tests — no network.
"""

from testing import assert_equal, assert_true
from protobuf_runtime.common import Bytes
from grpc_runtime.frame import encode_grpc_frame, decode_grpc_frame, FrameSplit


def make_bytes(values: List[Int]) -> Bytes:
    var b = Bytes()
    for v in values:
        b.append(UInt8(v))
    return b^


# ── encode ────────────────────────────────────────────────────────────────────

def test_encode_empty() raises:
    var frame = encode_grpc_frame(Bytes())
    assert_equal(len(frame), 5)
    assert_equal(frame[0], UInt8(0))   # compression = none
    assert_equal(frame[1], UInt8(0))
    assert_equal(frame[2], UInt8(0))
    assert_equal(frame[3], UInt8(0))
    assert_equal(frame[4], UInt8(0))   # length = 0

def test_encode_small() raises:
    var body = make_bytes([0xDE, 0xAD, 0xBE, 0xEF])
    var frame = encode_grpc_frame(body)
    assert_equal(len(frame), 9)        # 5 header + 4 body
    assert_equal(frame[0], UInt8(0))
    assert_equal(frame[1], UInt8(0))
    assert_equal(frame[2], UInt8(0))
    assert_equal(frame[3], UInt8(0))
    assert_equal(frame[4], UInt8(4))   # length = 4
    assert_equal(frame[5], UInt8(0xDE))
    assert_equal(frame[6], UInt8(0xAD))
    assert_equal(frame[7], UInt8(0xBE))
    assert_equal(frame[8], UInt8(0xEF))

def test_encode_large_length_be() raises:
    """Verify big-endian length encoding for lengths > 255."""
    var body = Bytes()
    for _ in range(300):
        body.append(UInt8(0x42))
    var frame = encode_grpc_frame(body)
    assert_equal(len(frame), 305)
    # 300 = 0x012C -> big-endian bytes [0x00, 0x00, 0x01, 0x2C]
    assert_equal(frame[1], UInt8(0x00))
    assert_equal(frame[2], UInt8(0x00))
    assert_equal(frame[3], UInt8(0x01))
    assert_equal(frame[4], UInt8(0x2C))


# ── decode ────────────────────────────────────────────────────────────────────

def test_decode_roundtrip() raises:
    var original = make_bytes([0x11, 0x22, 0x33, 0x44, 0x55])
    var frame = encode_grpc_frame(original)
    var split = decode_grpc_frame(frame)
    assert_equal(len(split.body), 5)
    assert_equal(split.body[0], UInt8(0x11))
    assert_equal(split.body[4], UInt8(0x55))
    assert_equal(len(split.remainder), 0)

def test_decode_two_frames() raises:
    """Decode one frame from a buffer that contains two back-to-back frames."""
    var a = make_bytes([0xAA, 0xBB])
    var b = make_bytes([0xCC])
    var buf = Bytes()
    var fa = encode_grpc_frame(a)
    var fb = encode_grpc_frame(b)
    for i in range(len(fa)): buf.append(fa[i])
    for i in range(len(fb)): buf.append(fb[i])

    var first = decode_grpc_frame(buf)
    assert_equal(len(first.body), 2)
    assert_equal(first.body[0], UInt8(0xAA))
    assert_equal(first.body[1], UInt8(0xBB))
    assert_equal(len(first.remainder), 6)   # second frame: 5 header + 1 body

    var second = decode_grpc_frame(first.remainder)
    assert_equal(len(second.body), 1)
    assert_equal(second.body[0], UInt8(0xCC))
    assert_equal(len(second.remainder), 0)

def test_decode_too_short() raises:
    var truncated = make_bytes([0x00, 0x00, 0x00])  # only 3 bytes, header needs 5
    var caught = False
    try:
        _ = decode_grpc_frame(truncated)
    except:
        caught = True
    assert_true(caught)

def test_decode_truncated_body() raises:
    var frame = make_bytes([0, 0, 0, 0, 5, 0x41, 0x42])   # claims 5 body bytes, has 2
    var caught = False
    try:
        _ = decode_grpc_frame(frame)
    except:
        caught = True
    assert_true(caught)


# ── runner ─────────────────────────────────────────────────────────────────────

def run_test(name: String, test: def() raises -> None) -> Bool:
    try:
        test()
        print("  PASS  " + name)
        return True
    except e:
        print("  FAIL  " + name + " — " + String(e))
        return False

def main() raises:
    print("=== grpc frame codec tests ===\n")
    var passed = 0
    var failed = 0

    @parameter
    def check(name: String, f: def() raises -> None):
        if run_test(name, f):
            passed += 1
        else:
            failed += 1

    check("encode empty",           test_encode_empty)
    check("encode small",           test_encode_small)
    check("encode large (BE)",      test_encode_large_length_be)
    check("decode roundtrip",       test_decode_roundtrip)
    check("decode two frames",      test_decode_two_frames)
    check("decode too short",       test_decode_too_short)
    check("decode truncated body",  test_decode_truncated_body)

    print("\n" + String(passed) + " passed, " + String(failed) + " failed")
    if failed > 0:
        raise Error("test failures")
