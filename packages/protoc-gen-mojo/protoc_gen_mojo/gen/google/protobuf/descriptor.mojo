"""
   AUTO-GENERATED CODE
   !!! DO NOT EDIT !!!
"""

from mo_protobuf import ProtoReader, ProtoWriter, ProtoSerializable


@fieldwise_init
struct Edition(Equatable, ImplicitlyCopyable, ProtoSerializable):
    var _value: Int

    comptime EDITION_UNKNOWN = Edition(0)

    comptime EDITION_LEGACY = Edition(900)

    comptime EDITION_PROTO2 = Edition(998)

    comptime EDITION_PROTO3 = Edition(999)

    comptime EDITION_2023 = Edition(1000)

    comptime EDITION_2024 = Edition(1001)

    comptime EDITION_1_TEST_ONLY = Edition(1)

    comptime EDITION_2_TEST_ONLY = Edition(2)

    comptime EDITION_99997_TEST_ONLY = Edition(99997)

    comptime EDITION_99998_TEST_ONLY = Edition(99998)

    comptime EDITION_99999_TEST_ONLY = Edition(99999)

    comptime EDITION_MAX = Edition(2147483647)

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
struct FileDescriptorSet(Copyable, ProtoSerializable):
    var file: List[FileDescriptorProto]

    def __init__(out self):
        self.file = List[FileDescriptorProto]()

    @staticmethod
    def parse(mut reader: ProtoReader) raises -> Self:
        var instance = Self()
        while reader.has_more():
            var field_number, wire_type = reader.read_tag()

            if field_number == 1:
                var sub = reader.read_message()
                instance.file.append(FileDescriptorProto.parse(sub))
            else:
                reader.skip_field(wire_type)
        return instance^

    def serialize(self, mut writer: ProtoWriter):
        var sub = ProtoWriter()
        for item in self.file:
            sub = ProtoWriter()
            item.serialize(sub)
            writer.write_message(1, sub)


@fieldwise_init
struct FileDescriptorProto(Copyable, ProtoSerializable):
    var name: Optional[String]
    var package: Optional[String]
    var dependency: List[String]
    var public_dependency: List[Int32]
    var weak_dependency: List[Int32]
    var message_type: List[DescriptorProto]
    var enum_type: List[EnumDescriptorProto]
    var service: List[ServiceDescriptorProto]
    var extension: List[FieldDescriptorProto]
    var options: Optional[FileOptions]
    var source_code_info: Optional[SourceCodeInfo]
    var syntax: Optional[String]
    var edition: Optional[Edition]

    def __init__(out self):
        self.name = None
        self.package = None
        self.dependency = List[String]()
        self.public_dependency = List[Int32]()
        self.weak_dependency = List[Int32]()
        self.message_type = List[DescriptorProto]()
        self.enum_type = List[EnumDescriptorProto]()
        self.service = List[ServiceDescriptorProto]()
        self.extension = List[FieldDescriptorProto]()
        self.options = None
        self.source_code_info = None
        self.syntax = None
        self.edition = None

    @staticmethod
    def parse(mut reader: ProtoReader) raises -> Self:
        var instance = Self()
        while reader.has_more():
            var field_number, wire_type = reader.read_tag()

            if field_number == 1:
                instance.name = reader.read_string()
            elif field_number == 2:
                instance.package = reader.read_string()
            elif field_number == 3:
                instance.dependency.append(reader.read_string())
            elif field_number == 10:
                if wire_type.value == 2:
                    var packed = reader.read_message()
                    while packed.has_more():
                        instance.public_dependency.append(packed.read_int32())
                else:
                    instance.public_dependency.append(reader.read_int32())
            elif field_number == 11:
                if wire_type.value == 2:
                    var packed = reader.read_message()
                    while packed.has_more():
                        instance.weak_dependency.append(packed.read_int32())
                else:
                    instance.weak_dependency.append(reader.read_int32())
            elif field_number == 4:
                var sub = reader.read_message()
                instance.message_type.append(DescriptorProto.parse(sub))
            elif field_number == 5:
                var sub = reader.read_message()
                instance.enum_type.append(EnumDescriptorProto.parse(sub))
            elif field_number == 6:
                var sub = reader.read_message()
                instance.service.append(ServiceDescriptorProto.parse(sub))
            elif field_number == 7:
                var sub = reader.read_message()
                instance.extension.append(FieldDescriptorProto.parse(sub))
            elif field_number == 8:
                var sub = reader.read_message()
                instance.options = FileOptions.parse(sub)
            elif field_number == 9:
                var sub = reader.read_message()
                instance.source_code_info = SourceCodeInfo.parse(sub)
            elif field_number == 12:
                instance.syntax = reader.read_string()
            elif field_number == 14:
                instance.edition = Edition(Int(reader.read_enum()))
            else:
                reader.skip_field(wire_type)
        return instance^

    def serialize(self, mut writer: ProtoWriter):
        var sub = ProtoWriter()
        if self.name:
            writer.write_string(1, self.name.value())
        if self.package:
            writer.write_string(2, self.package.value())
        for item in self.dependency:
            writer.write_string(3, item)
        for item in self.public_dependency:
            writer.write_int32(10, item)
        for item in self.weak_dependency:
            writer.write_int32(11, item)
        for item in self.message_type:
            sub = ProtoWriter()
            item.serialize(sub)
            writer.write_message(4, sub)
        for item in self.enum_type:
            sub = ProtoWriter()
            item.serialize(sub)
            writer.write_message(5, sub)
        for item in self.service:
            sub = ProtoWriter()
            item.serialize(sub)
            writer.write_message(6, sub)
        for item in self.extension:
            sub = ProtoWriter()
            item.serialize(sub)
            writer.write_message(7, sub)
        if self.options:
            sub = ProtoWriter()
            self.options.value().serialize(sub)
            writer.write_message(8, sub)
        if self.source_code_info:
            sub = ProtoWriter()
            self.source_code_info.value().serialize(sub)
            writer.write_message(9, sub)
        if self.syntax:
            writer.write_string(12, self.syntax.value())
        if self.edition:
            writer.write_int32(14, Int32(self.edition.value()._value))


@fieldwise_init
struct DescriptorProtoExtensionRange(Copyable, ProtoSerializable):
    var start: Optional[Int32]
    var end: Optional[Int32]
    var options: Optional[ExtensionRangeOptions]

    def __init__(out self):
        self.start = None
        self.end = None
        self.options = None

    @staticmethod
    def parse(mut reader: ProtoReader) raises -> Self:
        var instance = Self()
        while reader.has_more():
            var field_number, wire_type = reader.read_tag()

            if field_number == 1:
                instance.start = reader.read_int32()
            elif field_number == 2:
                instance.end = reader.read_int32()
            elif field_number == 3:
                var sub = reader.read_message()
                instance.options = ExtensionRangeOptions.parse(sub)
            else:
                reader.skip_field(wire_type)
        return instance^

    def serialize(self, mut writer: ProtoWriter):
        var sub = ProtoWriter()
        if self.start:
            writer.write_int32(1, self.start.value())
        if self.end:
            writer.write_int32(2, self.end.value())
        if self.options:
            sub = ProtoWriter()
            self.options.value().serialize(sub)
            writer.write_message(3, sub)


@fieldwise_init
struct DescriptorProtoReservedRange(Copyable, ProtoSerializable):
    var start: Optional[Int32]
    var end: Optional[Int32]

    def __init__(out self):
        self.start = None
        self.end = None

    @staticmethod
    def parse(mut reader: ProtoReader) raises -> Self:
        var instance = Self()
        while reader.has_more():
            var field_number, wire_type = reader.read_tag()

            if field_number == 1:
                instance.start = reader.read_int32()
            elif field_number == 2:
                instance.end = reader.read_int32()
            else:
                reader.skip_field(wire_type)
        return instance^

    def serialize(self, mut writer: ProtoWriter):
        var sub = ProtoWriter()
        if self.start:
            writer.write_int32(1, self.start.value())
        if self.end:
            writer.write_int32(2, self.end.value())


