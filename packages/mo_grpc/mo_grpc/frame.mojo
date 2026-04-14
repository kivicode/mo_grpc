"""
gRPC frame codec

Each gRPC DATA frame is:
    byte 0:     compression flag (0 = uncompressed, 1 = compressed)
    bytes 1-4:  big-endian UInt32 length of the message body
    bytes 5..:  serialized protobuf message (body)
"""

from std.memory import memcpy
from mo_protobuf.common import Bytes


def encode_grpc_frame(var body: Bytes) -> Bytes:
    """Prepend a 5-byte gRPC header to `body`. Consumes `body`."""
    var n = UInt32(len(body))
    var body_len = len(body)
    var out = Bytes()
    out.resize(5 + body_len, UInt8(0))
    var dst = out.unsafe_ptr()
    dst[0] = UInt8(0)
    dst[1] = UInt8((n >> 24) & 0xFF)
    dst[2] = UInt8((n >> 16) & 0xFF)
    dst[3] = UInt8((n >> 8) & 0xFF)
    dst[4] = UInt8(n & 0xFF)
    memcpy(dest=dst + 5, src=body.unsafe_ptr(), count=body_len)
    return out^


@fieldwise_init
struct FrameSplit:
    """Result of decode_grpc_frame: the payload and the remaining bytes."""

    var body: Bytes
    var remainder: Bytes


def decode_grpc_frame(var data: Bytes) raises -> FrameSplit:
    """Decode one gRPC frame from the front of `data`. Consumes `data`.

    Raises if `data` is shorter than the advertised frame length.
    Returns the body + any bytes that came after this frame.
    """
    if len(data) < 5:
        raise Error("gRPC frame too short: need at least 5 bytes, got " + String(len(data)))

    var length = (UInt32(data[1]) << 24) | (UInt32(data[2]) << 16) | (UInt32(data[3]) << 8) | UInt32(data[4])
    var end = 5 + Int(length)
    if len(data) < end:
        raise Error(
            "gRPC frame truncated: header says "
            + String(Int(length))
            + " body bytes, buffer has "
            + String(len(data) - 5)
        )

    var body_len = Int(length)
    var body = Bytes()
    body.resize(body_len, UInt8(0))
    memcpy(dest=body.unsafe_ptr(), src=data.unsafe_ptr() + 5, count=body_len)

    var remainder = Bytes()
    var rem_len = len(data) - end
    if rem_len > 0:
        remainder.resize(rem_len, UInt8(0))
        memcpy(dest=remainder.unsafe_ptr(), src=data.unsafe_ptr() + end, count=rem_len)

    return FrameSplit(body^, remainder^)
