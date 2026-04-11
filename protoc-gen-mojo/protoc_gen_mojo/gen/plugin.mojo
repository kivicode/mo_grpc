"""
   AUTO-GENERATED CODE
   !!! DO NOT EDIT !!!
"""

from protobuf_runtime import ProtoReader, ProtoWriter, ProtoSerializable

from protoc_gen_mojo.gen.google.protobuf.descriptor import *

@fieldwise_init
struct Version(ProtoSerializable, Copyable):
    var major: Optional[Int32]
    var minor: Optional[Int32]
    var patch: Optional[Int32]
    var suffix: Optional[String]
    
    def __init__(out self):
        self.major = None
        self.minor = None
        self.patch = None
        self.suffix = None

    @staticmethod
    def parse(mut reader: ProtoReader) raises -> Self:
        var instance = Self()
        while reader.has_more():
            var field_number, wire_type = reader.read_tag()
            
            if field_number == 1:
                instance.major = reader.read_int32()
            elif field_number == 2:
                instance.minor = reader.read_int32()
            elif field_number == 3:
                instance.patch = reader.read_int32()
            elif field_number == 4:
                instance.suffix = reader.read_string()
            else:
                reader.skip_field(wire_type)
        return instance^

    def serialize(self, mut writer: ProtoWriter):
        var sub = ProtoWriter()
        if self.major:
            writer.write_int32(1, self.major.value())
        if self.minor:
            writer.write_int32(2, self.minor.value())
        if self.patch:
            writer.write_int32(3, self.patch.value())
        if self.suffix:
            writer.write_string(4, self.suffix.value())

@fieldwise_init
struct CodeGeneratorRequest(ProtoSerializable, Copyable):
    var file_to_generate: List[String]
    var parameter: Optional[String]
    var proto_file: List[FileDescriptorProto]
    var source_file_descriptors: List[FileDescriptorProto]
    var compiler_version: Optional[Version]
    
    def __init__(out self):
        self.file_to_generate = List[String]()
        self.parameter = None
        self.proto_file = List[FileDescriptorProto]()
        self.source_file_descriptors = List[FileDescriptorProto]()
        self.compiler_version = None

    @staticmethod
    def parse(mut reader: ProtoReader) raises -> Self:
        var instance = Self()
        while reader.has_more():
            var field_number, wire_type = reader.read_tag()
            
            if field_number == 1:
                instance.file_to_generate.append(reader.read_string())
            elif field_number == 2:
                instance.parameter = reader.read_string()
            elif field_number == 15:
                var sub = reader.read_message()
                instance.proto_file.append(FileDescriptorProto.parse(sub))
            elif field_number == 17:
                var sub = reader.read_message()
                instance.source_file_descriptors.append(FileDescriptorProto.parse(sub))
            elif field_number == 3:
                var sub = reader.read_message()
                instance.compiler_version = Version.parse(sub)
            else:
                reader.skip_field(wire_type)
        return instance^

    def serialize(self, mut writer: ProtoWriter):
        var sub = ProtoWriter()
        for item in self.file_to_generate:
            writer.write_string(1, item)
        if self.parameter:
            writer.write_string(2, self.parameter.value())
        for item in self.proto_file:
            sub = ProtoWriter()
            item.serialize(sub)
            writer.write_message(15, sub)
        for item in self.source_file_descriptors:
            sub = ProtoWriter()
            item.serialize(sub)
            writer.write_message(17, sub)
        if self.compiler_version:
            sub = ProtoWriter()
            self.compiler_version.value().serialize(sub)
            writer.write_message(3, sub)

@fieldwise_init
struct CodeGeneratorResponseFile(ProtoSerializable, Copyable):
    var name: Optional[String]
    var insertion_point: Optional[String]
    var content: Optional[String]
    var generated_code_info: Optional[GeneratedCodeInfo]
    
    def __init__(out self):
        self.name = None
        self.insertion_point = None
        self.content = None
        self.generated_code_info = None

    @staticmethod
    def parse(mut reader: ProtoReader) raises -> Self:
        var instance = Self()
        while reader.has_more():
            var field_number, wire_type = reader.read_tag()
            
            if field_number == 1:
                instance.name = reader.read_string()
            elif field_number == 2:
                instance.insertion_point = reader.read_string()
            elif field_number == 15:
                instance.content = reader.read_string()
            elif field_number == 16:
                var sub = reader.read_message()
                instance.generated_code_info = GeneratedCodeInfo.parse(sub)
            else:
                reader.skip_field(wire_type)
        return instance^

    def serialize(self, mut writer: ProtoWriter):
        var sub = ProtoWriter()
        if self.name:
            writer.write_string(1, self.name.value())
        if self.insertion_point:
            writer.write_string(2, self.insertion_point.value())
        if self.content:
            writer.write_string(15, self.content.value())
        if self.generated_code_info:
            sub = ProtoWriter()
            self.generated_code_info.value().serialize(sub)
            writer.write_message(16, sub)

@fieldwise_init
struct Feature(ProtoSerializable, Equatable, ImplicitlyCopyable):
    var _value: Int
    
    comptime FEATURE_NONE = Feature(0)
    comptime FEATURE_PROTO3_OPTIONAL = Feature(1)
    comptime FEATURE_SUPPORTS_EDITIONS = Feature(2)

    @staticmethod
    def parse(mut reader: ProtoReader) raises -> Self:
        return Self(Int(reader.read_enum()))

    def serialize(self, mut writer: ProtoWriter):
        writer.write_varint(UInt64(self._value))

    def __eq__(self, other: Self) -> Bool:
        return self._value == other._value

    def __ne__(self, other: Self) -> Bool:
        return not (self == other)

@fieldwise_init
struct CodeGeneratorResponse(ProtoSerializable, Copyable):
    var error: Optional[String]
    var supported_features: Optional[UInt64]
    var minimum_edition: Optional[Int32]
    var maximum_edition: Optional[Int32]
    var file: List[CodeGeneratorResponseFile]
    
    def __init__(out self):
        self.error = None
        self.supported_features = None
        self.minimum_edition = None
        self.maximum_edition = None
        self.file = List[CodeGeneratorResponseFile]()

    @staticmethod
    def parse(mut reader: ProtoReader) raises -> Self:
        var instance = Self()
        while reader.has_more():
            var field_number, wire_type = reader.read_tag()
            
            if field_number == 1:
                instance.error = reader.read_string()
            elif field_number == 2:
                instance.supported_features = reader.read_uint64()
            elif field_number == 3:
                instance.minimum_edition = reader.read_int32()
            elif field_number == 4:
                instance.maximum_edition = reader.read_int32()
            elif field_number == 15:
                var sub = reader.read_message()
                instance.file.append(CodeGeneratorResponseFile.parse(sub))
            else:
                reader.skip_field(wire_type)
        return instance^

    def serialize(self, mut writer: ProtoWriter):
        var sub = ProtoWriter()
        if self.error:
            writer.write_string(1, self.error.value())
        if self.supported_features:
            writer.write_uint64(2, self.supported_features.value())
        if self.minimum_edition:
            writer.write_int32(3, self.minimum_edition.value())
        if self.maximum_edition:
            writer.write_int32(4, self.maximum_edition.value())
        for item in self.file:
            sub = ProtoWriter()
            item.serialize(sub)
            writer.write_message(15, sub)