@fieldwise_init
struct DescriptorProto(Copyable, ProtoSerializable):
    var name: Optional[String]
    var field: List[FieldDescriptorProto]
    var extension: List[FieldDescriptorProto]
    var nested_type: List[DescriptorProto]
    var enum_type: List[EnumDescriptorProto]
    var extension_range: List[DescriptorProtoExtensionRange]
    var oneof_decl: List[OneofDescriptorProto]
    var options: Optional[MessageOptions]
    var reserved_range: List[DescriptorProtoReservedRange]
    var reserved_name: List[String]

    def __init__(out self):
        self.name = None
        self.field = List[FieldDescriptorProto]()
        self.extension = List[FieldDescriptorProto]()
        self.nested_type = List[DescriptorProto]()
        self.enum_type = List[EnumDescriptorProto]()
        self.extension_range = List[DescriptorProtoExtensionRange]()
        self.oneof_decl = List[OneofDescriptorProto]()
        self.options = None
        self.reserved_range = List[DescriptorProtoReservedRange]()
        self.reserved_name = List[String]()

    @staticmethod
    def parse(mut reader: ProtoReader) raises -> Self:
        var instance = Self()
        while reader.has_more():
            var field_number, wire_type = reader.read_tag()

            if field_number == 1:
                instance.name = reader.read_string()
            elif field_number == 2:
                var sub = reader.read_message()
                instance.field.append(FieldDescriptorProto.parse(sub))
            elif field_number == 6:
                var sub = reader.read_message()
                instance.extension.append(FieldDescriptorProto.parse(sub))
            elif field_number == 3:
                var sub = reader.read_message()
                instance.nested_type.append(DescriptorProto.parse(sub))
            elif field_number == 4:
                var sub = reader.read_message()
                instance.enum_type.append(EnumDescriptorProto.parse(sub))
            elif field_number == 5:
                var sub = reader.read_message()
                instance.extension_range.append(DescriptorProtoExtensionRange.parse(sub))
            elif field_number == 8:
                var sub = reader.read_message()
                instance.oneof_decl.append(OneofDescriptorProto.parse(sub))
            elif field_number == 7:
                var sub = reader.read_message()
                instance.options = MessageOptions.parse(sub)
            elif field_number == 9:
                var sub = reader.read_message()
                instance.reserved_range.append(DescriptorProtoReservedRange.parse(sub))
            elif field_number == 10:
                instance.reserved_name.append(reader.read_string())
            else:
                reader.skip_field(wire_type)
        return instance^

    def serialize(self, mut writer: ProtoWriter):
        var sub = ProtoWriter()
        if self.name:
            writer.write_string(1, self.name.value())
        for item in self.field:
            sub = ProtoWriter()
            item.serialize(sub)
            writer.write_message(2, sub)
        for item in self.extension:
            sub = ProtoWriter()
            item.serialize(sub)
            writer.write_message(6, sub)
        for item in self.nested_type:
            sub = ProtoWriter()
            item.serialize(sub)
            writer.write_message(3, sub)
        for item in self.enum_type:
            sub = ProtoWriter()
            item.serialize(sub)
            writer.write_message(4, sub)
        for item in self.extension_range:
            sub = ProtoWriter()
            item.serialize(sub)
            writer.write_message(5, sub)
        for item in self.oneof_decl:
            sub = ProtoWriter()
            item.serialize(sub)
            writer.write_message(8, sub)
        if self.options:
            sub = ProtoWriter()
            self.options.value().serialize(sub)
            writer.write_message(7, sub)
        for item in self.reserved_range:
            sub = ProtoWriter()
            item.serialize(sub)
            writer.write_message(9, sub)
        for item in self.reserved_name:
            writer.write_string(10, item)


@fieldwise_init
struct ExtensionRangeOptionsDeclaration(Copyable, ProtoSerializable):
    var number: Optional[Int32]
    var full_name: Optional[String]
    var type: Optional[String]
    var reserved: Optional[Bool]
    var repeated: Optional[Bool]

    def __init__(out self):
        self.number = None
        self.full_name = None
        self.type = None
        self.reserved = None
        self.repeated = None

    @staticmethod
    def parse(mut reader: ProtoReader) raises -> Self:
        var instance = Self()
        while reader.has_more():
            var field_number, wire_type = reader.read_tag()

            if field_number == 1:
                instance.number = reader.read_int32()
            elif field_number == 2:
                instance.full_name = reader.read_string()
            elif field_number == 3:
                instance.type = reader.read_string()
            elif field_number == 5:
                instance.reserved = reader.read_bool()
            elif field_number == 6:
                instance.repeated = reader.read_bool()
            else:
                reader.skip_field(wire_type)
        return instance^

    def serialize(self, mut writer: ProtoWriter):
        var sub = ProtoWriter()
        if self.number:
            writer.write_int32(1, self.number.value())
        if self.full_name:
            writer.write_string(2, self.full_name.value())
        if self.type:
            writer.write_string(3, self.type.value())
        if self.reserved:
            writer.write_bool(5, self.reserved.value())
        if self.repeated:
            writer.write_bool(6, self.repeated.value())


@fieldwise_init
struct VerificationState(Equatable, ImplicitlyCopyable, ProtoSerializable):
    var _value: Int

    comptime DECLARATION = VerificationState(0)

    comptime UNVERIFIED = VerificationState(1)

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
struct ExtensionRangeOptions(Copyable, ProtoSerializable):
    var uninterpreted_option: List[UninterpretedOption]
    var declaration: List[ExtensionRangeOptionsDeclaration]
    var features: Optional[FeatureSet]
    var verification: Optional[VerificationState]

    def __init__(out self):
        self.uninterpreted_option = List[UninterpretedOption]()
        self.declaration = List[ExtensionRangeOptionsDeclaration]()
        self.features = None
        self.verification = None

    @staticmethod
    def parse(mut reader: ProtoReader) raises -> Self:
        var instance = Self()
        while reader.has_more():
            var field_number, wire_type = reader.read_tag()

            if field_number == 999:
                var sub = reader.read_message()
                instance.uninterpreted_option.append(UninterpretedOption.parse(sub))
            elif field_number == 2:
                var sub = reader.read_message()
                instance.declaration.append(ExtensionRangeOptionsDeclaration.parse(sub))
            elif field_number == 50:
                var sub = reader.read_message()
                instance.features = FeatureSet.parse(sub)
            elif field_number == 3:
                instance.verification = VerificationState(Int(reader.read_enum()))
            else:
                reader.skip_field(wire_type)
        return instance^

    def serialize(self, mut writer: ProtoWriter):
        var sub = ProtoWriter()
        for item in self.uninterpreted_option:
            sub = ProtoWriter()
            item.serialize(sub)
            writer.write_message(999, sub)
        for item in self.declaration:
            sub = ProtoWriter()
            item.serialize(sub)
            writer.write_message(2, sub)
        if self.features:
            sub = ProtoWriter()
            self.features.value().serialize(sub)
            writer.write_message(50, sub)
        if self.verification:
            writer.write_int32(3, Int32(self.verification.value()._value))


