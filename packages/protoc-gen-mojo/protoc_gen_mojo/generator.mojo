from std.collections import Dict
from protoc_gen_mojo.gen.google.protobuf.descriptor import (
    FileDescriptorProto,
    DescriptorProto,
    EnumDescriptorProto,
    FieldDescriptorProto,
    OneofDescriptorProto,
    ServiceDescriptorProto,
    MethodDescriptorProto,
    Type,
    Label,
)


def ts[T: Writable](s: T) -> String:
    var out = String()
    out.write(s)
    return out^


@fieldwise_init
struct MapEntry(Copyable, ImplicitlyCopyable):
    var key_mojo_type: String
    var key_read_fn: String
    var key_is_enum: Bool
    var val_mojo_type: String
    var val_read_fn: String
    var val_is_message: Bool
    var val_is_enum: Bool


@fieldwise_init
struct OneofField(Copyable, ImplicitlyCopyable):
    var field_name: String  # proto field name
    var field_number: Int32
    var mojo_type: String  # base mojo type without Optional/List wrapping
    var read_fn: String
    var is_message: Bool
    var is_enum: Bool


comptime Renamings = Dict[String, String]


def make_scalar_types() -> Dict[Int, String]:
    var d = Dict[Int, String]()
    d[Type.TYPE_DOUBLE._value] = "Float64"
    d[Type.TYPE_FLOAT._value] = "Float32"
    d[Type.TYPE_INT64._value] = "Int64"
    d[Type.TYPE_UINT64._value] = "UInt64"
    d[Type.TYPE_INT32._value] = "Int32"
    d[Type.TYPE_FIXED64._value] = "UInt64"
    d[Type.TYPE_FIXED32._value] = "UInt32"
    d[Type.TYPE_UINT32._value] = "UInt32"
    d[Type.TYPE_SFIXED32._value] = "Int32"
    d[Type.TYPE_SFIXED64._value] = "Int64"
    d[Type.TYPE_SINT32._value] = "Int32"
    d[Type.TYPE_SINT64._value] = "Int64"
    d[Type.TYPE_BOOL._value] = "Bool"
    d[Type.TYPE_STRING._value] = "String"
    d[Type.TYPE_BYTES._value] = "List[UInt8]"
    return d^


def make_read_fns() -> Dict[Int, String]:
    var d = Dict[Int, String]()
    d[Type.TYPE_DOUBLE._value] = "double"
    d[Type.TYPE_FLOAT._value] = "float"
    d[Type.TYPE_INT64._value] = "int64"
    d[Type.TYPE_UINT64._value] = "uint64"
    d[Type.TYPE_INT32._value] = "int32"
    d[Type.TYPE_FIXED64._value] = "fixed64"
    d[Type.TYPE_FIXED32._value] = "fixed32"
    d[Type.TYPE_UINT32._value] = "uint32"
    d[Type.TYPE_SFIXED32._value] = "sfixed32"
    d[Type.TYPE_SFIXED64._value] = "sfixed64"
    d[Type.TYPE_SINT32._value] = "sint32"
    d[Type.TYPE_SINT64._value] = "sint64"
    d[Type.TYPE_BOOL._value] = "bool"
    d[Type.TYPE_STRING._value] = "string"
    d[Type.TYPE_BYTES._value] = "bytes"
    return d^


# ── string helpers ─────────────────────────────────────────────────────────────


def last_component(s: String) -> String:
    """Returns the part of s after the last dot."""
    var b = s.as_bytes()
    var last_dot = -1
    for i in range(len(b)):
        if b[i] == 46:  # ord('.')
            last_dot = i
    if last_dot == -1:
        return s
    var out = List[UInt8]()
    for i in range(last_dot + 1, len(b)):
        out.append(b[i])
    return String(unsafe_from_utf8=out^)


def apply_indent(code: String, indent: Int) -> String:
    if indent == 0:
        return code
    var pad = String()
    for _ in range(indent * 4):
        pad += " "
    var result = String()
    var b = code.as_bytes()
    var line_start = 0
    for i in range(len(b)):
        if b[i] == 10:  # ord('\n')
            var line = List[UInt8]()
            for j in range(line_start, i + 1):
                line.append(b[j])
            result += pad + String(line^)
            line_start = i + 1
    if line_start < len(b):
        var tail = List[UInt8]()
        for j in range(line_start, len(b)):
            tail.append(b[j])
        result += pad + String(tail^)
    return result


