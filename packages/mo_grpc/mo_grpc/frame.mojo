"""
gRPC frame codec.

Each gRPC DATA frame is:
    byte 0:     compression flag (0 = uncompressed, 1 = compressed)
    bytes 1-4:  big-endian UInt32 length of the message body
    bytes 5..:  serialized protobuf message (body)
"""

from std.memory import memcpy
from mo_protobuf.common import Bytes


# 1-byte compression flag + 4-byte big-endian length.
comptime FRAME_HEADER_LEN = 5


def _read_be_u32(buffer: Bytes, offset: Int) -> UInt32:
    """Read a 4-byte big-endian UInt32 starting at `offset`."""
    return (
        (UInt32(buffer[offset]) << 24)
        | (UInt32(buffer[offset + 1]) << 16)
        | (UInt32(buffer[offset + 2]) << 8)
        | UInt32(buffer[offset + 3])
    )


def _check_frame_bounds(data: Bytes) raises -> Int:
    """Validate the 5-byte header and return the body length."""
    if len(data) < FRAME_HEADER_LEN:
        raise Error(
            "gRPC frame too short: need at least "
            + String(FRAME_HEADER_LEN)
            + " bytes, got "
            + String(len(data))
        )
    var body_len = Int(_read_be_u32(data, 1))
    if FRAME_HEADER_LEN + body_len > len(data):
        raise Error(
            "gRPC frame truncated: header says "
            + String(body_len)
            + " body bytes, buffer has "
            + String(len(data) - FRAME_HEADER_LEN)
        )
    return body_len


def encode_grpc_frame(var body: Bytes) -> Bytes:
    """Prepend a 5-byte gRPC header to `body`. Consumes `body`."""
    var body_len = len(body)
    var body_len_u32 = UInt32(body_len)

    var out = Bytes()
    out.resize(FRAME_HEADER_LEN + body_len, UInt8(0))

    var dst = out.unsafe_ptr()
    dst[0] = UInt8(0)  # compression flag
    dst[1] = UInt8((body_len_u32 >> 24) & 0xFF)
    dst[2] = UInt8((body_len_u32 >> 16) & 0xFF)
    dst[3] = UInt8((body_len_u32 >> 8) & 0xFF)
    dst[4] = UInt8(body_len_u32 & 0xFF)

    memcpy(dest=dst + FRAME_HEADER_LEN, src=body.unsafe_ptr(), count=body_len)
    return out^


@fieldwise_init
struct FrameSplit:
    """Result of `decode_grpc_frame`: the payload plus any trailing bytes."""

    var body: Bytes
    var remainder: Bytes


def decode_grpc_body(var data: Bytes) raises -> Bytes:
    """Decode one gRPC frame and return only its body.

    Cheaper than `decode_grpc_frame` for the unary case, which never has any
    bytes worth keeping after the frame body.
    """
    var body_len = _check_frame_bounds(data)

    var body = Bytes()
    body.resize(body_len, UInt8(0))
    if body_len > 0:
        memcpy(
            dest=body.unsafe_ptr(),
            src=data.unsafe_ptr() + FRAME_HEADER_LEN,
            count=body_len,
        )
    return body^


def decode_grpc_frame(var data: Bytes) raises -> FrameSplit:
    """Decode one gRPC frame from the front of `data`. Consumes `data`.

    Returns the body together with any bytes that came after this frame.
    Raises if `data` is shorter than the advertised frame length.
    """
    var body_len = _check_frame_bounds(data)
    var frame_end = FRAME_HEADER_LEN + body_len

    var body = Bytes()
    body.resize(body_len, UInt8(0))
    if body_len > 0:
        memcpy(
            dest=body.unsafe_ptr(),
            src=data.unsafe_ptr() + FRAME_HEADER_LEN,
            count=body_len,
        )

    var remainder = Bytes()
    var remainder_len = len(data) - frame_end
    if remainder_len > 0:
        remainder.resize(remainder_len, UInt8(0))
        memcpy(
            dest=remainder.unsafe_ptr(),
            src=data.unsafe_ptr() + frame_end,
            count=remainder_len,
        )

    return FrameSplit(body^, remainder^)