@fieldwise_init
struct Type(Equatable, ImplicitlyCopyable, ProtoSerializable):
    var _value: Int

    comptime TYPE_DOUBLE = Type(1)

    comptime TYPE_FLOAT = Type(2)

    comptime TYPE_INT64 = Type(3)

    comptime TYPE_UINT64 = Type(4)

    comptime TYPE_INT32 = Type(5)

    comptime TYPE_FIXED64 = Type(6)

    comptime TYPE_FIXED32 = Type(7)

    comptime TYPE_BOOL = Type(8)

    comptime TYPE_STRING = Type(9)

    comptime TYPE_GROUP = Type(10)

    comptime TYPE_MESSAGE = Type(11)

    comptime TYPE_BYTES = Type(12)

    comptime TYPE_UINT32 = Type(13)

    comptime TYPE_ENUM = Type(14)

    comptime TYPE_SFIXED32 = Type(15)

    comptime TYPE_SFIXED64 = Type(16)

    comptime TYPE_SINT32 = Type(17)

    comptime TYPE_SINT64 = Type(18)

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
struct Label(Equatable, ImplicitlyCopyable, ProtoSerializable):
    var _value: Int

    comptime LABEL_OPTIONAL = Label(1)

    comptime LABEL_REPEATED = Label(3)

    comptime LABEL_REQUIRED = Label(2)

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
struct FieldDescriptorProto(Copyable, ProtoSerializable):
    var name: Optional[String]
    var number: Optional[Int32]
    var label: Optional[Label]
    var type: Optional[Type]
    var type_name: Optional[String]
    var extendee: Optional[String]
    var default_value: Optional[String]
    var oneof_index: Optional[Int32]
    var json_name: Optional[String]
    var options: Optional[FieldOptions]
    var proto3_optional: Optional[Bool]

    def __init__(out self):
        self.name = None
        self.number = None
        self.label = None
        self.type = None
        self.type_name = None
        self.extendee = None
        self.default_value = None
        self.oneof_index = None
        self.json_name = None
        self.options = None
        self.proto3_optional = None

    @staticmethod
    def parse(mut reader: ProtoReader) raises -> Self:
        var instance = Self()
        while reader.has_more():
            var field_number, wire_type = reader.read_tag()

            if field_number == 1:
                instance.name = reader.read_string()
            elif field_number == 3:
                instance.number = reader.read_int32()
            elif field_number == 4:
                instance.label = Label(Int(reader.read_enum()))
            elif field_number == 5:
                instance.type = Type(Int(reader.read_enum()))
            elif field_number == 6:
                instance.type_name = reader.read_string()
            elif field_number == 2:
                instance.extendee = reader.read_string()
            elif field_number == 7:
                instance.default_value = reader.read_string()
            elif field_number == 9:
                instance.oneof_index = reader.read_int32()
            elif field_number == 10:
                instance.json_name = reader.read_string()
            elif field_number == 8:
                var sub = reader.read_message()
                instance.options = FieldOptions.parse(sub)
            elif field_number == 17:
                instance.proto3_optional = reader.read_bool()
            else:
                reader.skip_field(wire_type)
        return instance^

    def serialize(self, mut writer: ProtoWriter):
        var sub = ProtoWriter()
        if self.name:
            writer.write_string(1, self.name.value())
        if self.number:
            writer.write_int32(3, self.number.value())
        if self.label:
            writer.write_int32(4, Int32(self.label.value()._value))
        if self.type:
            writer.write_int32(5, Int32(self.type.value()._value))
        if self.type_name:
            writer.write_string(6, self.type_name.value())
        if self.extendee:
            writer.write_string(2, self.extendee.value())
        if self.default_value:
            writer.write_string(7, self.default_value.value())
        if self.oneof_index:
            writer.write_int32(9, self.oneof_index.value())
        if self.json_name:
            writer.write_string(10, self.json_name.value())
        if self.options:
            sub = ProtoWriter()
            self.options.value().serialize(sub)
            writer.write_message(8, sub)
        if self.proto3_optional:
            writer.write_bool(17, self.proto3_optional.value())


@fieldwise_init
struct OneofDescriptorProto(Copyable, ProtoSerializable):
    var name: Optional[String]
    var options: Optional[OneofOptions]

    def __init__(out self):
        self.name = None
        self.options = None

    @staticmethod
    def parse(mut reader: ProtoReader) raises -> Self:
        var instance = Self()
        while reader.has_more():
            var field_number, wire_type = reader.read_tag()

            if field_number == 1:
                instance.name = reader.read_string()
            elif field_number == 2:
                var sub = reader.read_message()
                instance.options = OneofOptions.parse(sub)
            else:
                reader.skip_field(wire_type)
        return instance^

    def serialize(self, mut writer: ProtoWriter):
        var sub = ProtoWriter()
        if self.name:
            writer.write_string(1, self.name.value())
        if self.options:
            sub = ProtoWriter()
            self.options.value().serialize(sub)
            writer.write_message(2, sub)


@fieldwise_init
struct EnumDescriptorProtoEnumReservedRange(Copyable, ProtoSerializable):
    var start: Optional[Int32]
    var end: Optional[Int32]

    def __init__(out self):
        self.start = None
        self.end = None

    @staticmethod
    def parse(mut reader: ProtoReader) raises -> Self:
        var instance = Self()
        while reader.has_more():
            var field_number, wire_type = reader.read_tag()

            if field_number == 1:
                instance.start = reader.read_int32()
            elif field_number == 2:
                instance.end = reader.read_int32()
            else:
                reader.skip_field(wire_type)
        return instance^

    def serialize(self, mut writer: ProtoWriter):
        var sub = ProtoWriter()
        if self.start:
            writer.write_int32(1, self.start.value())
        if self.end:
            writer.write_int32(2, self.end.value())


@fieldwise_init
struct EnumDescriptorProto(Copyable, ProtoSerializable):
    var name: Optional[String]
    var value: List[EnumValueDescriptorProto]
    var options: Optional[EnumOptions]
    var reserved_range: List[EnumDescriptorProtoEnumReservedRange]
    var reserved_name: List[String]

    def __init__(out self):
        self.name = None
        self.value = List[EnumValueDescriptorProto]()
        self.options = None
        self.reserved_range = List[EnumDescriptorProtoEnumReservedRange]()
        self.reserved_name = List[String]()

    @staticmethod
    def parse(mut reader: ProtoReader) raises -> Self:
        var instance = Self()
        while reader.has_more():
            var field_number, wire_type = reader.read_tag()

            if field_number == 1:
                instance.name = reader.read_string()
            elif field_number == 2:
                var sub = reader.read_message()
                instance.value.append(EnumValueDescriptorProto.parse(sub))
            elif field_number == 3:
                var sub = reader.read_message()
                instance.options = EnumOptions.parse(sub)
            elif field_number == 4:
                var sub = reader.read_message()
                instance.reserved_range.append(EnumDescriptorProtoEnumReservedRange.parse(sub))
            elif field_number == 5:
                instance.reserved_name.append(reader.read_string())
            else:
                reader.skip_field(wire_type)
        return instance^

    def serialize(self, mut writer: ProtoWriter):
        var sub = ProtoWriter()
        if self.name:
            writer.write_string(1, self.name.value())
        for item in self.value:
            sub = ProtoWriter()
            item.serialize(sub)
            writer.write_message(2, sub)
        if self.options:
            sub = ProtoWriter()
            self.options.value().serialize(sub)
            writer.write_message(3, sub)
        for item in self.reserved_range:
            sub = ProtoWriter()
            item.serialize(sub)
            writer.write_message(4, sub)
        for item in self.reserved_name:
            writer.write_string(5, item)


@fieldwise_init
struct EnumValueDescriptorProto(Copyable, ProtoSerializable):
    var name: Optional[String]
    var number: Optional[Int32]
    var options: Optional[EnumValueOptions]

    def __init__(out self):
        self.name = None
        self.number = None
        self.options = None

    @staticmethod
    def parse(mut reader: ProtoReader) raises -> Self:
        var instance = Self()
        while reader.has_more():
            var field_number, wire_type = reader.read_tag()

            if field_number == 1:
                instance.name = reader.read_string()
            elif field_number == 2:
                instance.number = reader.read_int32()
            elif field_number == 3:
                var sub = reader.read_message()
                instance.options = EnumValueOptions.parse(sub)
            else:
                reader.skip_field(wire_type)
        return instance^

    def serialize(self, mut writer: ProtoWriter):
        var sub = ProtoWriter()
        if self.name:
            writer.write_string(1, self.name.value())
        if self.number:
            writer.write_int32(2, self.number.value())
        if self.options:
            sub = ProtoWriter()
            self.options.value().serialize(sub)
            writer.write_message(3, sub)


@fieldwise_init
struct ServiceDescriptorProto(Copyable, ProtoSerializable):
    var name: Optional[String]
    var method: List[MethodDescriptorProto]
    var options: Optional[ServiceOptions]

    def __init__(out self):
        self.name = None
        self.method = List[MethodDescriptorProto]()
        self.options = None

    @staticmethod
    def parse(mut reader: ProtoReader) raises -> Self:
        var instance = Self()
        while reader.has_more():
            var field_number, wire_type = reader.read_tag()

            if field_number == 1:
                instance.name = reader.read_string()
            elif field_number == 2:
                var sub = reader.read_message()
                instance.method.append(MethodDescriptorProto.parse(sub))
            elif field_number == 3:
                var sub = reader.read_message()
                instance.options = ServiceOptions.parse(sub)
            else:
                reader.skip_field(wire_type)
        return instance^

    def serialize(self, mut writer: ProtoWriter):
        var sub = ProtoWriter()
        if self.name:
            writer.write_string(1, self.name.value())
        for item in self.method:
            sub = ProtoWriter()
            item.serialize(sub)
            writer.write_message(2, sub)
        if self.options:
            sub = ProtoWriter()
            self.options.value().serialize(sub)
            writer.write_message(3, sub)


