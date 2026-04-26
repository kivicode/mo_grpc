"""HTTP/2 + TLS transport for gRPC over native sockets."""

from mo_protobuf.common import Bytes
from mo_grpc.status import GrpcError, GRPC_STATUS_DEADLINE_EXCEEDED
from mo_grpc.net import TcpSocket, parse_url, ParsedUrl
from mo_grpc.tls import TlsSocket
from mo_grpc.h2 import H2Connection


def _ascii_lower(key: String) -> String:
    var key_bytes = key.as_bytes()
    var out = Bytes()
    out.reserve(len(key_bytes))
    for i in range(len(key_bytes)):
        var byte = Int(key_bytes[i])
        if byte >= ord("A") and byte <= ord("Z"):
            byte += 32
        out.append(UInt8(byte))
    return String(unsafe_from_utf8=out^)


def _validate_metadata_key(key: String) raises:
    var key_bytes = key.as_bytes()
    if len(key_bytes) == 0:
        raise Error("metadata key must not be empty")

    if key_bytes[0] == UInt8(ord(":")):
        raise Error(
            "metadata key '" + key + "' is an HTTP/2 pseudo-header"
        )

    if key.startswith("grpc-"):
        raise Error(
            "metadata key '"
            + key
            + "' uses the reserved 'grpc-' prefix"
        )

    if key.endswith("-bin"):
        raise Error(
            "metadata key '"
            + key
            + "' is binary (-bin); binary metadata is not supported yet"
        )

    if (
        key == "content-type"
        or key == "te"
        or key == "user-agent"
        or key == "connection"
        or key == "host"
        or key == "transfer-encoding"
    ):
        raise Error("metadata key '" + key + "' is managed by mo_grpc")

    for i in range(len(key_bytes)):
        var byte = Int(key_bytes[i])
        var is_lower_alpha = byte >= ord("a") and byte <= ord("z")
        var is_digit = byte >= ord("0") and byte <= ord("9")
        var is_punct = (
            byte == ord("_") or byte == ord("-") or byte == ord(".")
        )
        if not (is_lower_alpha or is_digit or is_punct):
            raise Error(
                "metadata key '"
                + key
                + "' contains illegal character at position "
                + String(i)
            )


def _validate_metadata_value(key: String, value: String) raises:
    var value_bytes = value.as_bytes()
    for i in range(len(value_bytes)):
        var byte = Int(value_bytes[i])
        if byte < 0x20 or byte > 0x7E:
            raise Error(
                "metadata value for '"
                + key
                + "' contains non-printable byte at position "
                + String(i)
            )


def grpc_headers(
    content_type: String = "application/grpc",
    timeout_ms: Int = 0,
    metadata: Dict[String, String] = Dict[String, String](),
) raises -> Dict[String, String]:
    """Build the gRPC client header set as a Dict."""
    var entries = Dict[String, String]()
    entries[String("content-type")] = content_type
    entries[String("te")] = String("trailers")
    entries[String("user-agent")] = String("grpc-mojo/0.1")
    if timeout_ms > 0:
        entries[String("grpc-timeout")] = String(timeout_ms) + String("m")

    for entry in metadata.items():
        var normalized_key = _ascii_lower(entry.key)
        _validate_metadata_key(normalized_key)
        _validate_metadata_value(normalized_key, entry.value)
        entries[normalized_key] = entry.value

    return entries^


def perform_post(
    mut conn: H2Connection,
    path: String,
    authority: String,
    headers: Dict[String, String],
    body: Bytes,
) raises:
    """Run a single gRPC POST on an existing H2Connection.

    After return, response data is in conn.response.
    """
    var stream_id = conn.submit_request(
        method=String("POST"),
        path=path,
        authority=authority,
        headers=headers,
        body=body,
    )
    conn.run_until_stream_close(stream_id)


def connect(host: String, port: UInt16) raises -> H2Connection:
    """Establish a TLS+HTTP/2 connection to host:port."""
    var tcp = TcpSocket()
    tcp.connect(host, port)
    var fd = tcp.fd
    tcp.fd = -1
    return H2Connection(fd, host)


def http_post(
    url: String,
    body: Bytes,
    content_type: String = "application/grpc",
) raises -> Bytes:
    """One-shot POST: opens a fresh connection and discards it.

    Prefer `GrpcChannel`, which keeps a long-lived connection.
    """
    var parsed = parse_url(url)
    var host = parsed.host
    var port = parsed.port
    var path = parsed.path

    var headers = grpc_headers(content_type)
    var conn = connect(host, port)
    perform_post(conn, path, host, headers, body)
    return conn.response.body.copy()
