"""gRPC stream handles for the four streaming combinations."""

from std.memory import UnsafePointer, memcpy
from mo_protobuf import ProtoReader, ProtoWriter, ProtoSerializable
from mo_protobuf.common import Bytes
from mo_grpc.frame import FRAME_HEADER_LEN, encode_grpc_frame
from mo_grpc.status import GrpcError, GRPC_STATUS_OK, GRPC_STATUS_UNKNOWN, GRPC_STATUS_CANCELLED
from mo_grpc.h2 import H2_CANCEL
from mo_grpc.h2 import H2Connection


fn _try_extract_grpc_frame(mut buf: Bytes) -> Optional[Bytes]:
    """Try to extract one complete gRPC frame from buf.
    Returns the body if a complete frame is available, else None."""
    if len(buf) < FRAME_HEADER_LEN:
        return None

    var body_len = (
        (Int(buf[1]) << 24) | (Int(buf[2]) << 16)
        | (Int(buf[3]) << 8) | Int(buf[4])
    )
    var frame_len = FRAME_HEADER_LEN + body_len
    if len(buf) < frame_len:
        return None

    var body = Bytes()
    body.resize(body_len, UInt8(0))
    if body_len > 0:
        memcpy(dest=body.unsafe_ptr(), src=buf.unsafe_ptr() + FRAME_HEADER_LEN, count=body_len)

    var remaining = len(buf) - frame_len
    if remaining > 0:
        var new_buf = Bytes()
        new_buf.resize(remaining, UInt8(0))
        memcpy(dest=new_buf.unsafe_ptr(), src=buf.unsafe_ptr() + frame_len, count=remaining)
        buf = new_buf^
    else:
        buf = Bytes()

    return body^


fn _serialize_grpc_frame[Req: ProtoSerializable & Copyable](request: Req) raises -> Bytes:
    var writer = ProtoWriter()
    writer.buf.resize(FRAME_HEADER_LEN, UInt8(0))
    request.serialize(writer)
    var framed = writer.flush()
    var body_len = len(framed) - FRAME_HEADER_LEN
    var ptr = framed.unsafe_ptr()
    ptr[0] = UInt8(0)
    ptr[1] = UInt8((body_len >> 24) & 0xFF)
    ptr[2] = UInt8((body_len >> 16) & 0xFF)
    ptr[3] = UInt8((body_len >> 8) & 0xFF)
    ptr[4] = UInt8(body_len & 0xFF)
    return framed^


fn _check_rst_stream(ev_is_rst: Bool, rst_code: Int) raises:
    """If the event is RST_STREAM, raise the appropriate GrpcError."""
    if ev_is_rst:
        if rst_code == H2_CANCEL:
            raise GrpcError(GRPC_STATUS_CANCELLED, String("stream cancelled by peer")).to_error()
        raise GrpcError(GRPC_STATUS_UNKNOWN, String("RST_STREAM error code ") + String(rst_code)).to_error()


fn _check_trailers(trailers: Dict[String, String]) raises:
    var status_opt = trailers.get(String("grpc-status"))
    if not status_opt:
        raise GrpcError(GRPC_STATUS_UNKNOWN, String("missing grpc-status trailer")).to_error()
    var code = Int(atol(status_opt.value()))
    if code == GRPC_STATUS_OK:
        return
    var msg_opt = trailers.get(String("grpc-message"))
    var msg = msg_opt.value() if msg_opt else String("")
    raise GrpcError(code, msg^).to_error()


def _deserialize[Resp: ProtoSerializable & Copyable](body: Bytes) raises -> Resp:
    var b = body.copy()
    var reader = ProtoReader(b^)
    return Resp.parse(reader)


fn _append_bytes(mut dst: Bytes, src: Bytes):
    var start = len(dst)
    dst.resize(start + len(src), UInt8(0))
    if len(src) > 0:
        memcpy(dest=dst.unsafe_ptr() + start, src=src.unsafe_ptr(), count=len(src))


struct GrpcServerStream[Resp: ProtoSerializable & Copyable]:
    """A server-streaming call: client sent one request, server sends many responses."""

    var _conn: UnsafePointer[H2Connection, MutExternalOrigin]
    var _stream_id: Int
    var _buf: Bytes
    var _done: Bool
    var _trailers: Dict[String, String]

    fn __init__(out self, conn: UnsafePointer[H2Connection, MutExternalOrigin], stream_id: Int):
        self._conn = conn
        self._stream_id = stream_id
        self._buf = Bytes()
        self._done = False
        self._trailers = Dict[String, String]()

    def recv(mut self) raises -> Optional[Self.Resp]:
        """Returns the next response, or None when the stream is complete."""
        var frame_body = _try_extract_grpc_frame(self._buf)
        if frame_body:
            return _deserialize[Self.Resp](frame_body.value())

        if self._done:
            _check_trailers(self._trailers)
            return None

        while True:
            var ev = self._conn[].read_next_event(self._stream_id)
            _check_rst_stream(ev.is_rst_stream, ev.rst_error_code)
            if ev.is_data:
                _append_bytes(self._buf, ev.data)
                if ev.is_end_stream:
                    self._done = True
                frame_body = _try_extract_grpc_frame(self._buf)
                if frame_body:
                    return _deserialize[Self.Resp](frame_body.value())
                if self._done:
                    _check_trailers(self._trailers)
                    return None
            elif ev.is_trailers:
                self._trailers = ev.trailers.copy()
                if ev.is_end_stream:
                    self._done = True
                    frame_body = _try_extract_grpc_frame(self._buf)
                    if frame_body:
                        return _deserialize[Self.Resp](frame_body.value())
                    _check_trailers(self._trailers)
                    return None

    def cancel(mut self) raises:
        """Cancel the stream by sending RST_STREAM."""
        self._conn[].cancel_stream(self._stream_id)
        self._done = True