@fieldwise_init
struct MethodDescriptorProto(Copyable, ProtoSerializable):
    var name: Optional[String]
    var input_type: Optional[String]
    var output_type: Optional[String]
    var options: Optional[MethodOptions]
    var client_streaming: Optional[Bool]
    var server_streaming: Optional[Bool]

    def __init__(out self):
        self.name = None
        self.input_type = None
        self.output_type = None
        self.options = None
        self.client_streaming = None
        self.server_streaming = None

    @staticmethod
    def parse(mut reader: ProtoReader) raises -> Self:
        var instance = Self()
        while reader.has_more():
            var field_number, wire_type = reader.read_tag()

            if field_number == 1:
                instance.name = reader.read_string()
            elif field_number == 2:
                instance.input_type = reader.read_string()
            elif field_number == 3:
                instance.output_type = reader.read_string()
            elif field_number == 4:
                var sub = reader.read_message()
                instance.options = MethodOptions.parse(sub)
            elif field_number == 5:
                instance.client_streaming = reader.read_bool()
            elif field_number == 6:
                instance.server_streaming = reader.read_bool()
            else:
                reader.skip_field(wire_type)
        return instance^

    def serialize(self, mut writer: ProtoWriter):
        var sub = ProtoWriter()
        if self.name:
            writer.write_string(1, self.name.value())
        if self.input_type:
            writer.write_string(2, self.input_type.value())
        if self.output_type:
            writer.write_string(3, self.output_type.value())
        if self.options:
            sub = ProtoWriter()
            self.options.value().serialize(sub)
            writer.write_message(4, sub)
        if self.client_streaming:
            writer.write_bool(5, self.client_streaming.value())
        if self.server_streaming:
            writer.write_bool(6, self.server_streaming.value())


@fieldwise_init
struct OptimizeMode(Equatable, ImplicitlyCopyable, ProtoSerializable):
    var _value: Int

    comptime SPEED = OptimizeMode(1)

    comptime CODE_SIZE = OptimizeMode(2)

    comptime LITE_RUNTIME = OptimizeMode(3)

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
struct FileOptions(Copyable, ProtoSerializable):
    var java_package: Optional[String]
    var java_outer_classname: Optional[String]
    var java_multiple_files: Optional[Bool]
    var java_generate_equals_and_hash: Optional[Bool]
    var java_string_check_utf8: Optional[Bool]
    var optimize_for: Optional[OptimizeMode]
    var go_package: Optional[String]
    var cc_generic_services: Optional[Bool]
    var java_generic_services: Optional[Bool]
    var py_generic_services: Optional[Bool]
    var deprecated: Optional[Bool]
    var cc_enable_arenas: Optional[Bool]
    var objc_class_prefix: Optional[String]
    var csharp_namespace: Optional[String]
    var swift_prefix: Optional[String]
    var php_class_prefix: Optional[String]
    var php_namespace: Optional[String]
    var php_metadata_namespace: Optional[String]
    var ruby_package: Optional[String]
    var features: Optional[FeatureSet]
    var uninterpreted_option: List[UninterpretedOption]

    def __init__(out self):
        self.java_package = None
        self.java_outer_classname = None
        self.java_multiple_files = None
        self.java_generate_equals_and_hash = None
        self.java_string_check_utf8 = None
        self.optimize_for = None
        self.go_package = None
        self.cc_generic_services = None
        self.java_generic_services = None
        self.py_generic_services = None
        self.deprecated = None
        self.cc_enable_arenas = None
        self.objc_class_prefix = None
        self.csharp_namespace = None
        self.swift_prefix = None
        self.php_class_prefix = None
        self.php_namespace = None
        self.php_metadata_namespace = None
        self.ruby_package = None
        self.features = None
        self.uninterpreted_option = List[UninterpretedOption]()

    @staticmethod
    def parse(mut reader: ProtoReader) raises -> Self:
        var instance = Self()
        while reader.has_more():
            var field_number, wire_type = reader.read_tag()

            if field_number == 1:
                instance.java_package = reader.read_string()
            elif field_number == 8:
                instance.java_outer_classname = reader.read_string()
            elif field_number == 10:
                instance.java_multiple_files = reader.read_bool()
            elif field_number == 20:
                instance.java_generate_equals_and_hash = reader.read_bool()
            elif field_number == 27:
                instance.java_string_check_utf8 = reader.read_bool()
            elif field_number == 9:
                instance.optimize_for = OptimizeMode(Int(reader.read_enum()))
            elif field_number == 11:
                instance.go_package = reader.read_string()
            elif field_number == 16:
                instance.cc_generic_services = reader.read_bool()
            elif field_number == 17:
                instance.java_generic_services = reader.read_bool()
            elif field_number == 18:
                instance.py_generic_services = reader.read_bool()
            elif field_number == 23:
                instance.deprecated = reader.read_bool()
            elif field_number == 31:
                instance.cc_enable_arenas = reader.read_bool()
            elif field_number == 36:
                instance.objc_class_prefix = reader.read_string()
            elif field_number == 37:
                instance.csharp_namespace = reader.read_string()
            elif field_number == 39:
                instance.swift_prefix = reader.read_string()
            elif field_number == 40:
                instance.php_class_prefix = reader.read_string()
            elif field_number == 41:
                instance.php_namespace = reader.read_string()
            elif field_number == 44:
                instance.php_metadata_namespace = reader.read_string()
            elif field_number == 45:
                instance.ruby_package = reader.read_string()
            elif field_number == 50:
                var sub = reader.read_message()
                instance.features = FeatureSet.parse(sub)
            elif field_number == 999:
                var sub = reader.read_message()
                instance.uninterpreted_option.append(UninterpretedOption.parse(sub))
            else:
                reader.skip_field(wire_type)
        return instance^

    def serialize(self, mut writer: ProtoWriter):
        var sub = ProtoWriter()
        if self.java_package:
            writer.write_string(1, self.java_package.value())
        if self.java_outer_classname:
            writer.write_string(8, self.java_outer_classname.value())
        if self.java_multiple_files:
            writer.write_bool(10, self.java_multiple_files.value())
        if self.java_generate_equals_and_hash:
            writer.write_bool(20, self.java_generate_equals_and_hash.value())
        if self.java_string_check_utf8:
            writer.write_bool(27, self.java_string_check_utf8.value())
        if self.optimize_for:
            writer.write_int32(9, Int32(self.optimize_for.value()._value))
        if self.go_package:
            writer.write_string(11, self.go_package.value())
        if self.cc_generic_services:
            writer.write_bool(16, self.cc_generic_services.value())
        if self.java_generic_services:
            writer.write_bool(17, self.java_generic_services.value())
        if self.py_generic_services:
            writer.write_bool(18, self.py_generic_services.value())
        if self.deprecated:
            writer.write_bool(23, self.deprecated.value())
        if self.cc_enable_arenas:
            writer.write_bool(31, self.cc_enable_arenas.value())
        if self.objc_class_prefix:
            writer.write_string(36, self.objc_class_prefix.value())
        if self.csharp_namespace:
            writer.write_string(37, self.csharp_namespace.value())
        if self.swift_prefix:
            writer.write_string(39, self.swift_prefix.value())
        if self.php_class_prefix:
            writer.write_string(40, self.php_class_prefix.value())
        if self.php_namespace:
            writer.write_string(41, self.php_namespace.value())
        if self.php_metadata_namespace:
            writer.write_string(44, self.php_metadata_namespace.value())
        if self.ruby_package:
            writer.write_string(45, self.ruby_package.value())
        if self.features:
            sub = ProtoWriter()
            self.features.value().serialize(sub)
            writer.write_message(50, sub)
        for item in self.uninterpreted_option:
            sub = ProtoWriter()
            item.serialize(sub)
            writer.write_message(999, sub)