def capitalize_first(s: String) -> String:
    var b = s.as_bytes()
    if len(b) == 0:
        return s
    var out = List[UInt8]()
    var c = b[0]
    out.append(c - 32 if c >= 97 and c <= 122 else c)  # a-z -> A-Z
    for i in range(1, len(b)):
        out.append(b[i])
    return String(unsafe_from_utf8=out^)


# ── field type resolution ──────────────────────────────────────────────────────


def field_base_type(
    field: FieldDescriptorProto,
    renamings: Renamings,
    scalar_types: Dict[Int, String],
) -> String:
    if not field.type:
        return "Unknown"
    var t = field.type.value()
    if t == Type.TYPE_MESSAGE or t == Type.TYPE_ENUM:
        var cls = last_component(field.type_name.value() if field.type_name else "")
        return renamings.get(cls, cls)
    return scalar_types.get(t._value, "Unknown")


def field_full_type(
    field: FieldDescriptorProto,
    renamings: Renamings,
    scalar_types: Dict[Int, String],
) -> String:
    var base = field_base_type(field, renamings, scalar_types)
    if not field.label:
        return base
    var lbl = field.label.value()
    if lbl == Label.LABEL_REPEATED:
        return "List[" + base + "]"
    if lbl == Label.LABEL_OPTIONAL:
        return "Optional[" + base + "]"
    return base


# ── generators ─────────────────────────────────────────────────────────────────


def proto_path_to_module(path: String, prefix: String = "") -> String:
    """'google/protobuf/descriptor.proto' -> 'google.protobuf.descriptor' (with optional prefix)."""
    var b = path.as_bytes()
    var out = List[UInt8]()
    var end = len(b) - 6  # strip .proto suffix
    for i in range(end):
        if b[i] == 47:  # ord('/')
            out.append(46)  # ord('.')
        else:
            out.append(b[i])
    var mod = String(unsafe_from_utf8=out^)
    return (prefix + mod) if len(prefix) > 0 else mod


def get_map_entry(
    map_entries: Dict[String, MapEntry],
    f: FieldDescriptorProto,
    parent_full: String,
) raises -> Optional[MapEntry]:
    if not (f.label and f.label.value() == Label.LABEL_REPEATED):
        return None
    if not (f.type and f.type.value() == Type.TYPE_MESSAGE):
        return None
    if not f.type_name:
        return None
    var entry_name = parent_full + last_component(f.type_name.value())
    if entry_name not in map_entries:
        return None
    return map_entries[entry_name]


def generate_prelude(deps: List[String], module_prefix: String = "", has_services: Bool = False) -> String:
    var out = (
        '"""\n'
        "   AUTO-GENERATED CODE\n"
        "   !!! DO NOT EDIT !!!\n"
        '"""\n\n'
        "from mo_protobuf import ProtoReader, ProtoWriter, ProtoSerializable\n"
        "from mo_protobuf.common import FieldNumber, WireType\n"
    )
    for dep in deps:
        var mod = proto_path_to_module(dep, module_prefix)
        out += ts(t"from {mod} import *\n")
    if has_services:
        out += "from mo_grpc import GrpcChannel, GrpcServerStream, GrpcClientStream, GrpcBidiStream\n"
    return out


# ── oneof helpers ──────────────────────────────────────────────────────────────


def get_oneof_fields(
    desc: DescriptorProto,
    oneof_idx: Int,
    renamings: Renamings,
    scalar_types: Dict[Int, String],
    read_fns: Dict[Int, String],
) -> List[OneofField]:
    """Return fields belonging to oneof group `oneof_idx`, excluding synthetic proto3 optionals."""
    var result = List[OneofField]()
    for f in desc.field:
        if not f.oneof_index:
            continue
        if f.proto3_optional and f.proto3_optional.value():
            continue
        if Int(f.oneof_index.value()) != oneof_idx:
            continue
        result.append(
            OneofField(
                f.name.value() if f.name else "unknown",
                f.number.value() if f.number else Int32(0),
                field_base_type(f, renamings, scalar_types),
                read_fns.get(f.type.value()._value if f.type else 0, "Unknown"),
                f.type and f.type.value() == Type.TYPE_MESSAGE,
                f.type and f.type.value() == Type.TYPE_ENUM,
            )
        )
    return result^


