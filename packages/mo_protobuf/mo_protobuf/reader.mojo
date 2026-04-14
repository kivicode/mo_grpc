from std.memory import bitcast, memcpy, UnsafePointer
from mo_protobuf.common import Bytes, WireType, FieldNumber, VarInt


@fieldwise_init
struct BufferExhausted(Copyable, Writable):
    var message: String

    def write_to(self, mut writer: Some[Writer]):
        writer.write("BufferExhausted: ", self.message)


struct ProtoReader:
    var buffer: Bytes
    var caret: Int

    def __init__(out self, var data: Bytes):
        self.buffer = data^
        self.caret = 0

    def read_int32(mut self) raises -> Int32:
        return Int32(self.read_varint())

    def read_int64(mut self) raises -> Int64:
        return Int64(self.read_varint())

    def read_uint32(mut self) raises -> UInt32:
        return UInt32(self.read_varint())

    def read_uint64(mut self) raises -> UInt64:
        return self.read_varint()

    def read_sint32(mut self) raises -> Int32:
        var v = self.read_varint()
        return Int32((v >> 1) ^ -(v & 1))

    def read_sint64(mut self) raises -> Int64:
        var v = self.read_varint()
        return Int64((v >> 1) ^ -(v & 1))

    def read_bool(mut self) raises -> Bool:
        return self.read_varint() != 0

    def read_enum(mut self) raises -> Int32:
        return Int32(self.read_varint())

    def read_fixed32(mut self) raises -> UInt32:
        if self.caret + 4 > len(self.buffer):
            raise BufferExhausted("read_fixed32 past end")
        var p = self.buffer.unsafe_ptr() + self.caret
        var v = UInt32(p[0]) | (UInt32(p[1]) << 8) | (UInt32(p[2]) << 16) | (UInt32(p[3]) << 24)
        self.caret += 4
        return v

    def read_fixed64(mut self) raises -> UInt64:
        if self.caret + 8 > len(self.buffer):
            raise BufferExhausted("read_fixed64 past end")
        var p = self.buffer.unsafe_ptr() + self.caret
        var v = UInt64(p[0])
        v |= UInt64(p[1]) << 8
        v |= UInt64(p[2]) << 16
        v |= UInt64(p[3]) << 24
        v |= UInt64(p[4]) << 32
        v |= UInt64(p[5]) << 40
        v |= UInt64(p[6]) << 48
        v |= UInt64(p[7]) << 56
        self.caret += 8
        return v

    def read_sfixed32(mut self) raises -> Int32:
        return Int32(self.read_fixed32())

    def read_sfixed64(mut self) raises -> Int64:
        return Int64(self.read_fixed64())

    def read_float(mut self) raises -> Float32:
        return bitcast[DType.float32](self.read_fixed32())

    def read_double(mut self) raises -> Float64:
        return bitcast[DType.float64](self.read_fixed64())

    def read_bytes(mut self) raises -> Bytes:
        var length = Int(self.read_varint())
        return self._read_n(length)

    def read_string(mut self) raises -> String:
        var data = self.read_bytes()
        return String(unsafe_from_utf8=data^)

    def read_message(mut self) raises -> ProtoReader:
        var length = Int(self.read_varint())
        if self.caret + length > len(self.buffer):
            raise BufferExhausted("read_message past end")
        var slice = Bytes()
        slice.resize(length, UInt8(0))
        if length > 0:
            memcpy(
                dest=slice.unsafe_ptr(),
                src=self.buffer.unsafe_ptr() + self.caret,
                count=length,
            )
        self.caret += length
        return ProtoReader(slice^)

    def skip_field(mut self, wire_type: WireType) raises:
        if wire_type == WireType.VARINT:
            _ = self.read_varint()
        elif wire_type == WireType.FIXED_64:
            self._skip_n(8)
        elif wire_type == WireType.LEN_DELIM:
            var length = Int(self.read_varint())
            self._skip_n(length)
        elif wire_type == WireType.FIXED_32:
            self._skip_n(4)

    def has_more(self) -> Bool:
        return self.caret < len(self.buffer)

    def read_varint(mut self) raises -> UInt64:
        var p = self.buffer.unsafe_ptr()
        var c = self.caret
        var n = len(self.buffer)
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while True:
            if c >= n:
                raise BufferExhausted("varint past end")
            var byte = p[c]
            c += 1
            result |= UInt64(byte & 0x7F) << shift
            if (byte & 0x80) == 0:
                break
            shift += 7
        self.caret = c
        return result

    def read_tag(mut self) raises -> Tuple[FieldNumber, WireType]:
        var tag = self.read_varint()
        return FieldNumber(tag >> 3), WireType(UInt8(tag & 0x07))

    def _read_n(mut self, num_bytes: Int) raises -> Bytes:
        if self.caret + num_bytes > len(self.buffer):
            raise BufferExhausted(
                "Attempted to read "
                + String(num_bytes)
                + " byte(s) past buffer capacity of "
                + String(len(self.buffer))
            )
        var out = Bytes()
        if num_bytes > 0:
            out.resize(num_bytes, UInt8(0))
            memcpy(
                dest=out.unsafe_ptr(),
                src=self.buffer.unsafe_ptr() + self.caret,
                count=num_bytes,
            )
        self.caret += num_bytes
        return out^

    def _skip_n(mut self, num_bytes: Int) raises:
        if self.caret + num_bytes > len(self.buffer):
            raise BufferExhausted(
                "Attempted to skip past buffer capacity of "
                + String(len(self.buffer))
            )
        self.caret += num_bytes