@fieldwise_init
struct MessageOptions(Copyable, ProtoSerializable):
    var message_set_wire_format: Optional[Bool]
    var no_standard_descriptor_accessor: Optional[Bool]
    var deprecated: Optional[Bool]
    var map_entry: Optional[Bool]
    var deprecated_legacy_json_field_conflicts: Optional[Bool]
    var features: Optional[FeatureSet]
    var uninterpreted_option: List[UninterpretedOption]

    def __init__(out self):
        self.message_set_wire_format = None
        self.no_standard_descriptor_accessor = None
        self.deprecated = None
        self.map_entry = None
        self.deprecated_legacy_json_field_conflicts = None
        self.features = None
        self.uninterpreted_option = List[UninterpretedOption]()

    @staticmethod
    def parse(mut reader: ProtoReader) raises -> Self:
        var instance = Self()
        while reader.has_more():
            var field_number, wire_type = reader.read_tag()

            if field_number == 1:
                instance.message_set_wire_format = reader.read_bool()
            elif field_number == 2:
                instance.no_standard_descriptor_accessor = reader.read_bool()
            elif field_number == 3:
                instance.deprecated = reader.read_bool()
            elif field_number == 7:
                instance.map_entry = reader.read_bool()
            elif field_number == 11:
                instance.deprecated_legacy_json_field_conflicts = reader.read_bool()
            elif field_number == 12:
                var sub = reader.read_message()
                instance.features = FeatureSet.parse(sub)
            elif field_number == 999:
                var sub = reader.read_message()
                instance.uninterpreted_option.append(UninterpretedOption.parse(sub))
            else:
                reader.skip_field(wire_type)
        return instance^

    def serialize(self, mut writer: ProtoWriter):
        var sub = ProtoWriter()
        if self.message_set_wire_format:
            writer.write_bool(1, self.message_set_wire_format.value())
        if self.no_standard_descriptor_accessor:
            writer.write_bool(2, self.no_standard_descriptor_accessor.value())
        if self.deprecated:
            writer.write_bool(3, self.deprecated.value())
        if self.map_entry:
            writer.write_bool(7, self.map_entry.value())
        if self.deprecated_legacy_json_field_conflicts:
            writer.write_bool(11, self.deprecated_legacy_json_field_conflicts.value())
        if self.features:
            sub = ProtoWriter()
            self.features.value().serialize(sub)
            writer.write_message(12, sub)
        for item in self.uninterpreted_option:
            sub = ProtoWriter()
            item.serialize(sub)
            writer.write_message(999, sub)


@fieldwise_init
struct FieldOptionsEditionDefault(Copyable, ProtoSerializable):
    var edition: Optional[Edition]
    var value: Optional[String]

    def __init__(out self):
        self.edition = None
        self.value = None

    @staticmethod
    def parse(mut reader: ProtoReader) raises -> Self:
        var instance = Self()
        while reader.has_more():
            var field_number, wire_type = reader.read_tag()

            if field_number == 3:
                instance.edition = Edition(Int(reader.read_enum()))
            elif field_number == 2:
                instance.value = reader.read_string()
            else:
                reader.skip_field(wire_type)
        return instance^

    def serialize(self, mut writer: ProtoWriter):
        var sub = ProtoWriter()
        if self.edition:
            writer.write_int32(3, Int32(self.edition.value()._value))
        if self.value:
            writer.write_string(2, self.value.value())


@fieldwise_init
struct FieldOptionsFeatureSupport(Copyable, ProtoSerializable):
    var edition_introduced: Optional[Edition]
    var edition_deprecated: Optional[Edition]
    var deprecation_warning: Optional[String]
    var edition_removed: Optional[Edition]

    def __init__(out self):
        self.edition_introduced = None
        self.edition_deprecated = None
        self.deprecation_warning = None
        self.edition_removed = None

    @staticmethod
    def parse(mut reader: ProtoReader) raises -> Self:
        var instance = Self()
        while reader.has_more():
            var field_number, wire_type = reader.read_tag()

            if field_number == 1:
                instance.edition_introduced = Edition(Int(reader.read_enum()))
            elif field_number == 2:
                instance.edition_deprecated = Edition(Int(reader.read_enum()))
            elif field_number == 3:
                instance.deprecation_warning = reader.read_string()
            elif field_number == 4:
                instance.edition_removed = Edition(Int(reader.read_enum()))
            else:
                reader.skip_field(wire_type)
        return instance^

    def serialize(self, mut writer: ProtoWriter):
        var sub = ProtoWriter()
        if self.edition_introduced:
            writer.write_int32(1, Int32(self.edition_introduced.value()._value))
        if self.edition_deprecated:
            writer.write_int32(2, Int32(self.edition_deprecated.value()._value))
        if self.deprecation_warning:
            writer.write_string(3, self.deprecation_warning.value())
        if self.edition_removed:
            writer.write_int32(4, Int32(self.edition_removed.value()._value))


@fieldwise_init
struct CType(Equatable, ImplicitlyCopyable, ProtoSerializable):
    var _value: Int

    comptime STRING = CType(0)

    comptime CORD = CType(1)

    comptime STRING_PIECE = CType(2)

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
struct JSType(Equatable, ImplicitlyCopyable, ProtoSerializable):
    var _value: Int

    comptime JS_NORMAL = JSType(0)

    comptime JS_STRING = JSType(1)

    comptime JS_NUMBER = JSType(2)

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
struct OptionRetention(Equatable, ImplicitlyCopyable, ProtoSerializable):
    var _value: Int

    comptime RETENTION_UNKNOWN = OptionRetention(0)

    comptime RETENTION_RUNTIME = OptionRetention(1)

    comptime RETENTION_SOURCE = OptionRetention(2)

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
struct OptionTargetType(Equatable, ImplicitlyCopyable, ProtoSerializable):
    var _value: Int

    comptime TARGET_TYPE_UNKNOWN = OptionTargetType(0)

    comptime TARGET_TYPE_FILE = OptionTargetType(1)

    comptime TARGET_TYPE_EXTENSION_RANGE = OptionTargetType(2)

    comptime TARGET_TYPE_MESSAGE = OptionTargetType(3)

    comptime TARGET_TYPE_FIELD = OptionTargetType(4)

    comptime TARGET_TYPE_ONEOF = OptionTargetType(5)

    comptime TARGET_TYPE_ENUM = OptionTargetType(6)

    comptime TARGET_TYPE_ENUM_ENTRY = OptionTargetType(7)

    comptime TARGET_TYPE_SERVICE = OptionTargetType(8)

    comptime TARGET_TYPE_METHOD = OptionTargetType(9)

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
struct FieldOptions(Copyable, ProtoSerializable):
    var ctype: Optional[CType]
    var packed: Optional[Bool]
    var jstype: Optional[JSType]
    var lazy: Optional[Bool]
    var unverified_lazy: Optional[Bool]
    var deprecated: Optional[Bool]
    var weak: Optional[Bool]
    var debug_redact: Optional[Bool]
    var retention: Optional[OptionRetention]
    var targets: List[OptionTargetType]
    var edition_defaults: List[FieldOptionsEditionDefault]
    var features: Optional[FeatureSet]
    var feature_support: Optional[FieldOptionsFeatureSupport]
    var uninterpreted_option: List[UninterpretedOption]

    def __init__(out self):
        self.ctype = None
        self.packed = None
        self.jstype = None
        self.lazy = None
        self.unverified_lazy = None
        self.deprecated = None
        self.weak = None
        self.debug_redact = None
        self.retention = None
        self.targets = List[OptionTargetType]()
        self.edition_defaults = List[FieldOptionsEditionDefault]()
        self.features = None
        self.feature_support = None
        self.uninterpreted_option = List[UninterpretedOption]()

    @staticmethod
    def parse(mut reader: ProtoReader) raises -> Self:
        var instance = Self()
        while reader.has_more():
            var field_number, wire_type = reader.read_tag()

            if field_number == 1:
                instance.ctype = CType(Int(reader.read_enum()))
            elif field_number == 2:
                instance.packed = reader.read_bool()
            elif field_number == 6:
                instance.jstype = JSType(Int(reader.read_enum()))
            elif field_number == 5:
                instance.lazy = reader.read_bool()
            elif field_number == 15:
                instance.unverified_lazy = reader.read_bool()
            elif field_number == 3:
                instance.deprecated = reader.read_bool()
            elif field_number == 10:
                instance.weak = reader.read_bool()
            elif field_number == 16:
                instance.debug_redact = reader.read_bool()
            elif field_number == 17:
                instance.retention = OptionRetention(Int(reader.read_enum()))
            elif field_number == 19:
                if wire_type.value == 2:
                    var packed = reader.read_message()
                    while packed.has_more():
                        instance.targets.append(OptionTargetType(Int(packed.read_enum())))
                else:
                    instance.targets.append(OptionTargetType(Int(reader.read_enum())))
            elif field_number == 20:
                var sub = reader.read_message()
                instance.edition_defaults.append(FieldOptionsEditionDefault.parse(sub))
            elif field_number == 21:
                var sub = reader.read_message()
                instance.features = FeatureSet.parse(sub)
            elif field_number == 22:
                var sub = reader.read_message()
                instance.feature_support = FieldOptionsFeatureSupport.parse(sub)
            elif field_number == 999:
                var sub = reader.read_message()
                instance.uninterpreted_option.append(UninterpretedOption.parse(sub))
            else:
                reader.skip_field(wire_type)
        return instance^

    def serialize(self, mut writer: ProtoWriter):
        var sub = ProtoWriter()
        if self.ctype:
            writer.write_int32(1, Int32(self.ctype.value()._value))
        if self.packed:
            writer.write_bool(2, self.packed.value())
        if self.jstype:
            writer.write_int32(6, Int32(self.jstype.value()._value))
        if self.lazy:
            writer.write_bool(5, self.lazy.value())
        if self.unverified_lazy:
            writer.write_bool(15, self.unverified_lazy.value())
        if self.deprecated:
            writer.write_bool(3, self.deprecated.value())
        if self.weak:
            writer.write_bool(10, self.weak.value())
        if self.debug_redact:
            writer.write_bool(16, self.debug_redact.value())
        if self.retention:
            writer.write_int32(17, Int32(self.retention.value()._value))
        for item in self.targets:
            writer.write_int32(19, Int32(item._value))
        for item in self.edition_defaults:
            sub = ProtoWriter()
            item.serialize(sub)
            writer.write_message(20, sub)
        if self.features:
            sub = ProtoWriter()
            self.features.value().serialize(sub)
            writer.write_message(21, sub)
        if self.feature_support:
            sub = ProtoWriter()
            self.feature_support.value().serialize(sub)
            writer.write_message(22, sub)
        for item in self.uninterpreted_option:
            sub = ProtoWriter()
            item.serialize(sub)
            writer.write_message(999, sub)


