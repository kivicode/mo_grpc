from testing import assert_equal, assert_true, assert_false
from protobuf_runtime import ProtoReader, ProtoWriter
from protobuf_runtime.common import Bytes
from person import Person, Address, PhoneType


def test_empty_message() raises:
    """A default-constructed message serializes to empty bytes and parses back."""
    var p = Person()
    var data = serialize(p)
    assert_equal(len(data), 0)
    var p2 = parse(data)
    assert_false(Bool(p2.name))
    assert_false(Bool(p2.id))


def test_optional_string_and_int() raises:
    var p = Person()
    p.name = Optional[String](String("Alice"))
    p.id = Optional[Int32](Int32(42))
    var p2 = parse(serialize(p))
    assert_true(Bool(p2.name))
    assert_equal(p2.name.value(), String("Alice"))
    assert_true(Bool(p2.id))
    assert_equal(p2.id.value(), Int32(42))


def test_repeated_field() raises:
    var p = Person()
    p.name = Optional[String](String("Bob"))
    p.emails.append(String("a@test.com"))
    p.emails.append(String("b@test.com"))
    var p2 = parse(serialize(p))
    assert_equal(len(p2.emails), 2)
    assert_equal(p2.emails[0], String("a@test.com"))
    assert_equal(p2.emails[1], String("b@test.com"))


def test_nested_message() raises:
    var p = Person()
    p.address = Optional[Address](Address())
    p.address.value().street = Optional[String](String("123 Main St"))
    p.address.value().city = Optional[String](String("Springfield"))
    var p2 = parse(serialize(p))
    assert_true(Bool(p2.address))
    assert_equal(p2.address.value().street.value(), String("123 Main St"))
    assert_equal(p2.address.value().city.value(), String("Springfield"))


def test_enum_field() raises:
    var p = Person()
    p.phone_type = Optional[PhoneType](PhoneType.MOBILE)
    var p2 = parse(serialize(p))
    assert_true(Bool(p2.phone_type))
    assert_true(p2.phone_type.value() == PhoneType.MOBILE)


def test_map_field() raises:
    var p = Person()
    p.attributes["role"] = String("admin")
    p.attributes["level"] = String("3")
    var p2 = parse(serialize(p))
    assert_equal(len(p2.attributes), 2)
    assert_equal(p2.attributes[String("role")], String("admin"))
    assert_equal(p2.attributes[String("level")], String("3"))


def test_absent_optional_not_written() raises:
    """Optional fields not set produce no bytes."""
    var p = Person()
    p.name = Optional[String](String("Carol"))
    # id not set
    var data = serialize(p)
    # Only 'name' field should be present; parse and confirm id is absent
    var p2 = parse(data)
    assert_false(Bool(p2.id))


def run_test(name: String, test: def() raises -> None) -> Bool:
    try:
        test()
        print("  PASS  " + name)
        return True
    except e:
        print("  FAIL  " + name + " — " + String(e))
        return False


def main() raises:
    print("=== codegen roundtrip tests ===\n")
    var passed = 0
    var failed = 0

    @parameter
    def check(name: String, f: def() raises -> None):
        if run_test(name, f):
            passed += 1
        else:
            failed += 1

    check("empty message", test_empty_message)
    check("optional string + int32", test_optional_string_and_int)
    check("repeated string", test_repeated_field)
    check("nested message", test_nested_message)
    check("enum field", test_enum_field)
    check("map<string,string>", test_map_field)
    check("absent optional omitted", test_absent_optional_not_written)

    print("\n" + String(passed) + " passed, " + String(failed) + " failed")
    if failed > 0:
        raise Error("test failures")


def serialize(p: Person) raises -> Bytes:
    var w = ProtoWriter()
    p.serialize(w)
    return w.flush()


def parse(data: Bytes) raises -> Person:
    var r = ProtoReader(data.copy())
    return Person.parse(r)
