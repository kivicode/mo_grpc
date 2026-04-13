from testing import assert_equal, assert_true, assert_false
from mo_protobuf import ProtoReader, ProtoWriter
from mo_protobuf.common import Bytes, WireType


def roundtrip(mut w: ProtoWriter) -> ProtoReader:
    var data = w.flush()
    return ProtoReader(data^)


def test_int32() raises:
    var w = ProtoWriter()
    w.write_int32(1, Int32(0))
    w.write_int32(2, Int32(42))
    w.write_int32(3, Int32(-1))
    w.write_int32(4, Int32(2147483647))
    var r = roundtrip(w)

    var f1, t1 = r.read_tag()
    assert_equal(Int(f1), 1)
    assert_equal(r.read_int32(), Int32(0))
    var f2, t2 = r.read_tag()
    assert_equal(Int(f2), 2)
    assert_equal(r.read_int32(), Int32(42))
    var f3, t3 = r.read_tag()
    assert_equal(Int(f3), 3)
    assert_equal(r.read_int32(), Int32(-1))
    var f4, t4 = r.read_tag()
    assert_equal(Int(f4), 4)
    assert_equal(r.read_int32(), Int32(2147483647))
    assert_false(r.has_more())


def test_int64() raises:
    var w = ProtoWriter()
    w.write_int64(1, Int64(0))
    w.write_int64(2, Int64(9223372036854775807))
    w.write_int64(3, Int64(-9223372036854775807))
    var r = roundtrip(w)
    var f1, t1 = r.read_tag()
    assert_equal(r.read_int64(), Int64(0))
    var f2, t2 = r.read_tag()
    assert_equal(r.read_int64(), Int64(9223372036854775807))
    var f3, t3 = r.read_tag()
    assert_equal(r.read_int64(), Int64(-9223372036854775807))


def test_uint32() raises:
    var w = ProtoWriter()
    w.write_uint32(1, UInt32(0))
    w.write_uint32(2, UInt32(4294967295))
    var r = roundtrip(w)
    var f1, t1 = r.read_tag()
    assert_equal(r.read_uint32(), UInt32(0))
    var f2, t2 = r.read_tag()
    assert_equal(r.read_uint32(), UInt32(4294967295))


def test_uint64() raises:
    var w = ProtoWriter()
    w.write_uint64(1, UInt64(0))
    w.write_uint64(2, UInt64(18446744073709551615))
    var r = roundtrip(w)
    var f1, t1 = r.read_tag()
    assert_equal(r.read_uint64(), UInt64(0))
    var f2, t2 = r.read_tag()
    assert_equal(r.read_uint64(), UInt64(18446744073709551615))


def test_sint32() raises:
    """sint32 uses zigzag: 0->0, -1->1, 1->2, -2->3."""
    var w = ProtoWriter()
    w.write_sint32(1, Int32(0))
    w.write_sint32(2, Int32(-1))
    w.write_sint32(3, Int32(1))
    w.write_sint32(4, Int32(-2147483648))
    var r = roundtrip(w)
    var f1, t1 = r.read_tag()
    assert_equal(r.read_sint32(), Int32(0))
    var f2, t2 = r.read_tag()
    assert_equal(r.read_sint32(), Int32(-1))
    var f3, t3 = r.read_tag()
    assert_equal(r.read_sint32(), Int32(1))
    var f4, t4 = r.read_tag()
    assert_equal(r.read_sint32(), Int32(-2147483648))


def test_sint64() raises:
    var w = ProtoWriter()
    w.write_sint64(1, Int64(0))
    w.write_sint64(2, Int64(-1))
    w.write_sint64(3, Int64(1))
    var r = roundtrip(w)
    var f1, t1 = r.read_tag()
    assert_equal(r.read_sint64(), Int64(0))
    var f2, t2 = r.read_tag()
    assert_equal(r.read_sint64(), Int64(-1))
    var f3, t3 = r.read_tag()
    assert_equal(r.read_sint64(), Int64(1))


