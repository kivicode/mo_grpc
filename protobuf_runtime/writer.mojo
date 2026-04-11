from protobuf_runtime.common import Bytes, WireType, FieldNumber, Tag, VarInt
from std.utils import Variant
from std.algorithm.reduction import sum
from std.sys import bit_width_of
from std.memory import bitcast

struct ProtoWriter:

    var buffer: List[Bytes]

    def __init__(out self):
        self.buffer = []

    def flush(mut self) -> Bytes:
        output = Bytes()

        var total: Int = 0
        for part in self.buffer:
            total += len(part)
        output.reserve(total)
        
        for part in self.buffer:
            output.extend(part.copy())

        self.buffer.clear()
        return output^

    def write_varint(mut self, value: UInt64):
        """Variable-length encoding — NOT the same as to_le_bytes."""
        var v = value
        var out = Bytes()
        while v > 0x7F:
            out.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        out.append(UInt8(v & 0x7F))
        self._write(out^)

    def write_tag(mut self, field: FieldNumber, wire_type: WireType):
        self.write_varint(UInt64((field << 3) | FieldNumber(wire_type.value)))

    def write_int32(mut self, field: FieldNumber, value: Int32):
        self.write_tag(field, WireType.VARINT)
        self.write_varint(UInt64(value))  # negative → 10 bytes

    def write_int64(mut self, field: FieldNumber, value: Int64):
        self.write_tag(field, WireType.VARINT)
        self.write_varint(UInt64(value))

    def write_uint32(mut self, field: FieldNumber, value: UInt32):
        self.write_tag(field, WireType.VARINT)
        self.write_varint(UInt64(value))

    def write_sint64(mut self, field: FieldNumber, value: Int64):
        self.write_tag(field, WireType.VARINT)
        self.write_varint(zigzag_encode(value))

    def write_sfixed32(mut self, field: FieldNumber, value: Int32):
        self.write_tag(field, WireType.FIXED_32)
        self._write(to_le_bytes(UInt32(bitcast[DType.uint32](value))))

    def write_sfixed64(mut self, field: FieldNumber, value: Int64):
        self.write_tag(field, WireType.FIXED_64)
        self._write(to_le_bytes(UInt64(bitcast[DType.uint64](value))))

    def write_sint32(mut self, field: FieldNumber, value: Int32):
        self.write_tag(field, WireType.VARINT)
        self.write_varint(zigzag_encode(Int64(value)))

    def write_uint64(mut self, field: FieldNumber, value: UInt64):
        self.write_tag(field, WireType.VARINT)
        self.write_varint(value)

    def write_bool(mut self, field: FieldNumber, value: Bool):
        self.write_tag(field, WireType.VARINT)
        self.write_varint(UInt64(1 if value else 0))

    def write_fixed32(mut self, field: FieldNumber, value: UInt32):
        self.write_tag(field, WireType.FIXED_32)
        self._write(to_le_bytes(value))

    def write_fixed64(mut self, field: FieldNumber, value: UInt64):
        self.write_tag(field, WireType.FIXED_64)
        self._write(to_le_bytes(value))

    def write_float(mut self, field: FieldNumber, value: Float32):
        self.write_tag(field, WireType.FIXED_32)
        self._write(to_le_bytes(value))

    def write_double(mut self, field: FieldNumber, value: Float64):
        self.write_tag(field, WireType.FIXED_64)
        self._write(to_le_bytes(value))

    def write_bytes(mut self, field: FieldNumber, data: Bytes):
        self.write_tag(field, WireType.LEN_DELIM)
        self.write_varint(UInt64(len(data)))
        self._write(data.copy())

    def write_string(mut self, field: FieldNumber, value: String):
        self.write_bytes(field, Bytes(value.as_bytes()))

    def write_message(mut self, field: FieldNumber, mut sub: ProtoWriter):
        self.write_tag(field, WireType.LEN_DELIM)
        var data = sub.flush()
        self.write_varint(UInt64(len(data)))
        self._write(data^)
        
    def _write(mut self,  data: Bytes):
        self.buffer.append(data.copy())

def zigzag_encode(val: Int64) -> UInt64:
    return UInt64((val << 1) ^ (val >> 63))

def to_le_bytes[T: DType](value: Scalar[T]) -> Bytes:
    comptime num_bytes = bit_width_of[Scalar[T]]() // 8
    var raw = bitcast[DType.uint8, num_bytes](value)
    var out = Bytes()
    
    for i in range(num_bytes):
        out.append(raw[i])
        
    return out^
