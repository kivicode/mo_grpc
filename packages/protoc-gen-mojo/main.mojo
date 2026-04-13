from std.sys import stdin, stdout
from protobuf_runtime import ProtoReader, ProtoWriter
from protobuf_runtime.common import Bytes
from protoc_gen_mojo.gen.plugin import CodeGeneratorRequest, CodeGeneratorResponse, CodeGeneratorResponseFile, Feature
from protoc_gen_mojo.generator import generate_file


def read_stdin() raises -> Bytes:
    var data: Bytes
    with open("/dev/stdin", "r") as f:
        data = f.read_bytes()
    return data^


def write_stdout(data: Bytes) raises:
    var out = stdout
    out.write_bytes(data)


def replace_proto_ext(name: String) -> String:
    var b = name.as_bytes()
    var suffix = ".proto".as_bytes()
    var n = len(b)
    var s = len(suffix)
    if n < s:
        return name
    for i in range(s):
        if b[n - s + i] != suffix[i]:
            return name
    var out = List[UInt8]()
    for i in range(n - s):
        out.append(b[i])
    for c in ".mojo".as_bytes():
        out.append(c)
    return String(unsafe_from_utf8=out^)


def emit_init_files(
    mut files: List[CodeGeneratorResponseFile],
    mut emitted: List[String],
    proto_name: String,
):
    """Emit __init__.mojo for each intermediate package directory."""
    var b = proto_name.as_bytes()
    # strip .proto suffix
    var name_end = len(b) - len(".proto")
    var parts = List[String]()
    var seg = List[UInt8]()
    for i in range(name_end):
        if b[i] == ord("/"):
            parts.append(String(unsafe_from_utf8=seg^))
            seg = List[UInt8]()
        else:
            seg.append(b[i])

    # emit google/__init__.mojo, google/protobuf/__init__.mojo, etc.
    var path = String()
    for i in range(len(parts) - 1):
        if i > 0:
            path += "/"
        path += parts[i]
        var init_path = path + String("/__init__.mojo")
        var already = False
        for e in emitted:
            if e == init_path:
                already = True
                break
        if not already:
            emitted.append(init_path)
            files.append(
                CodeGeneratorResponseFile(
                    name=Optional[String](init_path),
                    insertion_point=None,
                    content=Optional[String](String()),
                    generated_code_info=None,
                )
            )


def parse_module_prefix(parameter: Optional[String]) -> String:
    """Extract module_prefix=... from plugin parameter string."""
    if not parameter:
        return String()
    var param = parameter.value()
    var key = "module_prefix="
    var kb = key.as_bytes()
    var pb = param.as_bytes()
    var klen = len(kb)
    var plen = len(pb)
    for i in range(plen - klen + 1):
        var found = True
        for j in range(klen):
            if pb[i + j] != kb[j]:
                found = False
                break
        if found:
            var val = List[UInt8]()
            var end = i + klen
            while end < plen and pb[end] != 44:  # stop at ','
                val.append(pb[end])
                end += 1
            return String(unsafe_from_utf8=val^)
    return String()


def main() raises:
    var reader = ProtoReader(read_stdin())
    var request = CodeGeneratorRequest.parse(reader)
    var module_prefix = parse_module_prefix(request.parameter)

    var files = List[CodeGeneratorResponseFile]()
    var emitted_inits = List[String]()

    for pf in request.proto_file:
        if not pf.name:
            continue
        var fname = pf.name.value()
        emit_init_files(files, emitted_inits, fname)
        files.append(
            CodeGeneratorResponseFile(
                name=Optional[String](replace_proto_ext(fname)),
                insertion_point=None,
                content=Optional[String](generate_file(pf, module_prefix)),
                generated_code_info=None,
            )
        )

    var response = CodeGeneratorResponse(
        error=None,
        supported_features=Optional[UInt64](UInt64(Feature.FEATURE_PROTO3_OPTIONAL._value)),
        minimum_edition=None,
        maximum_edition=None,
        file=files^,
    )

    var writer = ProtoWriter()
    response.serialize(writer)
    write_stdout(writer.flush())