def test_bool() raises:
    var w = ProtoWriter()
    w.write_bool(1, True)
    w.write_bool(2, False)
    var r = roundtrip(w)
    var f1, t1 = r.read_tag()
    assert_true(r.read_bool())
    var f2, t2 = r.read_tag()
    assert_false(r.read_bool())


def test_fixed32() raises:
    var w = ProtoWriter()
    w.write_fixed32(1, UInt32(0))
    w.write_fixed32(2, UInt32(305419896))  # 0x12345678
    w.write_fixed32(3, UInt32(4294967295))
    var r = roundtrip(w)
    var f1, t1 = r.read_tag()
    assert_equal(t1.value, UInt8(5))  # FIXED_32 wire type
    assert_equal(r.read_fixed32(), UInt32(0))
    var f2, t2 = r.read_tag()
    assert_equal(r.read_fixed32(), UInt32(305419896))
    var f3, t3 = r.read_tag()
    assert_equal(r.read_fixed32(), UInt32(4294967295))


def test_fixed64() raises:
    var w = ProtoWriter()
    w.write_fixed64(1, UInt64(0))
    w.write_fixed64(2, UInt64(1311768467294899695))  # 0x1234567890ABCDEF
    var r = roundtrip(w)
    var f1, t1 = r.read_tag()
    assert_equal(t1.value, UInt8(1))  # FIXED_64 wire type
    assert_equal(r.read_fixed64(), UInt64(0))
    var f2, t2 = r.read_tag()
    assert_equal(r.read_fixed64(), UInt64(1311768467294899695))


def test_sfixed32() raises:
    var w = ProtoWriter()
    w.write_sfixed32(1, Int32(0))
    w.write_sfixed32(2, Int32(-42))
    w.write_sfixed32(3, Int32(2147483647))
    var r = roundtrip(w)
    var f1, t1 = r.read_tag()
    assert_equal(r.read_sfixed32(), Int32(0))
    var f2, t2 = r.read_tag()
    assert_equal(r.read_sfixed32(), Int32(-42))
    var f3, t3 = r.read_tag()
    assert_equal(r.read_sfixed32(), Int32(2147483647))


def test_sfixed64() raises:
    var w = ProtoWriter()
    w.write_sfixed64(1, Int64(0))
    w.write_sfixed64(2, Int64(-1))
    w.write_sfixed64(3, Int64(-9223372036854775807))
    var r = roundtrip(w)
    var f1, t1 = r.read_tag()
    assert_equal(r.read_sfixed64(), Int64(0))
    var f2, t2 = r.read_tag()
    assert_equal(r.read_sfixed64(), Int64(-1))
    var f3, t3 = r.read_tag()
    assert_equal(r.read_sfixed64(), Int64(-9223372036854775807))


def test_float() raises:
    var w = ProtoWriter()
    w.write_float(1, Float32(0.0))
    w.write_float(2, Float32(3.14))
    w.write_float(3, Float32(-1.5))
    var r = roundtrip(w)
    var f1, t1 = r.read_tag()
    assert_equal(r.read_float(), Float32(0.0))
    var f2, t2 = r.read_tag()
    assert_equal(r.read_float(), Float32(3.14))
    var f3, t3 = r.read_tag()
    assert_equal(r.read_float(), Float32(-1.5))


def test_double() raises:
    var w = ProtoWriter()
    w.write_double(1, Float64(0.0))
    w.write_double(2, Float64(3.141592653589793))
    w.write_double(3, Float64(-1e100))
    var r = roundtrip(w)
    var f1, t1 = r.read_tag()
    assert_equal(r.read_double(), Float64(0.0))
    var f2, t2 = r.read_tag()
    assert_equal(r.read_double(), Float64(3.141592653589793))
    var f3, t3 = r.read_tag()
    assert_equal(r.read_double(), Float64(-1e100))


def test_string() raises:
    var w = ProtoWriter()
    w.write_string(1, String(""))
    w.write_string(2, String("hello"))
    w.write_string(3, String("world 🌍"))
    var r = roundtrip(w)
    var f1, t1 = r.read_tag()
    assert_equal(r.read_string(), String(""))
    var f2, t2 = r.read_tag()
    assert_equal(r.read_string(), String("hello"))
    var f3, t3 = r.read_tag()
    assert_equal(r.read_string(), String("world 🌍"))