@fieldwise_init
struct OneofOptions(Copyable, ProtoSerializable):
    var features: Optional[FeatureSet]
    var uninterpreted_option: List[UninterpretedOption]

    def __init__(out self):
        self.features = None
        self.uninterpreted_option = List[UninterpretedOption]()

    @staticmethod
    def parse(mut reader: ProtoReader) raises -> Self:
        var instance = Self()
        while reader.has_more():
            var field_number, wire_type = reader.read_tag()

            if field_number == 1:
                var sub = reader.read_message()
                instance.features = FeatureSet.parse(sub)
            elif field_number == 999:
                var sub = reader.read_message()
                instance.uninterpreted_option.append(UninterpretedOption.parse(sub))
            else:
                reader.skip_field(wire_type)
        return instance^

    def serialize(self, mut writer: ProtoWriter):
        var sub = ProtoWriter()
        if self.features:
            sub = ProtoWriter()
            self.features.value().serialize(sub)
            writer.write_message(1, sub)
        for item in self.uninterpreted_option:
            sub = ProtoWriter()
            item.serialize(sub)
            writer.write_message(999, sub)


@fieldwise_init
struct EnumOptions(Copyable, ProtoSerializable):
    var allow_alias: Optional[Bool]
    var deprecated: Optional[Bool]
    var deprecated_legacy_json_field_conflicts: Optional[Bool]
    var features: Optional[FeatureSet]
    var uninterpreted_option: List[UninterpretedOption]

    def __init__(out self):
        self.allow_alias = None
        self.deprecated = None
        self.deprecated_legacy_json_field_conflicts = None
        self.features = None
        self.uninterpreted_option = List[UninterpretedOption]()

    @staticmethod
    def parse(mut reader: ProtoReader) raises -> Self:
        var instance = Self()
        while reader.has_more():
            var field_number, wire_type = reader.read_tag()

            if field_number == 2:
                instance.allow_alias = reader.read_bool()
            elif field_number == 3:
                instance.deprecated = reader.read_bool()
            elif field_number == 6:
                instance.deprecated_legacy_json_field_conflicts = reader.read_bool()
            elif field_number == 7:
                var sub = reader.read_message()
                instance.features = FeatureSet.parse(sub)
            elif field_number == 999:
                var sub = reader.read_message()
                instance.uninterpreted_option.append(UninterpretedOption.parse(sub))
            else:
                reader.skip_field(wire_type)
        return instance^

    def serialize(self, mut writer: ProtoWriter):
        var sub = ProtoWriter()
        if self.allow_alias:
            writer.write_bool(2, self.allow_alias.value())
        if self.deprecated:
            writer.write_bool(3, self.deprecated.value())
        if self.deprecated_legacy_json_field_conflicts:
            writer.write_bool(6, self.deprecated_legacy_json_field_conflicts.value())
        if self.features:
            sub = ProtoWriter()
            self.features.value().serialize(sub)
            writer.write_message(7, sub)
        for item in self.uninterpreted_option:
            sub = ProtoWriter()
            item.serialize(sub)
            writer.write_message(999, sub)


@fieldwise_init
struct EnumValueOptions(Copyable, ProtoSerializable):
    var deprecated: Optional[Bool]
    var features: Optional[FeatureSet]
    var debug_redact: Optional[Bool]
    var feature_support: Optional[FieldOptionsFeatureSupport]
    var uninterpreted_option: List[UninterpretedOption]

    def __init__(out self):
        self.deprecated = None
        self.features = None
        self.debug_redact = None
        self.feature_support = None
        self.uninterpreted_option = List[UninterpretedOption]()

    @staticmethod
    def parse(mut reader: ProtoReader) raises -> Self:
        var instance = Self()
        while reader.has_more():
            var field_number, wire_type = reader.read_tag()

            if field_number == 1:
                instance.deprecated = reader.read_bool()
            elif field_number == 2:
                var sub = reader.read_message()
                instance.features = FeatureSet.parse(sub)
            elif field_number == 3:
                instance.debug_redact = reader.read_bool()
            elif field_number == 4:
                var sub = reader.read_message()
                instance.feature_support = FieldOptionsFeatureSupport.parse(sub)
            elif field_number == 999:
                var sub = reader.read_message()
                instance.uninterpreted_option.append(UninterpretedOption.parse(sub))
            else:
                reader.skip_field(wire_type)
        return instance^

    def serialize(self, mut writer: ProtoWriter):
        var sub = ProtoWriter()
        if self.deprecated:
            writer.write_bool(1, self.deprecated.value())
        if self.features:
            sub = ProtoWriter()
            self.features.value().serialize(sub)
            writer.write_message(2, sub)
        if self.debug_redact:
            writer.write_bool(3, self.debug_redact.value())
        if self.feature_support:
            sub = ProtoWriter()
            self.feature_support.value().serialize(sub)
            writer.write_message(4, sub)
        for item in self.uninterpreted_option:
            sub = ProtoWriter()
            item.serialize(sub)
            writer.write_message(999, sub)


@fieldwise_init
struct ServiceOptions(Copyable, ProtoSerializable):
    var features: Optional[FeatureSet]
    var deprecated: Optional[Bool]
    var uninterpreted_option: List[UninterpretedOption]

    def __init__(out self):
        self.features = None
        self.deprecated = None
        self.uninterpreted_option = List[UninterpretedOption]()

    @staticmethod
    def parse(mut reader: ProtoReader) raises -> Self:
        var instance = Self()
        while reader.has_more():
            var field_number, wire_type = reader.read_tag()

            if field_number == 34:
                var sub = reader.read_message()
                instance.features = FeatureSet.parse(sub)
            elif field_number == 33:
                instance.deprecated = reader.read_bool()
            elif field_number == 999:
                var sub = reader.read_message()
                instance.uninterpreted_option.append(UninterpretedOption.parse(sub))
            else:
                reader.skip_field(wire_type)
        return instance^

    def serialize(self, mut writer: ProtoWriter):
        var sub = ProtoWriter()
        if self.features:
            sub = ProtoWriter()
            self.features.value().serialize(sub)
            writer.write_message(34, sub)
        if self.deprecated:
            writer.write_bool(33, self.deprecated.value())
        for item in self.uninterpreted_option:
            sub = ProtoWriter()
            item.serialize(sub)
            writer.write_message(999, sub)


