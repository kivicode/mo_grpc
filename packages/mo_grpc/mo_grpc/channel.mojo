"""
Client-side transport abstraction.
"""

from mojo_curl import Easy, CurlList
from mo_protobuf import ProtoReader, ProtoWriter, ProtoSerializable
from mo_protobuf.common import Bytes
from mo_grpc.frame import encode_grpc_frame, decode_grpc_frame
from mo_grpc.streams import GrpcServerStream, GrpcClientStream, GrpcBidiStream
from mo_grpc.transport import grpc_headers, http_post, perform_post


struct GrpcChannel(Movable):
    """A long-lived client channel.

    Holds a single libcurl Easy handle for the lifetime of the channel, so
    sequential RPCs reuse the same TCP / TLS / HTTP-2 connection. Without that
    reuse, every call would pay a full handshake — on a localhost loopback
    benchmark, that was the difference between ~180 req/s and ~6700 req/s.
    """

    var base_url: String
    var _easy: Easy

    def __init__(out self, base_url: String):
        self.base_url = base_url
        self._easy = Easy()

    def unary_unary[
        Req: ProtoSerializable & Copyable, Resp: ProtoSerializable & Copyable
    ](mut self, method: String, request: Req,) raises -> Resp:
        """Send a single request, receive a single response over HTTP/2 + TLS."""
        var w = ProtoWriter()
        request.serialize(w)
        var body = w.flush()
        var framed_req = encode_grpc_frame(body^)

        var url = self.base_url + method
        var headers = grpc_headers()
        var framed_resp = Bytes()
        var err = String("")
        try:
            framed_resp = perform_post(self._easy, headers, url, framed_req)
        except e:
            err = String(e)
        headers^.free()
        if len(err) > 0:
            raise Error(err)

        var split = decode_grpc_frame(framed_resp^)
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