def test_bytes_field() raises:
    var w = ProtoWriter()
    var empty = Bytes()
    var data = Bytes()
    data.append(UInt8(0))
    data.append(UInt8(1))
    data.append(UInt8(255))
    w.write_bytes(1, empty)
    w.write_bytes(2, data)
    var r = roundtrip(w)
    var f1, t1 = r.read_tag()
    var got1 = r.read_bytes()
    assert_equal(len(got1), 0)
    var f2, t2 = r.read_tag()
    var got2 = r.read_bytes()
    assert_equal(len(got2), 3)
    assert_equal(got2[0], UInt8(0))
    assert_equal(got2[1], UInt8(1))
    assert_equal(got2[2], UInt8(255))


def test_nested_message() raises:
    var inner = ProtoWriter()
    inner.write_int32(1, Int32(99))
    inner.write_string(2, String("inner"))

    var outer = ProtoWriter()
    outer.write_string(1, String("outer"))
    outer.write_message(2, inner)

    var r = roundtrip(outer)
    var f1, t1 = r.read_tag()
    assert_equal(Int(f1), 1)
    assert_equal(r.read_string(), String("outer"))

    var f2, t2 = r.read_tag()
    assert_equal(Int(f2), 2)
    assert_equal(t2.value, UInt8(2))
    var sub = r.read_message()
    var if1, it1 = sub.read_tag()
    assert_equal(Int(if1), 1)
    assert_equal(sub.read_int32(), Int32(99))
    var if2, it2 = sub.read_tag()
    assert_equal(Int(if2), 2)
    assert_equal(sub.read_string(), String("inner"))
    assert_false(sub.has_more())
    assert_false(r.has_more())


def test_nested_roundtrip_3_levels() raises:
    var l3 = ProtoWriter()
    l3.write_bool(1, True)

    var l2 = ProtoWriter()
    l2.write_int32(1, Int32(7))
    l2.write_message(2, l3)

    var l1 = ProtoWriter()
    l1.write_string(1, String("top"))
    l1.write_message(2, l2)

    var r = roundtrip(l1)
    var f1, t1 = r.read_tag()
    assert_equal(r.read_string(), String("top"))
    var f2, t2 = r.read_tag()
    var r2 = r.read_message()
    var if1, it1 = r2.read_tag()
    assert_equal(r2.read_int32(), Int32(7))
    var if2, it2 = r2.read_tag()
    var r3 = r2.read_message()
    var if3, it3 = r3.read_tag()
    assert_true(r3.read_bool())
    assert_false(r3.has_more())


def test_repeated_unpacked() raises:
    var w = ProtoWriter()
    w.write_int32(1, Int32(10))
    w.write_int32(1, Int32(20))
    w.write_int32(1, Int32(30))
    var r = roundtrip(w)
    var values = List[Int32]()
    while r.has_more():
        var fld, wt = r.read_tag()
        values.append(r.read_int32())
    assert_equal(len(values), 3)
    assert_equal(values[0], Int32(10))
    assert_equal(values[1], Int32(20))
    assert_equal(values[2], Int32(30))


def test_repeated_packed() raises:
    var packed = ProtoWriter()
    packed.write_varint(UInt64(10))
    packed.write_varint(UInt64(20))
    packed.write_varint(UInt64(30))
    var packed_data = packed.flush()

    var w = ProtoWriter()
    w.write_tag(1, WireType.LEN_DELIM)
    w.write_varint(UInt64(len(packed_data)))
    w._write(packed_data^)

    var r = roundtrip(w)
    var fld, wt = r.read_tag()
    assert_equal(wt.value, UInt8(2))
    var sub = r.read_message()
    var values = List[Int32]()
    while sub.has_more():
        values.append(sub.read_int32())
    assert_equal(len(values), 3)
    assert_equal(values[0], Int32(10))
    assert_equal(values[1], Int32(20))
    assert_equal(values[2], Int32(30))


