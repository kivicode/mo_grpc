from collections import Dict
from protoc_gen_mojo.gen.google.protobuf.descriptor import (
    FileDescriptorProto,
    DescriptorProto,
    EnumDescriptorProto,
    FieldDescriptorProto,
    Type,
    Label,
)

comptime Renamings = Dict[String, String]


# ── type maps (built once in generate_file) ────────────────────────────────────

def make_scalar_types() -> Dict[Int, String]:
    var d = Dict[Int, String]()
    d[Type.TYPE_DOUBLE._value] = "Float64"
    d[Type.TYPE_FLOAT._value]  = "Float32"
    d[Type.TYPE_INT64._value]  = "Int64"
    d[Type.TYPE_UINT64._value] = "UInt64"
    d[Type.TYPE_INT32._value]  = "Int32"
    d[Type.TYPE_UINT32._value] = "UInt32"
    d[Type.TYPE_BOOL._value]   = "Bool"
    d[Type.TYPE_STRING._value] = "String"
    d[Type.TYPE_BYTES._value]  = "List[UInt8]"
    return d^


def make_read_fns() -> Dict[Int, String]:
    var d = Dict[Int, String]()
    d[Type.TYPE_DOUBLE._value] = "double"
    d[Type.TYPE_FLOAT._value]  = "float"
    d[Type.TYPE_INT64._value]  = "int64"
    d[Type.TYPE_UINT64._value] = "uint64"
    d[Type.TYPE_INT32._value]  = "int32"
    d[Type.TYPE_UINT32._value] = "uint32"
    d[Type.TYPE_BOOL._value]   = "bool"
    d[Type.TYPE_STRING._value] = "string"
    d[Type.TYPE_BYTES._value]  = "bytes"
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
    if lbl == Label.LABEL_REPEATED: return "List[" + base + "]"
    if lbl == Label.LABEL_OPTIONAL: return "Optional[" + base + "]"
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


def generate_prelude(deps: List[String], module_prefix: String = "") -> String:
    var out = (
        '"""\n'
        '   AUTO-GENERATED CODE\n'
        '   !!! DO NOT EDIT !!!\n'
        '"""\n\n'
        'from protobuf_runtime import ProtoReader, ProtoWriter, ProtoSerializable\n'
    )
    for dep in deps:
        out += "from " + proto_path_to_module(dep, module_prefix) + " import *\n"
    return out


def generate_enum(desc: EnumDescriptorProto, indent: Int = 0) -> String:
    var name = desc.name.value() if desc.name else "Unknown"

    var out = "@fieldwise_init\nstruct " + name + "(ProtoSerializable, Equatable, ImplicitlyCopyable):\n"
    out += "    var _value: Int\n"
    for opt in desc.value:
        var oname = opt.name.value()                if opt.name   else "UNKNOWN"
        var oval  = String(Int(opt.number.value())) if opt.number else "0"
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
) -> List[String]:
    var name = desc.name.value() if desc.name else "Unknown"
    var full = prefix + name
    renamings[name] = full

    var parts = List[String]()
    for inner in desc.nested_type:
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
            out += "    var " + fname + ": " + field_full_type(f, renamings, scalar_types) + "\n"

    # __init__ with defaults (needed for Self() in parse)
    if len(desc.field) > 0:
        out += "\n    def __init__(out self):\n"
        for f in desc.field:
            var fname = f.name.value() if f.name else "unknown"
            var is_rep = f.label and f.label.value() == Label.LABEL_REPEATED
            var is_opt = f.label and f.label.value() == Label.LABEL_OPTIONAL
            if is_rep:
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
        var num   = String(Int(f.number.value())) if f.number else "0"
        var base  = field_base_type(f, renamings, scalar_types)
        out += "            " + ("if" if first else "elif") + " field_number == " + num + ":\n"
        var is_rep = f.label and f.label.value() == Label.LABEL_REPEATED
        if f.type and f.type.value() == Type.TYPE_MESSAGE:
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
    out += (
        "            else:\n"
        "                reader.skip_field(wire_type)\n"
        "        return instance^\n"
    )

    # serialize
    out += "\n    def serialize(self, mut writer: ProtoWriter):\n"
    if len(desc.field) == 0:
        out += "        ...\n"
    else:
        out += "        var sub = ProtoWriter()\n"
        for f in desc.field:
            var fname = f.name.value() if f.name else "unknown"
            var num   = String(Int(f.number.value())) if f.number else "0"
            var is_rep = f.label and f.label.value() == Label.LABEL_REPEATED
            var is_opt = f.label and f.label.value() == Label.LABEL_OPTIONAL
            if f.type and f.type.value() == Type.TYPE_MESSAGE:
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


def generate_file(proto_file: FileDescriptorProto, module_prefix: String = "") -> String:
    var renamings    = Renamings()
    var scalar_types = make_scalar_types()
    var read_fns     = make_read_fns()
    var chunks       = List[String]()

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
