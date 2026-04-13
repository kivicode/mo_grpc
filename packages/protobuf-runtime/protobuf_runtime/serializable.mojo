from protobuf_runtime.writer import ProtoWriter
from protobuf_runtime.reader import ProtoReader


trait ProtoSerializable:
    @staticmethod
    def parse(mut reader: ProtoReader) raises -> Self:
        ...

    def serialize(self, mut writer: ProtoWriter) raises:
        ...
