comptime Bytes = List[UInt8]
comptime FieldNumber = Int32
comptime Tag = UInt32
comptime VarInt = UInt64

@fieldwise_init
struct WireType(Equatable, ImplicitlyCopyable):
    var value: UInt8

    comptime VARINT = WireType(0)
    comptime FIXED_64 = WireType(1)
    comptime LEN_DELIM = WireType(2)
    comptime FIXED_32 = WireType(5)

    def __eq__(self, other: Self) -> Bool:
        return self.value == other.value

    def __ne__(self, other: Self) -> Bool:
        return not (self == other)

