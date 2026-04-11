from collections import Dict
from protoc_gen_mojo.gen.google.protobuf.descriptor import (
    FileDescriptorProto,
    DescriptorProto,
    EnumDescriptorProto,
    FieldDescriptorProto,
    Type,
    Label,
)


@fieldwise_init
struct MapEntry(Copyable, ImplicitlyCopyable):
    var key_mojo_type: String
    var key_read_fn: String
    var key_is_enum: Bool
    var val_mojo_type: String
    var val_read_fn: String
    var val_is_message: Bool
    var val_is_enum: Bool


comptime Renamings = Dict[String, String]


# ── type maps (built once in generate_file) ────────────────────────────────────


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
    """'google/protobuf/descriptor.proto' → 'google.protobuf.descriptor' (with optional prefix)."""
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


def generate_prelude(deps: List[String], module_prefix: String = "") -> String:
    var out = (
        '"""\n'
        "   AUTO-GENERATED CODE\n"
        "   !!! DO NOT EDIT !!!\n"
        '"""\n\n'
        "from protobuf_runtime import ProtoReader, ProtoWriter, ProtoSerializable\n"
    )
    for dep in deps:
        out += "from " + proto_path_to_module(dep, module_prefix) + " import *\n"
    return out


def generate_enum(desc: EnumDescriptorProto, indent: Int = 0) -> String:
    var name = desc.name.value() if desc.name else "Unknown"

    var out = "@fieldwise_init\nstruct " + name + "(ProtoSerializable, Equatable, ImplicitlyCopyable):\n"
    out += "    var _value: Int\n"
    for opt in desc.value:
        var oname = opt.name.value() if opt.name else "UNKNOWN"
        var oval = String(Int(opt.number.value())) if opt.number else "0"
        out += "    \n    comptime " + oname + " = " + name + "(" + oval + ")\n"

    out += (
        "\n"
        "    @staticmethod\n"
        "    def parse(mut reader: ProtoReader) raises -> Self:\n"
        "        return Self(Int(reader.read_enum()))\n"
        "\n"
        "    def serialize(self, mut writer: ProtoWriter):\n"
        "        writer.write_varint(UInt64(self._value))\n"
        "\n"
        "    def __eq__(self, other: Self) -> Bool:\n"
        "        return self._value == other._value\n"
        "\n"
        "    def __ne__(self, other: Self) -> Bool:\n"
        "        return not (self == other)\n"
    )
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

    var parts = List[String]()
    for inner in desc.nested_type:
        var is_map_entry = inner.options and inner.options.value().map_entry and inner.options.value().map_entry.value()
        if not is_map_entry:
            for p in generate_message(inner, renamings, scalar_types, read_fns, indent, prefix + name):
                parts.append(p)
    for inner in desc.enum_type:
        parts.append(generate_enum(inner, indent))

    # struct fields
    var out = "@fieldwise_init\nstruct " + full + "(ProtoSerializable, Copyable):\n"
    if len(desc.field) == 0:
        out += "    ...\n"
    else:
        for f in desc.field:
            var fname = f.name.value() if f.name else "unknown"
            var me = get_map_entry(map_entries, f, full)
            if me:
                var e = me.value()
                out += "    var " + fname + ": Dict[" + e.key_mojo_type + ", " + e.val_mojo_type + "]\n"
            else:
                out += "    var " + fname + ": " + field_full_type(f, renamings, scalar_types) + "\n"

    # __init__ with defaults (needed for Self() in parse)
    if len(desc.field) > 0:
        out += "\n    def __init__(out self):\n"
        for f in desc.field:
            var fname = f.name.value() if f.name else "unknown"
            var is_rep = f.label and f.label.value() == Label.LABEL_REPEATED
            var is_opt = f.label and f.label.value() == Label.LABEL_OPTIONAL
            var me = get_map_entry(map_entries, f, full)
            if me:
                var e = me.value()
                out += "        self." + fname + " = Dict[" + e.key_mojo_type + ", " + e.val_mojo_type + "]()\n"
            elif is_rep:
                var base = field_base_type(f, renamings, scalar_types)
                out += "        self." + fname + " = List[" + base + "]()\n"
            elif is_opt:
                out += "        self." + fname + " = None\n"
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
                out += "        self." + fname + " = " + zero + "\n"

    # parse
    out += (
        "\n"
        "    @staticmethod\n"
        "    def parse(mut reader: ProtoReader) raises -> Self:\n"
        "        var instance = Self()\n"
        "        while reader.has_more():\n"
        "            var field_number, wire_type = reader.read_tag()\n"
        "            \n"
    )
    var first = True
    for f in desc.field:
        var fname = f.name.value() if f.name else "unknown"
        var num = String(Int(f.number.value())) if f.number else "0"
        var base = field_base_type(f, renamings, scalar_types)
        out += "            " + ("if" if first else "elif") + " field_number == " + num + ":\n"
        var is_rep = f.label and f.label.value() == Label.LABEL_REPEATED
        var me_parse = get_map_entry(map_entries, f, full)
        if me_parse:
            var e = me_parse.value()
            # Map field: read sub-message, extract key+value, insert into Dict
            out += "                var entry = reader.read_message()\n"
            out += (
                "                var map_key = " + e.key_mojo_type + "()\n" if e.key_mojo_type
                != "String" else "                var map_key = String()\n"
            )
            out += (
                "                var map_val = "
                + e.val_mojo_type
                + "()\n" if (not e.val_is_message and e.val_mojo_type != "String") else ""
            )
            if e.val_is_message:
                out += "                var map_val_opt = Optional[" + e.val_mojo_type + "](None)\n"
            elif e.val_mojo_type == "String":
                out += "                var map_val = String()\n"
            out += "                while entry.has_more():\n"
            out += "                    var kfn, kwt = entry.read_tag()\n"
            out += "                    if kfn == 1:\n"
            if e.key_is_enum:
                out += "                        map_key = " + e.key_mojo_type + "(Int(entry.read_enum()))\n"
            else:
                out += "                        map_key = entry.read_" + e.key_read_fn + "()\n"
            out += "                    elif kfn == 2:\n"
            if e.val_is_message:
                out += "                        var vsub = entry.read_message()\n"
                out += "                        map_val_opt = " + e.val_mojo_type + ".parse(vsub)\n"
            elif e.val_is_enum:
                out += "                        map_val = " + e.val_mojo_type + "(Int(entry.read_enum()))\n"
            else:
                out += "                        map_val = entry.read_" + e.val_read_fn + "()\n"
            out += "                    else:\n"
            out += "                        entry.skip_field(kwt)\n"
            if e.val_is_message:
                out += "                if map_val_opt:\n"
                out += "                    instance." + fname + "[map_key] = map_val_opt.value()\n"
            else:
                out += "                instance." + fname + "[map_key] = map_val\n"
        elif f.type and f.type.value() == Type.TYPE_MESSAGE:
            out += "                var sub = reader.read_message()\n"
            if is_rep:
                out += "                instance." + fname + ".append(" + base + ".parse(sub))\n"
            else:
                out += "                instance." + fname + " = " + base + ".parse(sub)\n"
        elif f.type and f.type.value() == Type.TYPE_ENUM:
            if is_rep:
                out += "                if wire_type.value == 2:\n"
                out += "                    var packed = reader.read_message()\n"
                out += "                    while packed.has_more():\n"
                out += "                        instance." + fname + ".append(" + base + "(Int(packed.read_enum())))\n"
                out += "                else:\n"
                out += "                    instance." + fname + ".append(" + base + "(Int(reader.read_enum())))\n"
            else:
                out += "                instance." + fname + " = " + base + "(Int(reader.read_enum()))\n"
        else:
            var fn_name = read_fns.get(f.type.value()._value if f.type else 0, "Unknown")
            if is_rep:
                if fn_name == "string" or fn_name == "bytes":
                    # strings/bytes are always LEN_DELIM, never packed
                    out += "                instance." + fname + ".append(reader.read_" + fn_name + "())\n"
                else:
                    out += "                if wire_type.value == 2:\n"
                    out += "                    var packed = reader.read_message()\n"
                    out += "                    while packed.has_more():\n"
                    out += "                        instance." + fname + ".append(packed.read_" + fn_name + "())\n"
                    out += "                else:\n"
                    out += "                    instance." + fname + ".append(reader.read_" + fn_name + "())\n"
            else:
                out += "                instance." + fname + " = reader.read_" + fn_name + "()\n"
        first = False
    out += "            else:\n                reader.skip_field(wire_type)\n        return instance^\n"

    # serialize
    out += "\n    def serialize(self, mut writer: ProtoWriter):\n"
    if len(desc.field) == 0:
        out += "        ...\n"
    else:
        out += "        var sub = ProtoWriter()\n"
        for f in desc.field:
            var fname = f.name.value() if f.name else "unknown"
            var num = String(Int(f.number.value())) if f.number else "0"
            var is_rep = f.label and f.label.value() == Label.LABEL_REPEATED
            var is_opt = f.label and f.label.value() == Label.LABEL_OPTIONAL
            var me_ser = get_map_entry(map_entries, f, full)
            if me_ser:
                var e = me_ser.value()
                out += "        for item in self." + fname + ".items():\n"
                out += "            sub = ProtoWriter()\n"
                if e.key_is_enum:
                    out += "            sub.write_int32(1, Int32(item.key._value))\n"
                else:
                    out += "            sub.write_" + e.key_read_fn + "(1, item.key)\n"
                if e.val_is_message:
                    out += "            var vsub = ProtoWriter()\n"
                    out += "            item.value.serialize(vsub)\n"
                    out += "            sub.write_message(2, vsub)\n"
                elif e.val_is_enum:
                    out += "            sub.write_int32(2, Int32(item.value._value))\n"
                else:
                    out += "            sub.write_" + e.val_read_fn + "(2, item.value)\n"
                out += "            writer.write_message(" + num + ", sub)\n"
            elif f.type and f.type.value() == Type.TYPE_MESSAGE:
                if is_rep:
                    out += "        for item in self." + fname + ":\n"
                    out += "            sub = ProtoWriter()\n"
                    out += "            item.serialize(sub)\n"
                    out += "            writer.write_message(" + num + ", sub)\n"
                elif is_opt:
                    out += "        if self." + fname + ":\n"
                    out += "            sub = ProtoWriter()\n"
                    out += "            self." + fname + ".value().serialize(sub)\n"
                    out += "            writer.write_message(" + num + ", sub)\n"
                else:  # required message
                    out += "        sub = ProtoWriter()\n"
                    out += "        self." + fname + ".serialize(sub)\n"
                    out += "        writer.write_message(" + num + ", sub)\n"
            elif f.type and f.type.value() == Type.TYPE_ENUM:
                if is_rep:
                    out += "        for item in self." + fname + ":\n"
                    out += "            writer.write_int32(" + num + ", Int32(item._value))\n"
                elif is_opt:
                    out += "        if self." + fname + ":\n"
                    out += "            writer.write_int32(" + num + ", Int32(self." + fname + ".value()._value))\n"
                else:  # required enum
                    out += "        writer.write_int32(" + num + ", Int32(self." + fname + "._value))\n"
            else:
                var fn_name = read_fns.get(f.type.value()._value if f.type else 0, "Unknown")
                if is_rep:
                    out += "        for item in self." + fname + ":\n"
                    out += "            writer.write_" + fn_name + "(" + num + ", item)\n"
                elif is_opt:
                    out += "        if self." + fname + ":\n"
                    out += "            writer.write_" + fn_name + "(" + num + ", self." + fname + ".value())\n"
                else:
                    out += "        writer.write_" + fn_name + "(" + num + ", self." + fname + ")\n"

    parts.append(apply_indent(out, indent))
    return parts^


def generate_file(proto_file: FileDescriptorProto, module_prefix: String = "") raises -> String:
    var renamings = Renamings()
    var scalar_types = make_scalar_types()
    var read_fns = make_read_fns()
    var chunks = List[String]()

    var deps = List[String]()
    for dep in proto_file.dependency:
        deps.append(dep)
    chunks.append(generate_prelude(deps, module_prefix))
    for e in proto_file.enum_type:
        chunks.append(generate_enum(e, 0))
    for m in proto_file.message_type:
        for p in generate_message(m, renamings, scalar_types, read_fns, 0, ""):
            chunks.append(p)

    var out = String()
    var first = True
    for chunk in chunks:
        if not first:
            out += "\n\n"
        out += chunk
        first = False
    return out
