from protobuf_runtime.common import Bytes, WireType, FieldNumber, VarInt
from std.memory import bitcast


@fieldwise_init
struct BufferExhausted(Copyable, Writable):
    var message: String

    def write_to(self, mut writer: Some[Writer]):
        writer.write("BufferExhausted: ", self.message)


struct ProtoReader:
    var buffer: Bytes
    var caret: Int

    def __init__(out self, data: Bytes):
        self.buffer = data.copy()
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
        var data = self._read_n(4)
        return UInt32(data[0]) | (UInt32(data[1]) << 8) | (UInt32(data[2]) << 16) | (UInt32(data[3]) << 24)

    def read_fixed64(mut self) raises -> UInt64:
        var data = self._read_n(8)
        var result: UInt64 = 0
        for i in range(8):
            result |= UInt64(data[i]) << (UInt64(i) * 8)
        return result

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
        var data = self.read_bytes()
        return ProtoReader(data^)

    def skip_field(mut self, wire_type: WireType) raises:
        if wire_type == WireType.VARINT:
            _ = self.read_varint()
        elif wire_type == WireType.FIXED_64:
            _ = self._read_n(8)
        elif wire_type == WireType.LEN_DELIM:
            var length = Int(self.read_varint())
            _ = self._read_n(length)
        elif wire_type == WireType.FIXED_32:
            _ = self._read_n(4)


    def has_more(self) -> Bool:
        return self.caret < len(self.buffer)

    def read_varint(mut self) raises -> UInt64:
        var result: UInt64 = 0
        var shift: UInt64 = 0

        while True:
            var byte = self._read_byte()
            result |= UInt64(byte & 0x7F) << shift

            if byte & 0x80 == 0:
                break

            shift += 7

        return result

    def read_tag(mut self) raises -> Tuple[FieldNumber, WireType]:
        var tag = self.read_varint()
        return FieldNumber(tag >> 3), WireType(UInt8(tag & 0x07))


    def _read_byte(mut self) raises -> UInt8:
        if self.caret >= len(self.buffer):
            raise BufferExhausted("Attempted to read past buffer capacity of " + String(len(self.buffer)))

        var val = self.buffer[self.caret]
        self.caret += 1
        return val

    def _read_n(mut self, num_bytes: Int) raises -> Bytes:
        if self.caret + num_bytes > len(self.buffer):
            raise BufferExhausted("Attempted to read " + String(num_bytes) + " byte(s) past buffer capacity of " + String(len(self.buffer)))

        var out = Bytes()
        out.reserve(num_bytes)

        for _ in range(num_bytes):
            out.append(self.buffer[self.caret])
            self.caret += 1

        return out^

