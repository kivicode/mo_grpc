from std.memory import bitcast, memcpy, UnsafePointer
from mo_protobuf.common import Bytes, WireType, FieldNumber, VarInt


@fieldwise_init
struct BufferExhausted(Copyable, Writable):
    var message: String

    def write_to(self, mut writer: Some[Writer]):
        writer.write("BufferExhausted: ", self.message)


struct ProtoReader(Movable):
    """Pointer-based protobuf reader.

    Top-level readers own their `Bytes` via `_owned`; sub-readers returned by
    `read_message` are zero-copy views over the parent's buffer (same address,
    different `end`). The caller must keep the top-level reader alive while
    sub-readers are in scope.

    `ptr_addr` is the underlying buffer base address stored as an `Int` to
    sidestep Mojo's per-pointer origin parameter — sub-readers need to point
    into a buffer they don't own, which the lifetime system would reject.
    """

    var _owned: Bytes
    var ptr_addr: Int
    var caret: Int
    var end: Int

    def __init__(out self, var data: Bytes):
        self.end = len(data)
        self._owned = data^
        self.ptr_addr = Int(self._owned.unsafe_ptr())
        self.caret = 0

    @staticmethod
    def view(ptr_addr: Int, start: Int, end: Int) -> Self:
        """Build a sub-reader that does not own its buffer.
        Used by `read_message` to expose a window into the parent's bytes without an extra allocation.
        """
        var sub = Self(Bytes())
        sub.ptr_addr = ptr_addr
        sub.caret = start
        sub.end = end
        return sub^

    def read_int32(mut self) raises -> Int32:
        return Int32(self.read_varint())

    def read_int64(mut self) raises -> Int64:
        return Int64(self.read_varint())

    def read_uint32(mut self) raises -> UInt32:
        return UInt32(self.read_varint())

    def read_uint64(mut self) raises -> UInt64:
        return self.read_varint()

    def read_sint32(mut self) raises -> Int32:
        var value = self.read_varint()
        return Int32((value >> 1) ^ -(value & 1))

    def read_sint64(mut self) raises -> Int64:
        var value = self.read_varint()
        return Int64((value >> 1) ^ -(value & 1))

    def read_bool(mut self) raises -> Bool:
        return self.read_varint() != 0

    def read_enum(mut self) raises -> Int32:
        return Int32(self.read_varint())

    @always_inline
    def read_fixed32(mut self) raises -> UInt32:
        if self.caret + 4 > self.end:
            raise BufferExhausted("read_fixed32 past end")

        # Protobuf is little-endian on the wire; so is everything we run on.
        var ptr = self._ptr() + self.caret
        var value = ptr.bitcast[UInt32]()[0]
        self.caret += 4
        return value

    @always_inline
    def read_fixed64(mut self) raises -> UInt64:
        if self.caret + 8 > self.end:
            raise BufferExhausted("read_fixed64 past end")
        var ptr = self._ptr() + self.caret
        var value = ptr.bitcast[UInt64]()[0]
        self.caret += 8
        return value

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
        if self.caret + length > self.end:
            raise BufferExhausted("read_bytes past end")

        var out = Bytes()
        if length > 0:
            out.resize(length, UInt8(0))
            memcpy(
                dest=out.unsafe_ptr(),
                src=self._ptr() + self.caret,
                count=length,
            )
        self.caret += length
        return out^

    def read_string(mut self) raises -> String:
        # Construct the String directly from a StringSlice over the source buffer,
        # skips the intermediate Bytes alloc + zero-fill that `read_bytes()` would do.
        var length = Int(self.read_varint())
        if self.caret + length > self.end:
            raise BufferExhausted("read_string past end")

        var ptr = self._ptr() + self.caret
        self.caret += length
        var slice = StringSlice[MutAnyOrigin](ptr=ptr, length=length)
        return String(slice)

    def read_message(mut self) raises -> ProtoReader:
        """Returns a zero-copy sub-reader over `length` bytes of the parent.

        The returned reader points into the parent's buffer, the caller must
        keep `self` alive until the sub-reader is no longer in use.
        """
        var length = Int(self.read_varint())
        if self.caret + length > self.end:
            raise BufferExhausted("read_message past end")

        var sub = Self.view(self.ptr_addr, self.caret, self.caret + length)
        self.caret += length
        return sub^

    def push_limit(mut self) raises -> Int:
        """Read a varint length prefix and clamp `end` to that many bytes ahead.

        Returns the previous `end` so the caller can `pop_limit` after parsing
        the sub-message. Used by generated code in place of `read_message` to
        skip the sub-reader struct entirely, the same reader walks down into
        the sub-message, then `pop_limit` restores the parent bounds.
        """
        var length = Int(self.read_varint())
        var sub_end = self.caret + length
        if sub_end > self.end:
            raise BufferExhausted("push_limit past end")

        var saved_end = self.end
        self.end = sub_end
        return saved_end

    def pop_limit(mut self, saved_end: Int):
        """Restore the parent bounds set by a prior `push_limit`.

        `caret` is left at the end of the just-finished sub-message because
        `has_more()` drove parse to consume exactly that many bytes.
        """
        self.end = saved_end

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
        return self.caret < self.end

    @always_inline
    def read_varint(mut self) raises -> UInt64:
        # Hand-unrolled fast paths for 1-, 2-, and 3-byte varints, the vast majority of tags and lengths fall here.
        # Falls through to the byte loop for the (rare) longer ones.
        var ptr = self._ptr()
        var pos = self.caret
        var limit = self.end

        if pos >= limit:
            raise BufferExhausted("varint past end")

        var byte0 = ptr[pos]
        if (byte0 & 0x80) == 0:
            self.caret = pos + 1
            return UInt64(byte0)

        if pos + 1 >= limit:
            raise BufferExhausted("varint past end")
        var byte1 = ptr[pos + 1]
        if (byte1 & 0x80) == 0:
            self.caret = pos + 2
            return UInt64(byte0 & 0x7F) | (UInt64(byte1) << 7)

        if pos + 2 >= limit:
            raise BufferExhausted("varint past end")
        var byte2 = ptr[pos + 2]
        if (byte2 & 0x80) == 0:
            self.caret = pos + 3
            return (
                UInt64(byte0 & 0x7F)
                | (UInt64(byte1 & 0x7F) << 7)
                | (UInt64(byte2) << 14)
            )

        # Slow path: 4+ byte varints.
        var result: UInt64 = (
            UInt64(byte0 & 0x7F)
            | (UInt64(byte1 & 0x7F) << 7)
            | (UInt64(byte2 & 0x7F) << 14)
        )
        var shift: UInt64 = 21
        pos += 3
        while True:
            if pos >= limit:
                raise BufferExhausted("varint past end")
            var byte = ptr[pos]
            pos += 1
            result |= UInt64(byte & 0x7F) << shift
            if (byte & 0x80) == 0:
                break
            shift += 7

        self.caret = pos
        return result

    def read_tag(mut self) raises -> Tuple[FieldNumber, WireType]:
        var tag = self.read_varint()
        return FieldNumber(tag >> 3), WireType(UInt8(tag & 0x07))

    def _skip_n(mut self, num_bytes: Int) raises:
        if self.caret + num_bytes > self.end:
            raise BufferExhausted(
                "Attempted to skip past buffer capacity of " + String(self.end)
            )
        self.caret += num_bytes

    @always_inline
    def _ptr(self) -> UnsafePointer[UInt8, MutAnyOrigin]:
        return UnsafePointer[UInt8, MutAnyOrigin](unsafe_from_address=self.ptr_addr)
