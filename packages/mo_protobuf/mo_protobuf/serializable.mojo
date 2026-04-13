from mo_protobuf.writer import ProtoWriter
from mo_protobuf.reader import ProtoReader


trait ProtoSerializable:
    @staticmethod
    def parse(mut reader: ProtoReader) raises -> Self:
        ...

    def serialize(self, mut writer: ProtoWriter) raises:
        ...
