"""
Client-side transport abstraction.
"""

from mojo_curl import Easy, CurlList
from mo_protobuf import ProtoReader, ProtoWriter, ProtoSerializable
from mo_protobuf.common import Bytes
from mo_grpc.frame import encode_grpc_frame, decode_grpc_frame, decode_grpc_body, FRAME_HEADER_LEN
from mo_grpc.streams import GrpcServerStream, GrpcClientStream, GrpcBidiStream
from mo_grpc.transport import grpc_headers, http_post, perform_post


struct GrpcChannel(Movable):
    """A long-lived client channel."""

    var base_url: String
    var _easy: Easy

    def __init__(out self, base_url: String):
        self.base_url = base_url
        self._easy = Easy()

    def unary_unary[
        Req: ProtoSerializable & Copyable, Resp: ProtoSerializable & Copyable
    ](mut self, method: String, request: Req,) raises -> Resp:
        """Send a single request, receive a single response over HTTP/2 + TLS."""

        # Serialize directly into a buffer that already has a reserved 5-byte
        # gRPC frame header, then back-patch the length. Avoids the encode/
        # decode detour through a second `Bytes` per call.
        var writer = ProtoWriter()
        writer.buf.resize(FRAME_HEADER_LEN, UInt8(0))
        request.serialize(writer)
        var framed_request = writer.flush()

        var request_body_len = len(framed_request) - FRAME_HEADER_LEN
        var header_ptr = framed_request.unsafe_ptr()
        header_ptr[0] = UInt8(0)  # compression flag
        header_ptr[1] = UInt8((request_body_len >> 24) & 0xFF)
        header_ptr[2] = UInt8((request_body_len >> 16) & 0xFF)
        header_ptr[3] = UInt8((request_body_len >> 8) & 0xFF)
        header_ptr[4] = UInt8(request_body_len & 0xFF)

        # Send and capture the response. `headers` must be freed on every
        # path — Mojo's drop-check would otherwise refuse to compile this.
        var url = self.base_url + method
        var headers = grpc_headers()
        var framed_response = Bytes()
        var transport_err = String("")
        try:
            framed_response = perform_post(self._easy, headers, url, framed_request)
        except e:
            transport_err = String(e)
        headers^.free()
        if len(transport_err) > 0:
            raise Error(transport_err)

        # Parse the response in place: build a ProtoReader that owns the
        # entire framed buffer but starts past the 5-byte header.
        if len(framed_response) < FRAME_HEADER_LEN:
            raise Error("gRPC frame too short: " + String(len(framed_response)))

        var response_body_len = (
            (Int(framed_response[1]) << 24)
            | (Int(framed_response[2]) << 16)
            | (Int(framed_response[3]) << 8)
            | Int(framed_response[4])
        )
        if FRAME_HEADER_LEN + response_body_len > len(framed_response):
            raise Error("gRPC frame truncated")

        var reader = ProtoReader(framed_response^)
        reader.caret = FRAME_HEADER_LEN
        reader.end = FRAME_HEADER_LEN + response_body_len
        return Resp.parse(reader)

    def unary_stream[
        Req: ProtoSerializable & Copyable, Resp: ProtoSerializable & Copyable
    ](mut self, method: String, request: Req,) raises -> GrpcServerStream[Resp]:
        """Server-streaming is not yet implemented via libcurl easy handle. Requires multi handle + incremental frame decoding (TODO)."""
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
