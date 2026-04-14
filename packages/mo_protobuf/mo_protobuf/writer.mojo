from std.memory import memcpy, UnsafePointer, bitcast
from std.sys import bit_width_of
from mo_protobuf.common import Bytes, WireType, FieldNumber, Tag, VarInt


struct ProtoWriter:
    """Single-buffer protobuf writer.

    All writes append directly to one contiguous `buf`, so encoding a top-level
    message is a single growing allocation rather than the per-field cascade of
    small `Bytes` objects the previous `List[Bytes]` design required.

    Nested messages should use `begin_message` / `end_message`, which encode
    their length in place via a 5-byte varint placeholder, instead of the
    legacy `write_message(field, sub_writer)` path.
    """

    var buf: Bytes

    def __init__(out self):
        self.buf = Bytes()

    def __init__(out self, hint: Int):
        self.buf = Bytes()
        self.buf.reserve(hint)

    def flush(mut self) -> Bytes:
        var out = self.buf^
        self.buf = Bytes()
        return out^

    def write_varint(mut self, value: UInt64):
        """Variable-length encoding."""
        var remaining = value
        while remaining > 0x7F:
            self.buf.append(UInt8((remaining & 0x7F) | 0x80))
            remaining >>= 7
        self.buf.append(UInt8(remaining & 0x7F))

    def write_tag(mut self, field: FieldNumber, wire_type: WireType):
        # Tags with field numbers <= 15 fit in one byte, the vast majority of real protos. 
        # Skip the varint helper entirely.
        var tag = (field << 3) | FieldNumber(wire_type.value)
        if tag < 0x80:
            self.buf.append(UInt8(tag))
        else:
            self.write_varint(UInt64(tag))

    def write_int32(mut self, field: FieldNumber, value: Int32):
        self.write_tag(field, WireType.VARINT)
        self.write_varint(UInt64(value))  # negative -> 10 bytes

    def write_int64(mut self, field: FieldNumber, value: Int64):
        self.write_tag(field, WireType.VARINT)
        self.write_varint(UInt64(value))

    def write_uint32(mut self, field: FieldNumber, value: UInt32):
        self.write_tag(field, WireType.VARINT)
        self.write_varint(UInt64(value))

    def write_uint64(mut self, field: FieldNumber, value: UInt64):
        self.write_tag(field, WireType.VARINT)
        self.write_varint(value)

    def write_sint32(mut self, field: FieldNumber, value: Int32):
        self.write_tag(field, WireType.VARINT)
        self.write_varint(zigzag_encode(Int64(value)))

    def write_sint64(mut self, field: FieldNumber, value: Int64):
        self.write_tag(field, WireType.VARINT)
        self.write_varint(zigzag_encode(value))

    def write_bool(mut self, field: FieldNumber, value: Bool):
        self.write_tag(field, WireType.VARINT)
        self.buf.append(UInt8(1 if value else 0))

    def _write_le[T: DType](mut self, value: Scalar[T]):
        comptime num_bytes = bit_width_of[Scalar[T]]() // 8
        var raw = bitcast[DType.uint8, num_bytes](value)
        var start = len(self.buf)
        self.buf.resize(start + num_bytes, UInt8(0))
        var dst = self.buf.unsafe_ptr() + start
        for i in range(num_bytes):
            dst[i] = raw[i]

    def write_fixed32(mut self, field: FieldNumber, value: UInt32):
        self.write_tag(field, WireType.FIXED_32)
        self._write_le[DType.uint32](value)

    def write_fixed64(mut self, field: FieldNumber, value: UInt64):
        self.write_tag(field, WireType.FIXED_64)
        self._write_le[DType.uint64](value)

    def write_sfixed32(mut self, field: FieldNumber, value: Int32):
        self.write_tag(field, WireType.FIXED_32)
        self._write_le[DType.uint32](bitcast[DType.uint32](value))

    def write_sfixed64(mut self, field: FieldNumber, value: Int64):
        self.write_tag(field, WireType.FIXED_64)
        self._write_le[DType.uint64](bitcast[DType.uint64](value))

    def write_float(mut self, field: FieldNumber, value: Float32):
        self.write_tag(field, WireType.FIXED_32)
        self._write_le[DType.float32](value)

    def write_double(mut self, field: FieldNumber, value: Float64):
        self.write_tag(field, WireType.FIXED_64)
        self._write_le[DType.float64](value)

    def write_bytes(mut self, field: FieldNumber, data: Bytes):
        self.write_tag(field, WireType.LEN_DELIM)
        self.write_varint(UInt64(len(data)))
        self._append_span(Span(data))

    def write_string(mut self, field: FieldNumber, value: String):
        self.write_tag(field, WireType.LEN_DELIM)
        var bytes = value.as_bytes()
        self.write_varint(UInt64(len(bytes)))
        self._append_span(bytes)

    def write_message(mut self, field: FieldNumber, mut sub: ProtoWriter):
        """Legacy entry point: writes a length-delimited message from a sub-writer.

        Prefer `begin_message` / `end_message` for hot paths,
        the sub-writer path forces an extra buffer allocation and a memcpy per nested message.
        """
        self.write_tag(field, WireType.LEN_DELIM)
        var data = sub.flush()
        self.write_varint(UInt64(len(data)))
        self._append_span(Span(data))

    def begin_message(mut self, field: FieldNumber) -> Int:
        """Start a length-delimited message field in place.

        Writes the tag, then reserves 5 bytes for a length placeholder.
        Returns the buffer offset of the placeholder, which must be passed back
        to `end_message` once the body has been written.
        """
        self.write_tag(field, WireType.LEN_DELIM)
        var placeholder_start = len(self.buf)
        self.buf.resize(placeholder_start + 5, UInt8(0))
        return placeholder_start

    def end_message(mut self, placeholder_start: Int):
        """Back-patch the 5-byte placeholder reserved by `begin_message`.

        Always emits a 5-byte varint (max value 2^35 - 1), padding shorter values with continuation bits.
        """
        # Wastes up to 4 bytes per message but eliminates the sub-buffer copy entirely.
        var body_len = UInt64(len(self.buf) - placeholder_start - 5)
        var dst = self.buf.unsafe_ptr() + placeholder_start
        dst[0] = UInt8((body_len & 0x7F) | 0x80)
        dst[1] = UInt8(((body_len >> 7) & 0x7F) | 0x80)
        dst[2] = UInt8(((body_len >> 14) & 0x7F) | 0x80)
        dst[3] = UInt8(((body_len >> 21) & 0x7F) | 0x80)
        dst[4] = UInt8((body_len >> 28) & 0x7F)

    def _append_byte(mut self, value: UInt8):
        self.buf.append(value)

    def _append_span[O: Origin](mut self, span: Span[UInt8, O]):
        var count = len(span)
        if count == 0:
            return
        var start = len(self.buf)
        self.buf.resize(start + count, UInt8(0))
        memcpy(
            dest=self.buf.unsafe_ptr() + start,
            src=span.unsafe_ptr(),
            count=count,
        )


def zigzag_encode(value: Int64) -> UInt64:
    return UInt64((value << 1) ^ (value >> 63))