def generate_oneof_union(union_type: String, fields: List[OneofField], indent: Int = 0) -> String:
    """Generate a discriminant-tagged union struct for one oneof group."""
    var out = ts(t"struct {union_type}(Copyable, Movable):\n")
    out += "    var _tag: Int\n"
    for of in fields:
        out += ts(t"    var _{of.field_name}: Optional[{of.mojo_type}]\n")

    out += "\n    def __init__(out self):\n"
    out += "        self._tag = 0\n"
    for of in fields:
        out += ts(t"        self._{of.field_name} = None\n")

    var tag = 1
    for of in fields:
        out += "\n    @staticmethod\n"
        out += ts(t"    def {of.field_name}(v: {of.mojo_type}) -> Self:\n")
        out += "        var s = Self()\n"
        out += ts(t"        s._tag = {tag}\n")
        out += ts(t"        s._{of.field_name} = v.copy()\n")
        out += "        return s^\n"
        tag += 1

    tag = 1
    for of in fields:
        out += ts(t"\n    def is_{of.field_name}(self) -> Bool:\n")
        out += ts(t"        return self._tag == {tag}\n")
        out += ts(t"\n    def get_{of.field_name}(self) -> {of.mojo_type}:\n")
        if of.is_message:
            out += ts(t"        return self._{of.field_name}.value().copy()\n")
        else:
            out += ts(t"        return self._{of.field_name}.value()\n")
        tag += 1

    return apply_indent(out, indent)


def generate_enum(desc: EnumDescriptorProto, indent: Int = 0) -> String:
    var name = desc.name.value() if desc.name else "Unknown"

    var out = String("@fieldwise_init\n")
    out += ts(t"struct {name}(ProtoSerializable, Equatable, ImplicitlyCopyable):\n")
    out += "    var _value: Int\n"
    for opt in desc.value:
        var oname = opt.name.value() if opt.name else "UNKNOWN"
        var oval = String(Int(opt.number.value())) if opt.number else "0"
        out += "    \n"
        out += ts(t"    comptime {oname} = {name}({oval})\n")

    out += "\n"
    out += "    @staticmethod\n"
    out += "    def parse(mut reader: ProtoReader) raises -> Self:\n"
    out += "        return Self(Int(reader.read_enum()))\n"
    out += "\n"
    out += "    def serialize(self, mut writer: ProtoWriter):\n"
    out += "        writer.write_varint(UInt64(self._value))\n"
    out += "\n"
    out += "    def __eq__(self, other: Self) -> Bool:\n"
    out += "        return self._value == other._value\n"
    out += "\n"
    out += "    def __ne__(self, other: Self) -> Bool:\n"
    out += "        return not (self == other)\n"
    return apply_indent(out, indent)


