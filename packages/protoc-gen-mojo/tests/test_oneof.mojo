"""
Tests for generated oneof union structs.
Verifies mutual exclusivity, roundtrip serialization, and discriminant correctness
for all four variant kinds: string, scalar, nested message, and enum.
"""

from testing import assert_equal, assert_true, assert_false
from mo_protobuf import ProtoReader, ProtoWriter
from mo_protobuf.common import Bytes
from oneof_test import Wrapper, WrapperPayload, Inner, Color


def ser(w: Wrapper) raises -> Bytes:
    var wr = ProtoWriter()
    w.serialize(wr)
    return wr.flush()


def par(data: Bytes) raises -> Wrapper:
    var r = ProtoReader(data.copy())
    return Wrapper.parse(r)


# ── discriminant correctness ───────────────────────────────────────────────────


def test_default_unset() raises:
    var w = Wrapper()
    assert_false(Bool(w.payload))


def test_text_discriminant() raises:
    var p = WrapperPayload.text(String("hello"))
    assert_true(p.is_text())
    assert_false(p.is_number())
    assert_false(p.is_nested())
    assert_false(p.is_color())
    assert_equal(p.get_text(), String("hello"))


def test_number_discriminant() raises:
    var p = WrapperPayload.number(Int32(42))
    assert_false(p.is_text())
    assert_true(p.is_number())
    assert_false(p.is_nested())
    assert_equal(p.get_number(), Int32(42))


def test_nested_discriminant() raises:
    var inner = Inner()
    inner.x = Optional[Int32](Int32(7))
    var p = WrapperPayload.nested(inner)
    assert_true(p.is_nested())
    assert_false(p.is_text())
    assert_true(Bool(p.get_nested().x))
    assert_equal(p.get_nested().x.value(), Int32(7))


def test_enum_discriminant() raises:
    var p = WrapperPayload.color(Color.GREEN)
    assert_true(p.is_color())
    assert_false(p.is_text())
    assert_true(p.get_color() == Color.GREEN)


# ── roundtrip (serialize → parse) ─────────────────────────────────────────────


def test_roundtrip_text() raises:
    var w = Wrapper()
    w.payload = Optional[WrapperPayload](WrapperPayload.text(String("world")))
    var w2 = par(ser(w))
    assert_true(Bool(w2.payload))
    assert_true(w2.payload.value().is_text())
    assert_equal(w2.payload.value().get_text(), String("world"))


def test_roundtrip_number() raises:
    var w = Wrapper()
    w.payload = Optional[WrapperPayload](WrapperPayload.number(Int32(-99)))
    var w2 = par(ser(w))
    assert_true(w2.payload.value().is_number())
    assert_equal(w2.payload.value().get_number(), Int32(-99))


def test_roundtrip_nested() raises:
    var inner = Inner()
    inner.x = Optional[Int32](Int32(13))
    var w = Wrapper()
    w.payload = Optional[WrapperPayload](WrapperPayload.nested(inner))
    var w2 = par(ser(w))
    assert_true(w2.payload.value().is_nested())
    assert_equal(w2.payload.value().get_nested().x.value(), Int32(13))


def test_roundtrip_enum() raises:
    var w = Wrapper()
    w.payload = Optional[WrapperPayload](WrapperPayload.color(Color.BLUE))
    var w2 = par(ser(w))
    assert_true(w2.payload.value().is_color())
    assert_true(w2.payload.value().get_color() == Color.BLUE)


def test_last_wins_on_wire() raises:
    """On parse, the last field seen wins (standard protobuf oneof behavior)."""
    var w = ProtoWriter()
    w.write_string(1, String("first"))  # field 1 = text
    w.write_int32(2, Int32(99))  # field 2 = number (overwrites)
    var data = w.flush()
    var r = ProtoReader(data^)
    var wrapper = Wrapper.parse(r)
    assert_true(wrapper.payload.value().is_number())
    assert_equal(wrapper.payload.value().get_number(), Int32(99))


def test_non_oneof_field_unaffected() raises:
    """The 'name' field (outside the oneof) serializes independently."""
    var w = Wrapper()
    w.payload = Optional[WrapperPayload](WrapperPayload.text(String("hi")))
    w.name = Optional[String](String("Alice"))
    var w2 = par(ser(w))
    assert_true(w2.payload.value().is_text())
    assert_equal(w2.name.value(), String("Alice"))


# ── runner ─────────────────────────────────────────────────────────────────────


def run_test(name: String, test: def() raises -> None) -> Bool:
    try:
        test()
        print("  PASS  " + name)
        return True
    except e:
        print("  FAIL  " + name + " - " + String(e))
        return False


def main() raises:
    print("=== oneof tests ===\n")
    var passed = 0
    var failed = 0

    @parameter
    def check(name: String, f: def() raises -> None):
        if run_test(name, f):
            passed += 1
        else:
            failed += 1

    check("default unset", test_default_unset)
    check("text discriminant", test_text_discriminant)
    check("number discriminant", test_number_discriminant)
    check("nested discriminant", test_nested_discriminant)
    check("enum discriminant", test_enum_discriminant)
    check("roundtrip text", test_roundtrip_text)
    check("roundtrip number", test_roundtrip_number)
    check("roundtrip nested", test_roundtrip_nested)
    check("roundtrip enum", test_roundtrip_enum)
    check("last wins on wire", test_last_wins_on_wire)
    check("non-oneof field intact", test_non_oneof_field_unaffected)

    print("\n" + String(passed) + " passed, " + String(failed) + " failed")
    if failed > 0:
        raise Error("test failures")