def test_repeated_strings() raises:
    var w = ProtoWriter()
    w.write_string(5, String("a"))
    w.write_string(5, String("bb"))
    w.write_string(5, String("ccc"))
    var r = roundtrip(w)
    var results = List[String]()
    while r.has_more():
        var fld, wt = r.read_tag()
        results.append(r.read_string())
    assert_equal(len(results), 3)
    assert_equal(results[0], String("a"))
    assert_equal(results[1], String("bb"))
    assert_equal(results[2], String("ccc"))


def test_skip_field() raises:
    """Unknown fields are skipped without corrupting the reader."""
    var w = ProtoWriter()
    w.write_int32(1, Int32(111))
    w.write_string(99, String("skip me"))  # unknown LEN_DELIM
    w.write_double(200, Float64(999.0))  # unknown FIXED_64
    w.write_fixed32(300, UInt32(123))  # unknown FIXED_32
    w.write_int32(2, Int32(222))
    var r = roundtrip(w)

    var fa, ta = r.read_tag()
    assert_equal(Int(fa), 1)
    assert_equal(r.read_int32(), Int32(111))

    var fb, tb = r.read_tag()
    assert_equal(Int(fb), 99)
    r.skip_field(tb)

    var fc, tc = r.read_tag()
    assert_equal(Int(fc), 200)
    r.skip_field(tc)

    var fd, td = r.read_tag()
    assert_equal(Int(fd), 300)
    r.skip_field(td)

    var fe, te = r.read_tag()
    assert_equal(Int(fe), 2)
    assert_equal(r.read_int32(), Int32(222))
    assert_false(r.has_more())


def test_wire_types() raises:
    var w = ProtoWriter()
    w.write_int32(1, Int32(0))  # VARINT (0)
    w.write_fixed64(2, UInt64(0))  # FIXED_64 (1)
    w.write_string(3, String(""))  # LEN_DELIM (2)
    w.write_fixed32(4, UInt32(0))  # FIXED_32 (5)
    var r = roundtrip(w)

    var f1, t1 = r.read_tag()
    assert_equal(t1.value, UInt8(0))
    r.skip_field(t1)
    var f2, t2 = r.read_tag()
    assert_equal(t2.value, UInt8(1))
    r.skip_field(t2)
    var f3, t3 = r.read_tag()
    assert_equal(t3.value, UInt8(2))
    r.skip_field(t3)
    var f4, t4 = r.read_tag()
    assert_equal(t4.value, UInt8(5))
    r.skip_field(t4)
    assert_false(r.has_more())


def run_test(name: String, test: def() raises -> None) -> Bool:
    try:
        test()
        print("  PASS  " + name)
        return True
    except e:
        print("  FAIL  " + name + " - " + String(e))
        return False


def main() raises:
    print("=== protobuf runtime tests ===\n")
    var passed = 0
    var failed = 0

    @parameter
    def check(name: String, f: def() raises -> None):
        if run_test(name, f):
            passed += 1
        else:
            failed += 1

    check("int32", test_int32)
    check("int64", test_int64)
    check("uint32", test_uint32)
    check("uint64", test_uint64)
    check("sint32 (zigzag)", test_sint32)
    check("sint64 (zigzag)", test_sint64)
    check("bool", test_bool)
    check("fixed32", test_fixed32)
    check("fixed64", test_fixed64)
    check("sfixed32", test_sfixed32)
    check("sfixed64", test_sfixed64)
    check("float", test_float)
    check("double", test_double)
    check("string", test_string)
    check("bytes", test_bytes_field)
    check("nested message", test_nested_message)
    check("nested 3 levels", test_nested_roundtrip_3_levels)
    check("repeated unpacked", test_repeated_unpacked)
    check("repeated packed", test_repeated_packed)
    check("repeated strings", test_repeated_strings)
    check("skip_field", test_skip_field)
    check("wire types", test_wire_types)

    print("\n" + String(passed) + " passed, " + String(failed) + " failed")
    if failed > 0:
        raise Error("test failures")
