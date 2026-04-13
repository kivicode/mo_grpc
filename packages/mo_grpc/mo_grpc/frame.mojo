"""
gRPC frame codec

Each gRPC DATA frame is:
    byte 0:     compression flag (0 = uncompressed, 1 = compressed)
    bytes 1-4:  big-endian UInt32 length of the message body
    bytes 5..:  serialized protobuf message (body)
"""

from mo_protobuf.common import Bytes


def encode_grpc_frame(body: Bytes) -> Bytes:
    """Prepend a 5-byte gRPC header to `body`."""
    var n = UInt32(len(body))
    var out = Bytes()
    out.reserve(5 + len(body))
    out.append(UInt8(0))  # compression flag = none
    out.append(UInt8((n >> 24) & 0xFF))
    out.append(UInt8((n >> 16) & 0xFF))
    out.append(UInt8((n >> 8) & 0xFF))
    out.append(UInt8(n & 0xFF))
    for i in range(len(body)):
        out.append(body[i])
    return out^


@fieldwise_init
struct FrameSplit:
    """Result of decode_grpc_frame: the payload and the remaining bytes."""

    var body: Bytes
    var remainder: Bytes


def decode_grpc_frame(data: Bytes) raises -> FrameSplit:
    """Decode one gRPC frame from the front of `data`.

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

    var body = Bytes()
    body.reserve(Int(length))
    for i in range(5, end):
        body.append(data[i])

    var remainder = Bytes()
    for i in range(end, len(data)):
        remainder.append(data[i])

    return FrameSplit(body^, remainder^)