def generate_message(
    desc: DescriptorProto,
    mut renamings: Renamings,
    scalar_types: Dict[Int, String],
    read_fns: Dict[Int, String],
    indent: Int = 0,
    prefix: String = "",
) raises -> List[String]:
    var name = desc.name.value() if desc.name else "Unknown"
    var full = prefix + name
    renamings[name] = full

    # Collect map entry info before recursing, skip generating them as structs
    var map_entries = Dict[String, MapEntry]()
    for inner in desc.nested_type:
        var is_map_entry = inner.options and inner.options.value().map_entry and inner.options.value().map_entry.value()
        if is_map_entry:
            var entry_full = prefix + name + (inner.name.value() if inner.name else "")
            var key_mtype = String("String")
            var key_rfn = String("string")
            var key_isenum = False
            var val_mtype = String("String")
            var val_rfn = String("string")
            var val_is_message = False
            var val_isenum = False
            for ef in inner.field:
                var fnum = ef.number.value() if ef.number else Int32(0)
                if fnum == 1:  # key
                    key_mtype = field_base_type(ef, renamings, scalar_types)
                    key_rfn = read_fns.get(ef.type.value()._value if ef.type else 0, "string")
                    key_isenum = ef.type and ef.type.value() == Type.TYPE_ENUM
                elif fnum == 2:  # value
                    val_mtype = field_base_type(ef, renamings, scalar_types)
                    val_rfn = read_fns.get(ef.type.value()._value if ef.type else 0, "string")
                    val_is_message = ef.type and ef.type.value() == Type.TYPE_MESSAGE
                    val_isenum = ef.type and ef.type.value() == Type.TYPE_ENUM
            map_entries[entry_full] = MapEntry(
                key_mtype,
                key_rfn,
                key_isenum,
                val_mtype,
                val_rfn,
                val_is_message,
                val_isenum,
            )
        else:
            renamings[inner.name.value() if inner.name else ""] = (
                prefix + name + (inner.name.value() if inner.name else "")
            )

    # ── detect real oneof groups (skip proto3 synthetic optionals) ────────────
    # field_number -> oneof_index for fields in real oneofs
    var oneof_by_fnum = Dict[Int, Int]()
    var num_oneofs = len(desc.oneof_decl)
    for i in range(num_oneofs):
        var fields = get_oneof_fields(desc, i, renamings, scalar_types, read_fns)
        for of in fields:
            oneof_by_fnum[Int(of.field_number)] = i

    var parts = List[String]()

    # emit oneof union structs before the parent struct
    for i in range(num_oneofs):
        var oname = desc.oneof_decl[i].name.value() if desc.oneof_decl[i].name else "Oneof" + String(i)
        var fields = get_oneof_fields(desc, i, renamings, scalar_types, read_fns)
        if len(fields) > 0:
            var union_type = full + capitalize_first(oname)
            parts.append(apply_indent(generate_oneof_union(union_type, fields), indent))

    for inner in desc.nested_type:
        var is_map_entry = inner.options and inner.options.value().map_entry and inner.options.value().map_entry.value()
        if not is_map_entry:
            for p in generate_message(inner, renamings, scalar_types, read_fns, indent, prefix + name):
                parts.append(p)
    for inner in desc.enum_type:
        parts.append(generate_enum(inner, indent))

    # struct fields
    var out = String("@fieldwise_init\n")
    out += ts(t"struct {full}(ProtoSerializable, Copyable, Movable):\n")
    if len(desc.field) == 0 and len(oneof_by_fnum) == 0:
        out += "    ...\n"
    else:
        var seen_oneof_indices = List[Int]()
        for f in desc.field:
            var fname = f.name.value() if f.name else "unknown"
            var fnum = Int(f.number.value()) if f.number else 0
            var me = get_map_entry(map_entries, f, full)
            if fnum in oneof_by_fnum:
                var oi = oneof_by_fnum[fnum]
                var already = False
                for s in seen_oneof_indices:
                    if s == oi:
                        already = True
                        break
                if not already:
                    seen_oneof_indices.append(oi)
                    var oname = desc.oneof_decl[oi].name.value() if desc.oneof_decl[oi].name else "oneof" + String(oi)
                    var union_type = full + capitalize_first(oname)
                    out += ts(t"    var {oname}: Optional[{union_type}]\n")
            elif me:
                var e = me.value()
                out += ts(t"    var {fname}: Dict[{e.key_mojo_type}, {e.val_mojo_type}]\n")
            else:
                var ftype = field_full_type(f, renamings, scalar_types)
                out += ts(t"    var {fname}: {ftype}\n")

    if len(desc.field) > 0 or len(oneof_by_fnum) > 0:
        out += "\n    def __init__(out self):\n"
        var seen_oneof_init = List[Int]()
        for f in desc.field:
            var fname = f.name.value() if f.name else "unknown"
            var fnum = Int(f.number.value()) if f.number else 0
            var is_rep = f.label and f.label.value() == Label.LABEL_REPEATED
            var is_opt = f.label and f.label.value() == Label.LABEL_OPTIONAL
            var me = get_map_entry(map_entries, f, full)
            if fnum in oneof_by_fnum:
                var oi = oneof_by_fnum[fnum]
                var already = False
                for s in seen_oneof_init:
                    if s == oi:
                        already = True
                        break
                if not already:
                    seen_oneof_init.append(oi)
                    var oname = desc.oneof_decl[oi].name.value() if desc.oneof_decl[oi].name else "oneof" + String(oi)
                    out += ts(t"        self.{oname} = None\n")
            elif me:
                var e = me.value()
                out += ts(t"        self.{fname} = Dict[{e.key_mojo_type}, {e.val_mojo_type}]()\n")
            elif is_rep:
                var base = field_base_type(f, renamings, scalar_types)
                out += ts(t"        self.{fname} = List[{base}]()\n")
            elif is_opt:
                out += ts(t"        self.{fname} = None\n")
            else:  # required
                var zero: String
                if f.type and f.type.value() == Type.TYPE_STRING:
                    zero = "String()"
                elif f.type and f.type.value() == Type.TYPE_BOOL:
                    zero = "False"
                elif f.type and (f.type.value() == Type.TYPE_FLOAT or f.type.value() == Type.TYPE_DOUBLE):
                    zero = "0.0"
                else:
                    zero = "0"
                out += ts(t"        self.{fname} = {zero}\n")

    # parse
    out += "\n"
    out += "    @staticmethod\n"
    out += "    def parse(mut reader: ProtoReader) raises -> Self:\n"
    out += "        var instance = Self()\n"

    # Pre-reserve a small initial capacity for every repeated field so the
    # first few appends don't trigger O(log n) reallocations. Maps use Dict
    # which has its own growth strategy and no `reserve` method.
    for f in desc.field:
        var fname = f.name.value() if f.name else "unknown"
        var is_rep = f.label and f.label.value() == Label.LABEL_REPEATED
        var is_map = Bool(get_map_entry(map_entries, f, full))
        if is_rep and not is_map:
            out += ts(t"        instance.{fname}.reserve(8)\n")

    out += "        while reader.has_more():\n"
    out += "            var wire_tag = reader.read_varint()\n"
    out += "            var field_number = Int(wire_tag >> 3)\n"
    out += "\n"
    var first = True
    for f in desc.field:
        var fname = f.name.value() if f.name else "unknown"
        var num = String(Int(f.number.value())) if f.number else "0"
        var fnum = Int(f.number.value()) if f.number else 0
        var base = field_base_type(f, renamings, scalar_types)
        var branch = "if" if first else "elif"
        out += ts(t"            {branch} field_number == {num}:\n")
        first = False

        if fnum in oneof_by_fnum:
            var oi = oneof_by_fnum[fnum]
            var oname = desc.oneof_decl[oi].name.value() if desc.oneof_decl[oi].name else "oneof" + String(oi)
            var utype = full + capitalize_first(oname)
            if f.type and f.type.value() == Type.TYPE_MESSAGE:
                out += "                var saved_end = reader.push_limit()\n"
                out += ts(t"                instance.{oname} = {utype}.{fname}({base}.parse(reader))\n")
                out += "                reader.pop_limit(saved_end)\n"
            elif f.type and f.type.value() == Type.TYPE_ENUM:
                out += ts(t"                instance.{oname} = {utype}.{fname}({base}(Int(reader.read_enum())))\n")
            else:
                var rdfn = read_fns.get(f.type.value()._value if f.type else 0, "Unknown")
                out += ts(t"                instance.{oname} = {utype}.{fname}(reader.read_{rdfn}())\n")
            continue
        var is_rep = f.label and f.label.value() == Label.LABEL_REPEATED
        var me_parse = get_map_entry(map_entries, f, full)
        if me_parse:
            var e = me_parse.value()
            out += "                var entry_end = reader.push_limit()\n"
            if e.key_mojo_type != "String":
                out += ts(t"                var map_key = {e.key_mojo_type}()\n")
            else:
                out += "                var map_key = String()\n"
            if e.val_is_message:
                out += ts(t"                var map_val_opt = Optional[{e.val_mojo_type}](None)\n")
            elif e.val_mojo_type != "String":
                out += ts(t"                var map_val = {e.val_mojo_type}()\n")
            else:
                out += "                var map_val = String()\n"
            out += "                while reader.has_more():\n"
            out += "                    var entry_tag = reader.read_varint()\n"
            out += "                    var entry_field_number = Int(entry_tag >> 3)\n"
            out += "                    if entry_field_number == 1:\n"
            if e.key_is_enum:
                out += ts(t"                        map_key = {e.key_mojo_type}(Int(reader.read_enum()))\n")
            else:
                out += ts(t"                        map_key = reader.read_{e.key_read_fn}()\n")
            out += "                    elif entry_field_number == 2:\n"
            if e.val_is_message:
                out += "                        var val_end = reader.push_limit()\n"
                out += ts(t"                        map_val_opt = {e.val_mojo_type}.parse(reader)\n")
                out += "                        reader.pop_limit(val_end)\n"
            elif e.val_is_enum:
                out += ts(t"                        map_val = {e.val_mojo_type}(Int(reader.read_enum()))\n")
            else:
                out += ts(t"                        map_val = reader.read_{e.val_read_fn}()\n")
            out += "                    else:\n"
            out += "                        reader.skip_field(WireType(UInt8(entry_tag & 0x07)))\n"
            out += "                reader.pop_limit(entry_end)\n"
            if e.val_is_message:
                out += "                if map_val_opt:\n"
                out += ts(t"                    instance.{fname}[map_key] = map_val_opt.value().copy()\n")
            else:
                out += ts(t"                instance.{fname}[map_key] = map_val\n")
        elif f.type and f.type.value() == Type.TYPE_MESSAGE:
            out += "                var saved_end = reader.push_limit()\n"
            if is_rep:
                out += ts(t"                instance.{fname}.append({base}.parse(reader))\n")
            else:
                out += ts(t"                instance.{fname} = {base}.parse(reader)\n")
            out += "                reader.pop_limit(saved_end)\n"
        elif f.type and f.type.value() == Type.TYPE_ENUM:
            if is_rep:
                out += "                if (wire_tag & 0x07) == 2:\n"
                out += "                    var packed_end = reader.push_limit()\n"
                out += "                    while reader.has_more():\n"
                out += ts(t"                        instance.{fname}.append({base}(Int(reader.read_enum())))\n")
                out += "                    reader.pop_limit(packed_end)\n"
                out += "                else:\n"
                out += ts(t"                    instance.{fname}.append({base}(Int(reader.read_enum())))\n")
            else:
                out += ts(t"                instance.{fname} = {base}(Int(reader.read_enum()))\n")
        else:
            var fn_name = read_fns.get(f.type.value()._value if f.type else 0, "Unknown")
            if is_rep:
                if fn_name == "string" or fn_name == "bytes":
                    out += ts(t"                instance.{fname}.append(reader.read_{fn_name}())\n")
                else:
                    out += "                if (wire_tag & 0x07) == 2:\n"
                    out += "                    var packed_end = reader.push_limit()\n"
                    out += "                    while reader.has_more():\n"
                    out += ts(t"                        instance.{fname}.append(reader.read_{fn_name}())\n")
                    out += "                    reader.pop_limit(packed_end)\n"
                    out += "                else:\n"
                    out += ts(t"                    instance.{fname}.append(reader.read_{fn_name}())\n")
            else:
                out += ts(t"                instance.{fname} = reader.read_{fn_name}()\n")
    out += "            else:\n"
    out += "                reader.skip_field(WireType(UInt8(wire_tag & 0x07)))\n"
    out += "        return instance^\n"

    # serialize
    out += "\n    def serialize(self, mut writer: ProtoWriter):\n"
    if len(desc.field) == 0:
        out += "        ...\n"
    else:
        var seen_oneof_ser = List[Int]()
        for f in desc.field:
            var fname = f.name.value() if f.name else "unknown"
            var num = String(Int(f.number.value())) if f.number else "0"
            var fnum = Int(f.number.value()) if f.number else 0
            var is_rep = f.label and f.label.value() == Label.LABEL_REPEATED
            var is_opt = f.label and f.label.value() == Label.LABEL_OPTIONAL
            var me_ser = get_map_entry(map_entries, f, full)
            if fnum in oneof_by_fnum:
                var oi = oneof_by_fnum[fnum]
                var already = False
                for s in seen_oneof_ser:
                    if s == oi:
                        already = True
                        break
                if not already:
                    seen_oneof_ser.append(oi)
                    var oname = desc.oneof_decl[oi].name.value() if desc.oneof_decl[oi].name else "oneof" + String(oi)
                    var group = get_oneof_fields(desc, oi, renamings, scalar_types, read_fns)
                    out += ts(t"        if self.{oname}:\n")
                    out += ts(t"            var pu = self.{oname}.value().copy()\n")
                    var gfirst = True
                    for gf in group:
                        var gnum = String(Int(gf.field_number))
                        var gbranch = "if" if gfirst else "elif"
                        out += ts(t"            {gbranch} pu.is_{gf.field_name}():\n")
                        gfirst = False
                        if gf.is_message:
                            out += ts(t"                var len_slot = writer.begin_message({gnum})\n")
                            out += ts(t"                pu.get_{gf.field_name}().serialize(writer)\n")
                            out += "                writer.end_message(len_slot)\n"
                        elif gf.is_enum:
                            out += ts(
                                t"                writer.write_int32({gnum}, Int32(pu.get_{gf.field_name}()._value))\n"
                            )
                        else:
                            out += ts(t"                writer.write_{gf.read_fn}({gnum}, pu.get_{gf.field_name}())\n")
                continue  # skip per-field serialize for oneof members

            if me_ser:
                var e = me_ser.value()
                out += ts(t"        for item in self.{fname}.items():\n")
                out += ts(t"            var entry_slot = writer.begin_message({num})\n")
                if e.key_is_enum:
                    out += "            writer.write_int32(1, Int32(item.key._value))\n"
                else:
                    out += ts(t"            writer.write_{e.key_read_fn}(1, item.key)\n")
                if e.val_is_message:
                    out += "            var value_slot = writer.begin_message(2)\n"
                    out += "            item.value.serialize(writer)\n"
                    out += "            writer.end_message(value_slot)\n"
                elif e.val_is_enum:
                    out += "            writer.write_int32(2, Int32(item.value._value))\n"
                else:
                    out += ts(t"            writer.write_{e.val_read_fn}(2, item.value)\n")
                out += "            writer.end_message(entry_slot)\n"
            elif f.type and f.type.value() == Type.TYPE_MESSAGE:
                var is_self_ref = field_base_type(f, renamings, scalar_types) == full
                if is_rep:
                    out += ts(t"        for item in self.{fname}:\n")
                    out += ts(t"            var len_slot = writer.begin_message({num})\n")
                    if is_self_ref:
                        out += "            var ser = Self.serialize\n"
                        out += "            ser(item, writer)\n"
                    else:
                        out += "            item.serialize(writer)\n"
                    out += "            writer.end_message(len_slot)\n"
                elif is_opt:
                    out += ts(t"        if self.{fname}:\n")
                    out += ts(t"            var len_slot = writer.begin_message({num})\n")
                    if is_self_ref:
                        out += "            var ser = Self.serialize\n"
                        out += ts(t"            ser(self.{fname}.value(), writer)\n")
                    else:
                        out += ts(t"            self.{fname}.value().serialize(writer)\n")
                    out += "            writer.end_message(len_slot)\n"
                else:  # required message
                    out += ts(t"        var len_slot = writer.begin_message({num})\n")
                    if is_self_ref:
                        out += "        var ser = Self.serialize\n"
                        out += ts(t"        ser(self.{fname}, writer)\n")
                    else:
                        out += ts(t"        self.{fname}.serialize(writer)\n")
                    out += "        writer.end_message(len_slot)\n"
            elif f.type and f.type.value() == Type.TYPE_ENUM:
                if is_rep:
                    out += ts(t"        for item in self.{fname}:\n")
                    out += ts(t"            writer.write_int32({num}, Int32(item._value))\n")
                elif is_opt:
                    out += ts(t"        if self.{fname}:\n")
                    out += ts(t"            writer.write_int32({num}, Int32(self.{fname}.value()._value))\n")
                else:  # required enum
                    out += ts(t"        writer.write_int32({num}, Int32(self.{fname}._value))\n")
            else:
                var fn_name = read_fns.get(f.type.value()._value if f.type else 0, "Unknown")
                if is_rep:
                    out += ts(t"        for item in self.{fname}:\n")
                    out += ts(t"            writer.write_{fn_name}({num}, item)\n")
                elif is_opt:
                    out += ts(t"        if self.{fname}:\n")
                    out += ts(t"            writer.write_{fn_name}({num}, self.{fname}.value())\n")
                else:
                    out += ts(t"        writer.write_{fn_name}({num}, self.{fname})\n")

    parts.append(apply_indent(out, indent))
    return parts^


