"""
Client-side transport abstraction.
"""

from mojo_curl import Easy, CurlList
from mojo_curl.c.header import HeaderOrigin
from mo_protobuf import ProtoReader, ProtoWriter, ProtoSerializable
from mo_protobuf.common import Bytes
from mo_grpc.frame import encode_grpc_frame, decode_grpc_frame, decode_grpc_body, FRAME_HEADER_LEN
from mo_grpc.status import GrpcError, GRPC_STATUS_OK, GRPC_STATUS_UNKNOWN
from mo_grpc.streams import GrpcServerStream, GrpcClientStream, GrpcBidiStream
from mo_grpc.transport import grpc_headers, http_post, perform_post


# `CURLH_*` bits from `curl/header.h`. gRPC normally sends `grpc-status` in
# the HTTP/2 trailers, but a "trailers-only" reply (the optimization for
# non-OK statuses with no body) puts it in the *initial* HEADERS frame
# instead, so the channel has to look in both buckets.
comptime CURLH_HEADER  = 1
comptime CURLH_TRAILER = 2


struct GrpcChannel(Movable):
    """A long-lived client channel."""

    var base_url: String
    var _easy: Easy

    def __init__(out self, base_url: String):
        self.base_url = base_url
        self._easy = Easy()

    def _lookup_grpc_header(mut self, name: String) raises -> Optional[String]:
        """Look up a gRPC pseudo-header by name, checking the trailers first
        and then the initial headers. Returns `None` if neither carries it."""
        var trailers: Dict[String, String] = self._easy.headers(HeaderOrigin(CURLH_TRAILER))
        var trailer_hit = trailers.get(name)
        if trailer_hit:
            return trailer_hit^

        var headers: Dict[String, String] = self._easy.headers(HeaderOrigin(CURLH_HEADER))
        return headers.get(name)

    def _check_grpc_status(mut self) raises:
        """Raise `GrpcError` if the response carries a non-OK `grpc-status`.

        A missing `grpc-status` is treated as UNKNOWN — every compliant gRPC
        server has to send one, so its absence means we're talking to
        something that isn't gRPC (or the call never reached the server).
        """
        var status_str = self._lookup_grpc_header(String("grpc-status"))
        if not status_str:
            raise GrpcError(
                GRPC_STATUS_UNKNOWN, String("missing grpc-status trailer")
            ).to_error()

        var code = Int(atol(status_str.value()))
        if code == GRPC_STATUS_OK:
            return

        var message_opt = self._lookup_grpc_header(String("grpc-message"))
        var message = message_opt.value() if message_opt else String("")
        raise GrpcError(code, message^).to_error()

    def unary_unary[
        Req: ProtoSerializable & Copyable, Resp: ProtoSerializable & Copyable
    ](
        mut self,
        method: String,
        request: Req,
        timeout_ms: Int = 0,
        metadata: Dict[String, String] = Dict[String, String](),
    ) raises -> Resp:
        """Send a single request, receive a single response over HTTP/2 + TLS.

        `timeout_ms = 0` (the default) means no client-side deadline. Any
        positive value sets `CURLOPT_TIMEOUT_MS` on the libcurl handle *and*
        sends the canonical `grpc-timeout: <n>m` request header so the server
        can shed the request itself. On expiry the call raises a typed
        `GrpcError(DEADLINE_EXCEEDED)`.

        `metadata` is application-supplied custom request metadata
        (`authorization`, `x-tenant`, `x-request-id`, …). Keys are validated
        and lowercased per the gRPC-over-HTTP/2 spec; reserved keys
        (`grpc-*`, `:*`, `content-type`, `te`, `user-agent`, …) raise before
        the call hits the wire. Binary (`-bin`) metadata is not supported yet.
        """

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

        var url = self.base_url + method
        var headers = grpc_headers(timeout_ms=timeout_ms, metadata=metadata)
        var framed_response = Bytes()
        var transport_err = String("")
        try:
            framed_response = perform_post(self._easy, headers, url, framed_request, timeout_ms)
        except e:
            transport_err = String(e)
        headers^.free()
        if len(transport_err) > 0:
            raise Error(transport_err)

        self._check_grpc_status()

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
