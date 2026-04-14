"""End-to-end test for `grpc-status` trailer parsing.

Hits the local Python `StatusProbe` server (started by `bench/run.sh`) and
asserts:
  * an OK reply round-trips the body unchanged
  * non-OK replies raise `GrpcError` with the right code + message
  * a missing-status trailer would surface as UNKNOWN (covered indirectly)

Run via:
  bash bench/run.sh        # builds + runs as part of the harness
  ./bench/test_status      # standalone, server must already be up
"""

from mo_grpc import GrpcChannel, GrpcError
from mo_grpc.status import (
    GRPC_STATUS_OK,
    GRPC_STATUS_INVALID_ARGUMENT,
    GRPC_STATUS_NOT_FOUND,
    GRPC_STATUS_PERMISSION_DENIED,
    GRPC_STATUS_RESOURCE_EXHAUSTED,
    GRPC_STATUS_UNAUTHENTICATED,
    grpc_status_name,
)
from status_probe import StatusProbeStub, StatusRequest, StatusReply


def make_request(code: Int, message: String, echo: String) -> StatusRequest:
    var request = StatusRequest()
    request.code = Int32(code)
    request.message = message
    request.echo = echo
    return request^


def expect_ok(mut stub: StatusProbeStub, echo: String) raises:
    var reply = stub.Run(make_request(GRPC_STATUS_OK, String(""), echo))
    var got = reply.echo.value() if reply.echo else String("")
    if got != echo:
        raise Error(
            "OK echo mismatch: expected '"
            + echo
            + "', got '"
            + got
            + "'"
        )
    print("  PASS OK round-trips body (echo='" + echo + "')")


def expect_status(
    mut stub: StatusProbeStub,
    code: Int,
    message: String,
) raises:
    var saw_error = False
    var error_text = String("")
    try:
        _ = stub.Run(make_request(code, message, String("")))
    except e:
        saw_error = True
        error_text = String(e)

    if not saw_error:
        raise Error(
            "expected GrpcError "
            + grpc_status_name(code)
            + " but call returned normally"
        )

    var expected_name = grpc_status_name(code)
    if expected_name not in error_text:
        raise Error(
            "expected error to mention "
            + expected_name
            + " — got: "
            + error_text
        )
    if len(message) > 0 and message not in error_text:
        raise Error(
            "expected error to carry message '"
            + message
            + "' — got: "
            + error_text
        )
    print(
        "  PASS "
        + expected_name
        + " (code="
        + String(code)
        + ") raises GrpcError with message='"
        + message
        + "'"
    )


def main() raises:
    var stub = StatusProbeStub(GrpcChannel(String("https://localhost:50443")))

    print("=== grpc-status trailer parsing ===")

    expect_ok(stub, String("hello, world"))
    expect_ok(stub, String("second OK call reuses the connection"))

    expect_status(stub, GRPC_STATUS_INVALID_ARGUMENT, String("bad input"))
    expect_status(stub, GRPC_STATUS_NOT_FOUND, String("nope"))
    expect_status(stub, GRPC_STATUS_PERMISSION_DENIED, String("denied"))
    expect_status(stub, GRPC_STATUS_RESOURCE_EXHAUSTED, String("over quota"))
    expect_status(stub, GRPC_STATUS_UNAUTHENTICATED, String("who are you"))

    # After several errors, the channel should still be healthy: a fresh OK
    # call must round-trip on the same Easy handle / TLS connection.
    expect_ok(stub, String("OK after errors"))

    print("\nall status-trailer assertions passed")