def generate_service(svc: ServiceDescriptorProto, package: String) -> String:
    """Generate a server trait and client stub for one service."""
    var name = svc.name.value() if svc.name else "Unknown"
    var pkg_prefix = "/" + package + "." if len(package) > 0 else "/"

    var out = ts(t"trait {name}Servicer:\n")
    for m in svc.method:
        var mname = m.name.value() if m.name else "Unknown"
        var req = last_component(m.input_type.value() if m.input_type else "")
        var resp = last_component(m.output_type.value() if m.output_type else "")
        var cs = m.client_streaming and m.client_streaming.value()
        var ss = m.server_streaming and m.server_streaming.value()
        if not cs and not ss:
            out += ts(t"    def {mname}(self, request: {req}) raises -> {resp}: ...\n")
        elif not cs and ss:
            out += ts(t"    def {mname}(self, request: {req}, ctx: GrpcServerStream[{resp}]) raises: ...\n")
        elif cs and not ss:
            out += ts(t"    def {mname}(self, stream: GrpcClientStream[{req}]) raises -> {resp}: ...\n")
        else:
            out += ts(t"    def {mname}(self, stream: GrpcBidiStream[{req}, {resp}]) raises: ...\n")

    out += "\n\n"
    out += ts(t"struct {name}Stub:\n")
    out += "    var _channel: GrpcChannel\n"
    out += "\n    def __init__(out self, var channel: GrpcChannel):\n"
    out += "        self._channel = channel^\n"

    for m in svc.method:
        var mname = m.name.value() if m.name else "Unknown"
        var req = last_component(m.input_type.value() if m.input_type else "")
        var resp = last_component(m.output_type.value() if m.output_type else "")
        var path = pkg_prefix + name + "/" + mname
        var cs = m.client_streaming and m.client_streaming.value()
        var ss = m.server_streaming and m.server_streaming.value()
        if not cs and not ss:
            out += ts(t"\n    def {mname}(mut self, request: {req}, timeout_ms: Int = 0, metadata: Dict[String, String] = Dict[String, String]()) raises -> {resp}:\n")
            out += ts(t'        return self._channel.unary_unary[{req}, {resp}]("{path}", request, timeout_ms, metadata)\n')
        elif not cs and ss:
            out += ts(t"\n    def {mname}(mut self, request: {req}) raises -> GrpcServerStream[{resp}]:\n")
            out += ts(t'        return self._channel.unary_stream[{req}, {resp}]("{path}", request)\n')
        elif cs and not ss:
            out += ts(t"\n    def {mname}(mut self) raises -> GrpcClientStream[{req}, {resp}]:\n")
            out += ts(t'        return self._channel.stream_unary[{req}, {resp}]("{path}")\n')
        else:
            out += ts(t"\n    def {mname}(mut self) raises -> GrpcBidiStream[{req}, {resp}]:\n")
            out += ts(t'        return self._channel.bidi[{req}, {resp}]("{path}")\n')

    return out


def generate_file(proto_file: FileDescriptorProto, module_prefix: String = "") raises -> String:
    var renamings = Renamings()
    var scalar_types = make_scalar_types()
    var read_fns = make_read_fns()
    var chunks = List[String]()

    var deps = List[String]()
    for dep in proto_file.dependency:
        deps.append(dep)
    var has_services = len(proto_file.service) > 0
    chunks.append(generate_prelude(deps, module_prefix, has_services))
    for e in proto_file.enum_type:
        chunks.append(generate_enum(e, 0))
    for m in proto_file.message_type:
        for p in generate_message(m, renamings, scalar_types, read_fns, 0, ""):
            chunks.append(p)
    var pkg = proto_file.package.value() if proto_file.package else ""
    for svc in proto_file.service:
        chunks.append(generate_service(svc, pkg))

    var out = String()
    var first = True
    for chunk in chunks:
        if not first:
            out += "\n\n"
        out += chunk
        first = False
    return out