struct GrpcClientStream[Req: ProtoSerializable & Copyable, Resp: ProtoSerializable & Copyable]:
    """A client-streaming call: client sends many requests, server sends one response."""

    var _conn: UnsafePointer[H2Connection, MutExternalOrigin]
    var _stream_id: Int

    fn __init__(out self, conn: UnsafePointer[H2Connection, MutExternalOrigin], stream_id: Int):
        self._conn = conn
        self._stream_id = stream_id

    def send(mut self, msg: Self.Req) raises:
        var framed = _serialize_grpc_frame(msg)
        self._conn[].send_data_frame(self._stream_id, framed, end_stream=False)

    def close_and_recv(mut self) raises -> Self.Resp:
        self._conn[].send_data_frame(self._stream_id, Bytes(), end_stream=True)

        var response_body = Bytes()
        var trailers = Dict[String, String]()
        var got_initial_headers = False

        while True:
            var ev = self._conn[].read_next_event(self._stream_id)
            if ev.is_data:
                _append_bytes(response_body, ev.data)
            elif ev.is_trailers:
                if not got_initial_headers:
                    got_initial_headers = True
                else:
                    trailers = ev.trailers.copy()
            if ev.is_end_stream:
                break

        _check_trailers(trailers)

        if len(response_body) < FRAME_HEADER_LEN:
            raise Error("gRPC frame too short: " + String(len(response_body)))

        var body_len = (
            (Int(response_body[1]) << 24) | (Int(response_body[2]) << 16)
            | (Int(response_body[3]) << 8) | Int(response_body[4])
        )
        var reader = ProtoReader(response_body^)
        reader.caret = FRAME_HEADER_LEN
        reader.end = FRAME_HEADER_LEN + body_len
        return Self.Resp.parse(reader)


struct GrpcBidiStream[Req: ProtoSerializable & Copyable, Resp: ProtoSerializable & Copyable]:
    """A bidirectional streaming call: both sides send many messages."""

    var _conn: UnsafePointer[H2Connection, MutExternalOrigin]
    var _stream_id: Int
    var _buf: Bytes
    var _recv_done: Bool
    var _trailers: Dict[String, String]

    fn __init__(out self, conn: UnsafePointer[H2Connection, MutExternalOrigin], stream_id: Int):
        self._conn = conn
        self._stream_id = stream_id
        self._buf = Bytes()
        self._recv_done = False
        self._trailers = Dict[String, String]()

    def send(mut self, msg: Self.Req) raises:
        var framed = _serialize_grpc_frame(msg)
        self._conn[].send_data_frame(self._stream_id, framed, end_stream=False)

    def recv(mut self) raises -> Optional[Self.Resp]:
        var frame_body = _try_extract_grpc_frame(self._buf)
        if frame_body:
            return _deserialize[Self.Resp](frame_body.value())

        if self._recv_done:
            _check_trailers(self._trailers)
            return None

        while True:
            var ev = self._conn[].read_next_event(self._stream_id)
            _check_rst_stream(ev.is_rst_stream, ev.rst_error_code)
            if ev.is_data:
                _append_bytes(self._buf, ev.data)
                if ev.is_end_stream:
                    self._recv_done = True
                frame_body = _try_extract_grpc_frame(self._buf)
                if frame_body:
                    return _deserialize[Self.Resp](frame_body.value())
                if self._recv_done:
                    _check_trailers(self._trailers)
                    return None
            elif ev.is_trailers:
                self._trailers = ev.trailers.copy()
                if ev.is_end_stream:
                    self._recv_done = True
                    frame_body = _try_extract_grpc_frame(self._buf)
                    if frame_body:
                        return _deserialize[Self.Resp](frame_body.value())
                    _check_trailers(self._trailers)
                    return None

    def close_send(mut self) raises:
        self._conn[].send_data_frame(self._stream_id, Bytes(), end_stream=True)

    def cancel(mut self) raises:
        """Cancel the stream by sending RST_STREAM."""
        self._conn[].cancel_stream(self._stream_id)
        self._recv_done = True
