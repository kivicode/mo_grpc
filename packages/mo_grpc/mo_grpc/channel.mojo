"""
Client-side transport abstraction.
"""

from mo_protobuf import ProtoReader, ProtoWriter, ProtoSerializable
from mo_protobuf.common import Bytes
from mo_grpc.frame import encode_grpc_frame, decode_grpc_frame
from mo_grpc.streams import GrpcServerStream, GrpcClientStream, GrpcBidiStream
from mo_grpc.transport import http_post


struct GrpcChannel:
    var base_url: String

    def __init__(out self, base_url: String):
        self.base_url = base_url

    def unary_unary[
        Req: ProtoSerializable & Copyable, Resp: ProtoSerializable & Copyable
    ](mut self, method: String, request: Req,) raises -> Resp:
        """Send a single request, receive a single response over HTTP/2 + TLS."""
        var w = ProtoWriter()
        request.serialize(w)
        var framed_req = encode_grpc_frame(w.flush())

        var url = self.base_url + method
        var framed_resp = http_post(url, framed_req)

        var split = decode_grpc_frame(framed_resp)
        var r = ProtoReader(split.body^)
        return Resp.parse(r)

    def unary_stream[
        Req: ProtoSerializable & Copyable, Resp: ProtoSerializable & Copyable
    ](mut self, method: String, request: Req,) raises -> GrpcServerStream[Resp]:
        """Server-streaming is not yet implemented via libcurl easy handle. Requires multi handle + incremental frame decoding (TODO).
        """
        raise Error("unary_stream requires libcurl multi handle (TODO)")

    def stream_unary[
        Req: ProtoSerializable & Copyable, Resp: ProtoSerializable & Copyable
    ](mut self, method: String,) raises -> GrpcClientStream[Req, Resp]:
        """Client-streaming - requires libcurl read callback (TODO)."""
        raise Error("stream_unary requires libcurl read callback (TODO)")

    def bidi[
        Req: ProtoSerializable & Copyable, Resp: ProtoSerializable & Copyable
    ](mut self, method: String,) raises -> GrpcBidiStream[Req, Resp]:
        """Bidi streaming - requires libcurl multi handle (TODO)."""
        raise Error("bidi requires libcurl multi handle (TODO)")
