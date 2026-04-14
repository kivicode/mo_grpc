"""
gRPC status codes + errors.

The wire format carries a `grpc-status: <int>` HTTP/2 trailer on every reply.
Non-zero values mean the call failed and the server may also include a
`grpc-message: <text>` trailer with a human-readable description. mo_grpc
parses both and raises `GrpcError` from the client stub.

Status code values match `google.rpc.Code` and the canonical set used across
all gRPC implementations.
"""


comptime GRPC_STATUS_OK                  =  0
comptime GRPC_STATUS_CANCELLED           =  1
comptime GRPC_STATUS_UNKNOWN             =  2
comptime GRPC_STATUS_INVALID_ARGUMENT    =  3
comptime GRPC_STATUS_DEADLINE_EXCEEDED   =  4
comptime GRPC_STATUS_NOT_FOUND           =  5
comptime GRPC_STATUS_ALREADY_EXISTS      =  6
comptime GRPC_STATUS_PERMISSION_DENIED   =  7
comptime GRPC_STATUS_RESOURCE_EXHAUSTED  =  8
comptime GRPC_STATUS_FAILED_PRECONDITION =  9
comptime GRPC_STATUS_ABORTED             = 10
comptime GRPC_STATUS_OUT_OF_RANGE        = 11
comptime GRPC_STATUS_UNIMPLEMENTED       = 12
comptime GRPC_STATUS_INTERNAL            = 13
comptime GRPC_STATUS_UNAVAILABLE         = 14
comptime GRPC_STATUS_DATA_LOSS           = 15
comptime GRPC_STATUS_UNAUTHENTICATED     = 16


def grpc_status_name(code: Int) -> String:
    """Return the canonical name (`OK`, `NOT_FOUND`, …) for a status code, or `STATUS_<n>` for unknown values."""
    if code == GRPC_STATUS_OK:                  return String("OK")
    if code == GRPC_STATUS_CANCELLED:           return String("CANCELLED")
    if code == GRPC_STATUS_UNKNOWN:             return String("UNKNOWN")
    if code == GRPC_STATUS_INVALID_ARGUMENT:    return String("INVALID_ARGUMENT")
    if code == GRPC_STATUS_DEADLINE_EXCEEDED:   return String("DEADLINE_EXCEEDED")
    if code == GRPC_STATUS_NOT_FOUND:           return String("NOT_FOUND")
    if code == GRPC_STATUS_ALREADY_EXISTS:      return String("ALREADY_EXISTS")
    if code == GRPC_STATUS_PERMISSION_DENIED:   return String("PERMISSION_DENIED")
    if code == GRPC_STATUS_RESOURCE_EXHAUSTED:  return String("RESOURCE_EXHAUSTED")
    if code == GRPC_STATUS_FAILED_PRECONDITION: return String("FAILED_PRECONDITION")
    if code == GRPC_STATUS_ABORTED:             return String("ABORTED")
    if code == GRPC_STATUS_OUT_OF_RANGE:        return String("OUT_OF_RANGE")
    if code == GRPC_STATUS_UNIMPLEMENTED:       return String("UNIMPLEMENTED")
    if code == GRPC_STATUS_INTERNAL:            return String("INTERNAL")
    if code == GRPC_STATUS_UNAVAILABLE:         return String("UNAVAILABLE")
    if code == GRPC_STATUS_DATA_LOSS:           return String("DATA_LOSS")
    if code == GRPC_STATUS_UNAUTHENTICATED:     return String("UNAUTHENTICATED")
    return String("STATUS_") + String(code)


@fieldwise_init
struct GrpcError(Copyable, Movable, Writable):
    """Structured gRPC failure raised when the server returns a non-OK status."""

    var code: Int
    var message: String

    def __init__(out self, code: Int):
        self.code = code
        self.message = String("")

    def write_to(self, mut writer: Some[Writer]):
        writer.write("GrpcError(", grpc_status_name(self.code))
        writer.write("=", String(self.code))

        if len(self.message) > 0:
            writer.write(": ", self.message)

        writer.write(")")

    def to_error(self) -> Error:
        var name = grpc_status_name(self.code)

        if len(self.message) > 0:
            return Error("gRPC " + name + " (" + String(self.code) + "): " + self.message)

        return Error("gRPC " + name + " (" + String(self.code) + ")")
