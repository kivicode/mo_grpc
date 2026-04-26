"""gRPC server runtime.

Example usage:

    fn echo_handler(body: Bytes) raises -> Bytes:
        # deserialize request, process, serialize response
        ...

    var server = GrpcServer("127.0.0.1", 50443, "cert.pem", "key.pem")
    server.add_route("/echo.Echo/Ping", echo_handler)
    server.serve_forever()
"""

from std.memory import UnsafePointer, memcpy
from mo_protobuf import ProtoReader, ProtoWriter, ProtoSerializable
from mo_protobuf.common import Bytes
from mo_grpc.net import ListenSocket, TcpSocket, c_void
from mo_grpc.tls import ServerTlsSocket
from mo_grpc.h2 import H2ServerConnection, H2Request
from mo_grpc.frame import FRAME_HEADER_LEN as GRPC_FRAME_HEADER_LEN
from mo_grpc.status import GRPC_STATUS_OK, GRPC_STATUS_UNIMPLEMENTED, GRPC_STATUS_INTERNAL


# Handler type: raw protobuf bytes in → raw protobuf bytes out.
# Users deserialize/serialize inside the handler.
comptime UnaryHandler = fn (Bytes) raises -> Bytes


fn _make_grpc_frame(body: Bytes) -> Bytes:
    var frame = Bytes()
    var body_len = len(body)
    frame.resize(GRPC_FRAME_HEADER_LEN + body_len, UInt8(0))
    var ptr = frame.unsafe_ptr()
    ptr[0] = UInt8(0)
    ptr[1] = UInt8((body_len >> 24) & 0xFF)
    ptr[2] = UInt8((body_len >> 16) & 0xFF)
    ptr[3] = UInt8((body_len >> 8) & 0xFF)
    ptr[4] = UInt8(body_len & 0xFF)
    if body_len > 0:
        memcpy(dest=ptr + GRPC_FRAME_HEADER_LEN, src=body.unsafe_ptr(), count=body_len)
    return frame^


fn _extract_grpc_body(data: Bytes) raises -> Bytes:
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


@fieldwise_init
struct _Route(Copyable, Movable):
    var path: String
    var handler: UnaryHandler


struct GrpcServer:
    """Single-threaded gRPC server over HTTP/2 + TLS.

    Usage:
        var server = GrpcServer("127.0.0.1", 50443, "cert.pem", "key.pem")
        server.add_route("/package.Service/Method", handler_fn)
        server.serve_forever()

    Handler signature: fn(Bytes) raises -> Bytes
    (receives raw protobuf body, returns raw protobuf response body)
    """

    var _listener: ListenSocket
    var _cert_path: String
    var _key_path: String
    var _ca_path: String
    var _routes: List[_Route]

    fn __init__(
        out self,
        host: String,
        port: UInt16,
        cert_path: String,
        key_path: String,
        ca_path: String = String(""),
    ) raises:
        self._listener = ListenSocket(host, port)
        self._cert_path = cert_path
        self._key_path = key_path
        self._ca_path = ca_path
        self._routes = List[_Route]()

    fn add_route(mut self, path: String, handler: UnaryHandler):
        """Register a unary RPC handler for the given method path."""
        self._routes.append(_Route(path, handler))

    fn serve_one(mut self) raises:
        """Accept one connection and serve all requests until it closes."""
        var client = self._listener.accept()
        var fd = client.fd
        client.fd = -1
        var conn = H2ServerConnection(fd, self._cert_path, self._key_path, self._ca_path)
        self._serve_connection(conn)

    fn serve_forever(mut self) raises:
        """Accept connections in a loop, serving each sequentially."""
        while True:
            try:
                self.serve_one()
            except e:
                var err = String(e)
                if err.startswith("connection closed") or err.startswith("SSL_accept"):
                    continue
                raise Error(err)

    fn _serve_connection(self, mut conn: H2ServerConnection) raises:
        while True:
            var req: H2Request
            try:
                req = conn.read_request()
            except:
                return

            var handled = False
            for i in range(len(self._routes)):
                if self._routes[i].path == req.path:
                    handled = True
                    try:
                        var body = _extract_grpc_body(req.body)
                        var resp_body = self._routes[i].handler(body)
                        var framed = _make_grpc_frame(resp_body^)
                        conn.send_response(req.stream_id, GRPC_STATUS_OK, String(""), framed)
                    except e:
                        try:
                            conn.send_error(req.stream_id, GRPC_STATUS_INTERNAL, String(e))
                        except:
                            return
                    break

            if not handled:
                try:
                    conn.send_error(
                        req.stream_id, GRPC_STATUS_UNIMPLEMENTED,
                        String("unknown method: ") + req.path
                    )
                except:
                    return
