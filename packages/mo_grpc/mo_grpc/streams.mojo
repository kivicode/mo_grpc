"""
gRPC stream handles for the four streaming combinations
"""

from mo_protobuf import ProtoReader, ProtoWriter, ProtoSerializable
from mo_protobuf.common import Bytes


struct GrpcServerStream[Resp: ProtoSerializable & Copyable]:
    """A server-streaming call: client sent one request, server sends many responses."""

    var _done: Bool

    def __init__(out self):
        self._done = False

    def recv(mut self) raises -> Optional[Resp]:
        """Returns the next response, or None when the stream is complete."""
        raise Error("GrpcServerStream.recv: transport not implemented")


struct GrpcClientStream[Req: ProtoSerializable & Copyable, Resp: ProtoSerializable & Copyable]:
    """A client-streaming call: client sends many requests, server sends one response."""

    def __init__(out self):
        pass

    def send(mut self, msg: Req) raises:
        raise Error("GrpcClientStream.send: transport not implemented")

    def close_and_recv(mut self) raises -> Resp:
        raise Error("GrpcClientStream.close_and_recv: transport not implemented")


struct GrpcBidiStream[Req: ProtoSerializable & Copyable, Resp: ProtoSerializable & Copyable]:
    """A bidirectional streaming call: both sides send many messages."""

    def __init__(out self):
        pass

    def send(mut self, msg: Req) raises:
        raise Error("GrpcBidiStream.send: transport not implemented")

    def recv(mut self) raises -> Optional[Resp]:
        raise Error("GrpcBidiStream.recv: transport not implemented")

    def close_send(mut self) raises:
        raise Error("GrpcBidiStream.close_send: transport not implemented")
