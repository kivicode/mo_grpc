"""Client-side gRPC channel over native HTTP/2 + TLS."""

from mo_protobuf import ProtoReader, ProtoWriter, ProtoSerializable
from mo_protobuf.common import Bytes
from mo_grpc.frame import encode_grpc_frame, decode_grpc_frame, decode_grpc_body, FRAME_HEADER_LEN
from mo_grpc.status import GrpcError, GRPC_STATUS_OK, GRPC_STATUS_UNKNOWN, GRPC_STATUS_DEADLINE_EXCEEDED
from mo_grpc.streams import GrpcServerStream, GrpcClientStream, GrpcBidiStream
from mo_grpc.transport import grpc_headers, perform_post, connect
from mo_grpc.net import parse_url, ParsedUrl, TcpSocket
from mo_grpc.h2 import H2Connection


struct GrpcChannel(Movable):
    """A long-lived client channel that pools a TCP/TLS/HTTP2 connection."""

    var base_url: String
    var _host: String
    var _port: UInt16
    var _conn: Optional[H2Connection]

    def __init__(out self, base_url: String) raises:
        self.base_url = base_url
        var parsed = parse_url(base_url)
        self._host = parsed.host
        self._port = parsed.port
        self._conn = None

    fn __moveinit__(out self: GrpcChannel, deinit take: GrpcChannel):
        self.base_url = take.base_url^
        self._host = take._host^
        self._port = take._port
        self._conn = take._conn^

    def _ensure_connected(mut self) raises:
        if not self._conn:
            self._conn = connect(self._host, self._port)

    def _lookup_grpc_header(
        self,
        name: String,
        headers: Dict[String, String],
        trailers: Dict[String, String],
    ) -> Optional[String]:
        var trailer_hit = trailers.get(name)
        if trailer_hit:
            return trailer_hit^
        return headers.get(name)

    def _check_grpc_status(
        self,
        headers: Dict[String, String],
        trailers: Dict[String, String],
    ) raises:
        var status_str = self._lookup_grpc_header(String("grpc-status"), headers, trailers)
        if not status_str:
            raise GrpcError(
                GRPC_STATUS_UNKNOWN, String("missing grpc-status trailer")
            ).to_error()

        var code = Int(atol(status_str.value()))
        if code == GRPC_STATUS_OK:
            return

        var message_opt = self._lookup_grpc_header(String("grpc-message"), headers, trailers)
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
        """Send a single request, receive a single response over HTTP/2 + TLS."""

        var writer = ProtoWriter()
        writer.buf.resize(FRAME_HEADER_LEN, UInt8(0))
        request.serialize(writer)
        var framed_request = writer.flush()

        var request_body_len = len(framed_request) - FRAME_HEADER_LEN
        var header_ptr = framed_request.unsafe_ptr()
        header_ptr[0] = UInt8(0)
        header_ptr[1] = UInt8((request_body_len >> 24) & 0xFF)
        header_ptr[2] = UInt8((request_body_len >> 16) & 0xFF)
        header_ptr[3] = UInt8((request_body_len >> 8) & 0xFF)
        header_ptr[4] = UInt8(request_body_len & 0xFF)

        var path = method
        var hdrs = grpc_headers(timeout_ms=timeout_ms, metadata=metadata)

        self._ensure_connected()

        if timeout_ms > 0:
            self._conn.value().tls.tcp.set_timeout(timeout_ms)

        try:
            perform_post(self._conn.value(), path, self._host, hdrs, framed_request)
        except e:
            var err_str = String(e)
            self._conn = None
            if err_str.startswith("deadline_exceeded:") or (
                timeout_ms > 0 and (
                    err_str.startswith("connection closed") or
                    String("SSL_read failed") in err_str
                )
            ):
                raise GrpcError(
                    GRPC_STATUS_DEADLINE_EXCEEDED,
                    String("client deadline exceeded after ") + String(timeout_ms) + String("ms"),
                ).to_error()
            raise Error(err_str)
        var framed_response = self._conn.value().response.body.copy()
        var resp_headers = self._conn.value().response.headers.copy()
        var resp_trailers = self._conn.value().response.trailers.copy()

        self._check_grpc_status(resp_headers, resp_trailers)

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
    ](
        mut self,
        method: String,
        request: Req,
        timeout_ms: Int = 0,
        metadata: Dict[String, String] = Dict[String, String](),
    ) raises -> GrpcServerStream[Resp]:
        """Server-streaming: send one request, receive many responses."""
        # Frame the request
        var writer = ProtoWriter()
        writer.buf.resize(FRAME_HEADER_LEN, UInt8(0))
        request.serialize(writer)
        var framed_request = writer.flush()
        var request_body_len = len(framed_request) - FRAME_HEADER_LEN
        var hp = framed_request.unsafe_ptr()
        hp[0] = UInt8(0)
        hp[1] = UInt8((request_body_len >> 24) & 0xFF)
        hp[2] = UInt8((request_body_len >> 16) & 0xFF)
        hp[3] = UInt8((request_body_len >> 8) & 0xFF)
        hp[4] = UInt8(request_body_len & 0xFF)

        var hdrs = grpc_headers(timeout_ms=timeout_ms, metadata=metadata)
        self._ensure_connected()

        if timeout_ms > 0:
            self._conn.value().tls.tcp.set_timeout(timeout_ms)

        # submit_request sends HEADERS + DATA with END_STREAM (unary request)
        var stream_id = self._conn.value().submit_request(
            method=String("POST"), path=method, authority=self._host,
            headers=hdrs, body=framed_request,
        )

        # Read the initial response HEADERS (status, content-type)
        var ev = self._conn.value().read_next_event(stream_id)
        if ev.is_trailers:
            self._conn.value().response.headers = ev.trailers.copy()

        return GrpcServerStream[Resp](
            UnsafePointer[H2Connection, MutExternalOrigin](unsafe_from_address=Int(UnsafePointer(to=self._conn.value()))), stream_id
        )

    def stream_unary[
        Req: ProtoSerializable & Copyable, Resp: ProtoSerializable & Copyable
    ](
        mut self,
        method: String,
        timeout_ms: Int = 0,
        metadata: Dict[String, String] = Dict[String, String](),
    ) raises -> GrpcClientStream[Req, Resp]:
        """Client-streaming: send many requests, receive one response."""
        var hdrs = grpc_headers(timeout_ms=timeout_ms, metadata=metadata)
        self._ensure_connected()

        if timeout_ms > 0:
            self._conn.value().tls.tcp.set_timeout(timeout_ms)

        # Send HEADERS only (no END_STREAM, client will send data later)
        var stream_id = self._conn.value().send_headers_only(
            method=String("POST"), path=method, authority=self._host, headers=hdrs,
        )

        return GrpcClientStream[Req, Resp](
            UnsafePointer[H2Connection, MutExternalOrigin](unsafe_from_address=Int(UnsafePointer(to=self._conn.value()))), stream_id
        )

    def bidi[
        Req: ProtoSerializable & Copyable, Resp: ProtoSerializable & Copyable
    ](
        mut self,
        method: String,
        timeout_ms: Int = 0,
        metadata: Dict[String, String] = Dict[String, String](),
    ) raises -> GrpcBidiStream[Req, Resp]:
        """Bidi-streaming: both sides send many messages."""
        var hdrs = grpc_headers(timeout_ms=timeout_ms, metadata=metadata)
        self._ensure_connected()

        if timeout_ms > 0:
            self._conn.value().tls.tcp.set_timeout(timeout_ms)

        var stream_id = self._conn.value().send_headers_only(
            method=String("POST"), path=method, authority=self._host, headers=hdrs,
        )

        return GrpcBidiStream[Req, Resp](
            UnsafePointer[H2Connection, MutExternalOrigin](unsafe_from_address=Int(UnsafePointer(to=self._conn.value()))), stream_id
        )
