"""gRPC server runtime. Accepts connections and dispatches to handlers."""

from std.memory import UnsafePointer, memcpy
from mo_protobuf import ProtoReader, ProtoWriter, ProtoSerializable
from mo_protobuf.common import Bytes
from mo_grpc.net import ListenSocket, TcpSocket, c_void
from mo_grpc.tls import ServerTlsSocket
from mo_grpc.h2 import H2ServerConnection, H2Request
from mo_grpc.frame import FRAME_HEADER_LEN as GRPC_FRAME_HEADER_LEN
from mo_grpc.status import GRPC_STATUS_OK, GRPC_STATUS_UNIMPLEMENTED, GRPC_STATUS_INTERNAL


@fieldwise_init
struct ServiceRoute(Copyable, Movable):
    """A registered service handler: method path."""
    var path: String


struct GrpcServer:
    """Single-threaded gRPC server over HTTP/2 + TLS."""

    var listen_socket: ListenSocket
    var cert_path: String
    var key_path: String
    var ca_path: String
    var _handlers: List[ServiceRoute]

    fn __init__(
        out self,
        host: String,
        port: UInt16,
        cert_path: String,
        key_path: String,
        ca_path: String = String(""),
    ) raises:
        self.listen_socket = ListenSocket(host, port)
        self.cert_path = cert_path
        self.key_path = key_path
        self.ca_path = ca_path
        self._handlers = List[ServiceRoute]()

    fn serve_one(mut self) raises:
        """Accept one connection and serve all requests on it until it closes."""
        var client = self.listen_socket.accept()
        var fd = client.fd
        client.fd = -1

        var conn = H2ServerConnection(fd, self.cert_path, self.key_path, self.ca_path)
        self._serve_connection(conn)

    fn serve_forever(mut self) raises:
        """Accept connections in a loop, serving each sequentially."""
        while True:
            try:
                self.serve_one()
            except e:
                var err = String(e)
                if err.startswith("connection closed"):
                    continue
                raise Error(err)

    fn _serve_connection(self, mut conn: H2ServerConnection) raises:
        """Serve all requests on a single connection."""
        while True:
            var req: H2Request
            try:
                req = conn.read_request()
            except:
                return

            # Dispatch to registered handler
            var handled = False
            for i in range(len(self._handlers)):
                if self._handlers[i].path == req.path:
                    handled = True
                    try:
                        self._dispatch_unary(conn, req, i)
                    except e:
                        try:
                            conn.send_error(req.stream_id, GRPC_STATUS_INTERNAL, String(e))
                        except:
                            return
                    break

            if not handled:
                try:
                    conn.send_error(req.stream_id, GRPC_STATUS_UNIMPLEMENTED, String("unknown method: ") + req.path)
                except:
                    return

    fn _dispatch_unary(
        self,
        mut conn: H2ServerConnection,
        req: H2Request,
        handler_idx: Int,
    ) raises:
        """Call a unary handler and send the response."""
        # The handler is stored as a function pointer that takes (body) -> (status, response_body)
        # For now, this is a placeholder — the real dispatch uses register_unary below
        pass


fn _make_grpc_frame(body: Bytes) -> Bytes:
    """Wrap a serialized protobuf body in a 5-byte gRPC frame."""
    var frame = Bytes()
    var body_len = len(body)
    frame.resize(GRPC_FRAME_HEADER_LEN + body_len, UInt8(0))
    var ptr = frame.unsafe_ptr()
    ptr[0] = UInt8(0)  # compression flag
    ptr[1] = UInt8((body_len >> 24) & 0xFF)
    ptr[2] = UInt8((body_len >> 16) & 0xFF)
    ptr[3] = UInt8((body_len >> 8) & 0xFF)
    ptr[4] = UInt8(body_len & 0xFF)
    if body_len > 0:
        memcpy(dest=ptr + GRPC_FRAME_HEADER_LEN, src=body.unsafe_ptr(), count=body_len)
    return frame^


fn _extract_grpc_body(data: Bytes) raises -> Bytes:
    """Extract protobuf body from a gRPC frame."""
    if len(data) < GRPC_FRAME_HEADER_LEN:
        raise Error("gRPC frame too short")
    var body_len = (
        (Int(data[1]) << 24) | (Int(data[2]) << 16)
        | (Int(data[3]) << 8) | Int(data[4])
    )
    var body = Bytes()
    body.resize(body_len, UInt8(0))
    if body_len > 0:
        memcpy(dest=body.unsafe_ptr(), src=data.unsafe_ptr() + GRPC_FRAME_HEADER_LEN, count=body_len)
    return body^


def serve_unary(
    mut conn: H2ServerConnection,
    req: H2Request,
    handler: fn (Bytes) raises -> Bytes,
) raises:
    """Serve a single unary RPC. Handler receives raw protobuf body, returns raw protobuf body."""
    var body = _extract_grpc_body(req.body)
    var resp_body = handler(body)
    var framed = _make_grpc_frame(resp_body^)
    conn.send_response(req.stream_id, GRPC_STATUS_OK, String(""), framed)


struct ServerStreamWriter:
    """Passed to server-streaming handlers to send response messages."""
    var _conn: UnsafePointer[H2ServerConnection, MutExternalOrigin]
    var _stream_id: Int
    var _sent_headers: Bool

    fn __init__(out self, conn: UnsafePointer[H2ServerConnection, MutExternalOrigin], stream_id: Int):
        self._conn = conn
        self._stream_id = stream_id
        self._sent_headers = False

    fn send[Resp: ProtoSerializable & Copyable](mut self, msg: Resp) raises:
        if not self._sent_headers:
            self._conn[].send_initial_headers(self._stream_id)
            self._sent_headers = True
        var writer = ProtoWriter()
        msg.serialize(writer)
        var body = writer.flush()
        var framed = _make_grpc_frame(body^)
        self._conn[].send_data_frame(self._stream_id, framed, end_stream=False)

    fn finish(mut self, status_code: Int = GRPC_STATUS_OK, message: String = String("")) raises:
        if not self._sent_headers:
            self._conn[].send_initial_headers(self._stream_id)
            self._sent_headers = True
        self._conn[].send_trailers(self._stream_id, status_code, message)