@fieldwise_init
struct IdempotencyLevel(Equatable, ImplicitlyCopyable, ProtoSerializable):
    var _value: Int

    comptime IDEMPOTENCY_UNKNOWN = IdempotencyLevel(0)

    comptime NO_SIDE_EFFECTS = IdempotencyLevel(1)

    comptime IDEMPOTENT = IdempotencyLevel(2)

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
struct MethodOptions(Copyable, ProtoSerializable):
    var deprecated: Optional[Bool]
    var idempotency_level: Optional[IdempotencyLevel]
    var features: Optional[FeatureSet]
    var uninterpreted_option: List[UninterpretedOption]

    def __init__(out self):
        self.deprecated = None
        self.idempotency_level = None
        self.features = None
        self.uninterpreted_option = List[UninterpretedOption]()

    @staticmethod
    def parse(mut reader: ProtoReader) raises -> Self:
        var instance = Self()
        while reader.has_more():
            var field_number, wire_type = reader.read_tag()

            if field_number == 33:
                instance.deprecated = reader.read_bool()
            elif field_number == 34:
                instance.idempotency_level = IdempotencyLevel(Int(reader.read_enum()))
            elif field_number == 35:
                var sub = reader.read_message()
                instance.features = FeatureSet.parse(sub)
            elif field_number == 999:
                var sub = reader.read_message()
                instance.uninterpreted_option.append(UninterpretedOption.parse(sub))
            else:
                reader.skip_field(wire_type)
        return instance^

    def serialize(self, mut writer: ProtoWriter):
        var sub = ProtoWriter()
        if self.deprecated:
            writer.write_bool(33, self.deprecated.value())
        if self.idempotency_level:
            writer.write_int32(34, Int32(self.idempotency_level.value()._value))
        if self.features:
            sub = ProtoWriter()
            self.features.value().serialize(sub)
            writer.write_message(35, sub)
        for item in self.uninterpreted_option:
            sub = ProtoWriter()
            item.serialize(sub)
            writer.write_message(999, sub)


@fieldwise_init
struct UninterpretedOptionNamePart(Copyable, ProtoSerializable):
    var name_part: String
    var is_extension: Bool

    def __init__(out self):
        self.name_part = String()
        self.is_extension = False

    @staticmethod
    def parse(mut reader: ProtoReader) raises -> Self:
        var instance = Self()
        while reader.has_more():
            var field_number, wire_type = reader.read_tag()

            if field_number == 1:
                instance.name_part = reader.read_string()
            elif field_number == 2:
                instance.is_extension = reader.read_bool()
            else:
                reader.skip_field(wire_type)
        return instance^

    def serialize(self, mut writer: ProtoWriter):
        var sub = ProtoWriter()
        writer.write_string(1, self.name_part)
        writer.write_bool(2, self.is_extension)


@fieldwise_init
struct UninterpretedOption(Copyable, ProtoSerializable):
    var name: List[UninterpretedOptionNamePart]
    var identifier_value: Optional[String]
    var positive_int_value: Optional[UInt64]
    var negative_int_value: Optional[Int64]
    var double_value: Optional[Float64]
    var string_value: Optional[List[UInt8]]
    var aggregate_value: Optional[String]

    def __init__(out self):
        self.name = List[UninterpretedOptionNamePart]()
        self.identifier_value = None
        self.positive_int_value = None
        self.negative_int_value = None
        self.double_value = None
        self.string_value = None
        self.aggregate_value = None

    @staticmethod
    def parse(mut reader: ProtoReader) raises -> Self:
        var instance = Self()
        while reader.has_more():
            var field_number, wire_type = reader.read_tag()

            if field_number == 2:
                var sub = reader.read_message()
                instance.name.append(UninterpretedOptionNamePart.parse(sub))
            elif field_number == 3:
                instance.identifier_value = reader.read_string()
            elif field_number == 4:
                instance.positive_int_value = reader.read_uint64()
            elif field_number == 5:
                instance.negative_int_value = reader.read_int64()
            elif field_number == 6:
                instance.double_value = reader.read_double()
            elif field_number == 7:
                instance.string_value = reader.read_bytes()
            elif field_number == 8:
                instance.aggregate_value = reader.read_string()
            else:
                reader.skip_field(wire_type)
        return instance^

    def serialize(self, mut writer: ProtoWriter):
        var sub = ProtoWriter()
        for item in self.name:
            sub = ProtoWriter()
            item.serialize(sub)
            writer.write_message(2, sub)
        if self.identifier_value:
            writer.write_string(3, self.identifier_value.value())
        if self.positive_int_value:
            writer.write_uint64(4, self.positive_int_value.value())
        if self.negative_int_value:
            writer.write_int64(5, self.negative_int_value.value())
        if self.double_value:
            writer.write_double(6, self.double_value.value())
        if self.string_value:
            writer.write_bytes(7, self.string_value.value())
        if self.aggregate_value:
            writer.write_string(8, self.aggregate_value.value())


@fieldwise_init
struct FieldPresence(Equatable, ImplicitlyCopyable, ProtoSerializable):
    var _value: Int

    comptime FIELD_PRESENCE_UNKNOWN = FieldPresence(0)

    comptime EXPLICIT = FieldPresence(1)

    comptime IMPLICIT = FieldPresence(2)

    comptime LEGACY_REQUIRED = FieldPresence(3)

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
struct EnumType(Equatable, ImplicitlyCopyable, ProtoSerializable):
    var _value: Int

    comptime ENUM_TYPE_UNKNOWN = EnumType(0)

    comptime OPEN = EnumType(1)

    comptime CLOSED = EnumType(2)

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
struct RepeatedFieldEncoding(Equatable, ImplicitlyCopyable, ProtoSerializable):
    var _value: Int

    comptime REPEATED_FIELD_ENCODING_UNKNOWN = RepeatedFieldEncoding(0)

    comptime PACKED = RepeatedFieldEncoding(1)

    comptime EXPANDED = RepeatedFieldEncoding(2)

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
struct Utf8Validation(Equatable, ImplicitlyCopyable, ProtoSerializable):
    var _value: Int

    comptime UTF8_VALIDATION_UNKNOWN = Utf8Validation(0)

    comptime VERIFY = Utf8Validation(2)

    comptime NONE = Utf8Validation(3)

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
struct MessageEncoding(Equatable, ImplicitlyCopyable, ProtoSerializable):
    var _value: Int

    comptime MESSAGE_ENCODING_UNKNOWN = MessageEncoding(0)

    comptime LENGTH_PREFIXED = MessageEncoding(1)

    comptime DELIMITED = MessageEncoding(2)

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
struct JsonFormat(Equatable, ImplicitlyCopyable, ProtoSerializable):
    var _value: Int

    comptime JSON_FORMAT_UNKNOWN = JsonFormat(0)

    comptime ALLOW = JsonFormat(1)

    comptime LEGACY_BEST_EFFORT = JsonFormat(2)

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
struct FeatureSet(Copyable, ProtoSerializable):
    var field_presence: Optional[FieldPresence]
    var enum_type: Optional[EnumType]
    var repeated_field_encoding: Optional[RepeatedFieldEncoding]
    var utf8_validation: Optional[Utf8Validation]
    var message_encoding: Optional[MessageEncoding]
    var json_format: Optional[JsonFormat]

    def __init__(out self):
        self.field_presence = None
        self.enum_type = None
        self.repeated_field_encoding = None
        self.utf8_validation = None
        self.message_encoding = None
        self.json_format = None

    @staticmethod
    def parse(mut reader: ProtoReader) raises -> Self:
        var instance = Self()
        while reader.has_more():
            var field_number, wire_type = reader.read_tag()

            if field_number == 1:
                instance.field_presence = FieldPresence(Int(reader.read_enum()))
            elif field_number == 2:
                instance.enum_type = EnumType(Int(reader.read_enum()))
            elif field_number == 3:
                instance.repeated_field_encoding = RepeatedFieldEncoding(Int(reader.read_enum()))
            elif field_number == 4:
                instance.utf8_validation = Utf8Validation(Int(reader.read_enum()))
            elif field_number == 5:
                instance.message_encoding = MessageEncoding(Int(reader.read_enum()))
            elif field_number == 6:
                instance.json_format = JsonFormat(Int(reader.read_enum()))
            else:
                reader.skip_field(wire_type)
        return instance^

    def serialize(self, mut writer: ProtoWriter):
        var sub = ProtoWriter()
        if self.field_presence:
            writer.write_int32(1, Int32(self.field_presence.value()._value))
        if self.enum_type:
            writer.write_int32(2, Int32(self.enum_type.value()._value))
        if self.repeated_field_encoding:
            writer.write_int32(3, Int32(self.repeated_field_encoding.value()._value))
        if self.utf8_validation:
            writer.write_int32(4, Int32(self.utf8_validation.value()._value))
        if self.message_encoding:
            writer.write_int32(5, Int32(self.message_encoding.value()._value))
        if self.json_format:
            writer.write_int32(6, Int32(self.json_format.value()._value))


@fieldwise_init
struct FeatureSetDefaultsFeatureSetEditionDefault(Copyable, ProtoSerializable):
    var edition: Optional[Edition]
    var overridable_features: Optional[FeatureSet]
    var fixed_features: Optional[FeatureSet]

    def __init__(out self):
        self.edition = None
        self.overridable_features = None
        self.fixed_features = None

    @staticmethod
    def parse(mut reader: ProtoReader) raises -> Self:
        var instance = Self()
        while reader.has_more():
            var field_number, wire_type = reader.read_tag()

            if field_number == 3:
                instance.edition = Edition(Int(reader.read_enum()))
            elif field_number == 4:
                var sub = reader.read_message()
                instance.overridable_features = FeatureSet.parse(sub)
            elif field_number == 5:
                var sub = reader.read_message()
                instance.fixed_features = FeatureSet.parse(sub)
            else:
                reader.skip_field(wire_type)
        return instance^

    def serialize(self, mut writer: ProtoWriter):
        var sub = ProtoWriter()
        if self.edition:
            writer.write_int32(3, Int32(self.edition.value()._value))
        if self.overridable_features:
            sub = ProtoWriter()
            self.overridable_features.value().serialize(sub)
            writer.write_message(4, sub)
        if self.fixed_features:
            sub = ProtoWriter()
            self.fixed_features.value().serialize(sub)
            writer.write_message(5, sub)


@fieldwise_init
struct FeatureSetDefaults(Copyable, ProtoSerializable):
    var defaults: List[FeatureSetDefaultsFeatureSetEditionDefault]
    var minimum_edition: Optional[Edition]
    var maximum_edition: Optional[Edition]

    def __init__(out self):
        self.defaults = List[FeatureSetDefaultsFeatureSetEditionDefault]()
        self.minimum_edition = None
        self.maximum_edition = None

    @staticmethod
    def parse(mut reader: ProtoReader) raises -> Self:
        var instance = Self()
        while reader.has_more():
            var field_number, wire_type = reader.read_tag()

            if field_number == 1:
                var sub = reader.read_message()
                instance.defaults.append(FeatureSetDefaultsFeatureSetEditionDefault.parse(sub))
            elif field_number == 4:
                instance.minimum_edition = Edition(Int(reader.read_enum()))
            elif field_number == 5:
                instance.maximum_edition = Edition(Int(reader.read_enum()))
            else:
                reader.skip_field(wire_type)
        return instance^

    def serialize(self, mut writer: ProtoWriter):
        var sub = ProtoWriter()
        for item in self.defaults:
            sub = ProtoWriter()
            item.serialize(sub)
            writer.write_message(1, sub)
        if self.minimum_edition:
            writer.write_int32(4, Int32(self.minimum_edition.value()._value))
        if self.maximum_edition:
            writer.write_int32(5, Int32(self.maximum_edition.value()._value))


@fieldwise_init
struct SourceCodeInfoLocation(Copyable, ProtoSerializable):
    var path: List[Int32]
    var span: List[Int32]
    var leading_comments: Optional[String]
    var trailing_comments: Optional[String]
    var leading_detached_comments: List[String]

    def __init__(out self):
        self.path = List[Int32]()
        self.span = List[Int32]()
        self.leading_comments = None
        self.trailing_comments = None
        self.leading_detached_comments = List[String]()

    @staticmethod
    def parse(mut reader: ProtoReader) raises -> Self:
        var instance = Self()
        while reader.has_more():
            var field_number, wire_type = reader.read_tag()

            if field_number == 1:
                if wire_type.value == 2:
                    var packed = reader.read_message()
                    while packed.has_more():
                        instance.path.append(packed.read_int32())
                else:
                    instance.path.append(reader.read_int32())
            elif field_number == 2:
                if wire_type.value == 2:
                    var packed = reader.read_message()
                    while packed.has_more():
                        instance.span.append(packed.read_int32())
                else:
                    instance.span.append(reader.read_int32())
            elif field_number == 3:
                instance.leading_comments = reader.read_string()
            elif field_number == 4:
                instance.trailing_comments = reader.read_string()
            elif field_number == 6:
                instance.leading_detached_comments.append(reader.read_string())
            else:
                reader.skip_field(wire_type)
        return instance^

    def serialize(self, mut writer: ProtoWriter):
        var sub = ProtoWriter()
        for item in self.path:
            writer.write_int32(1, item)
        for item in self.span:
            writer.write_int32(2, item)
        if self.leading_comments:
            writer.write_string(3, self.leading_comments.value())
        if self.trailing_comments:
            writer.write_string(4, self.trailing_comments.value())
        for item in self.leading_detached_comments:
            writer.write_string(6, item)


@fieldwise_init
struct SourceCodeInfo(Copyable, ProtoSerializable):
    var location: List[SourceCodeInfoLocation]

    def __init__(out self):
        self.location = List[SourceCodeInfoLocation]()

    @staticmethod
    def parse(mut reader: ProtoReader) raises -> Self:
        var instance = Self()
        while reader.has_more():
            var field_number, wire_type = reader.read_tag()

            if field_number == 1:
                var sub = reader.read_message()
                instance.location.append(SourceCodeInfoLocation.parse(sub))
            else:
                reader.skip_field(wire_type)
        return instance^

    def serialize(self, mut writer: ProtoWriter):
        var sub = ProtoWriter()
        for item in self.location:
            sub = ProtoWriter()
            item.serialize(sub)
            writer.write_message(1, sub)


@fieldwise_init
struct Semantic(Equatable, ImplicitlyCopyable, ProtoSerializable):
    var _value: Int

    comptime NONE = Semantic(0)

    comptime SET = Semantic(1)

    comptime ALIAS = Semantic(2)

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
struct GeneratedCodeInfoAnnotation(Copyable, ProtoSerializable):
    var path: List[Int32]
    var source_file: Optional[String]
    var begin: Optional[Int32]
    var end: Optional[Int32]
    var semantic: Optional[Semantic]

    def __init__(out self):
        self.path = List[Int32]()
        self.source_file = None
        self.begin = None
        self.end = None
        self.semantic = None

    @staticmethod
    def parse(mut reader: ProtoReader) raises -> Self:
        var instance = Self()
        while reader.has_more():
            var field_number, wire_type = reader.read_tag()

            if field_number == 1:
                if wire_type.value == 2:
                    var packed = reader.read_message()
                    while packed.has_more():
                        instance.path.append(packed.read_int32())
                else:
                    instance.path.append(reader.read_int32())
            elif field_number == 2:
                instance.source_file = reader.read_string()
            elif field_number == 3:
                instance.begin = reader.read_int32()
            elif field_number == 4:
                instance.end = reader.read_int32()
            elif field_number == 5:
                instance.semantic = Semantic(Int(reader.read_enum()))
            else:
                reader.skip_field(wire_type)
        return instance^

    def serialize(self, mut writer: ProtoWriter):
        var sub = ProtoWriter()
        for item in self.path:
            writer.write_int32(1, item)
        if self.source_file:
            writer.write_string(2, self.source_file.value())
        if self.begin:
            writer.write_int32(3, self.begin.value())
        if self.end:
            writer.write_int32(4, self.end.value())
        if self.semantic:
            writer.write_int32(5, Int32(self.semantic.value()._value))


@fieldwise_init
struct GeneratedCodeInfo(Copyable, ProtoSerializable):
    var annotation: List[GeneratedCodeInfoAnnotation]

    def __init__(out self):
        self.annotation = List[GeneratedCodeInfoAnnotation]()

    @staticmethod
    def parse(mut reader: ProtoReader) raises -> Self:
        var instance = Self()
        while reader.has_more():
            var field_number, wire_type = reader.read_tag()

            if field_number == 1:
                var sub = reader.read_message()
                instance.annotation.append(GeneratedCodeInfoAnnotation.parse(sub))
            else:
                reader.skip_field(wire_type)
        return instance^

    def serialize(self, mut writer: ProtoWriter):
        var sub = ProtoWriter()
        for item in self.annotation:
            sub = ProtoWriter()
            item.serialize(sub)
            writer.write_message(1, sub)
