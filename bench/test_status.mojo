"""End-to-end tests for `grpc-status` trailer parsing and client deadlines.

Hits the local Python `StatusProbe` server (started by `bench/run.sh`) and
asserts:
  * an OK reply round-trips the body unchanged
  * non-OK replies raise `GrpcError` with the right code + message
  * a slow server beyond the client deadline raises DEADLINE_EXCEEDED
  * the channel is reusable after both error and timeout paths

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
    GRPC_STATUS_DEADLINE_EXCEEDED,
    grpc_status_name,
)
from status_probe import StatusProbeStub, StatusRequest, StatusReply


def make_request(
    code: Int,
    message: String,
    echo: String,
    delay_ms: Int = 0,
) -> StatusRequest:
    var request = StatusRequest()
    request.code = Int32(code)
    request.message = message
    request.echo = echo
    request.delay_ms = Int32(delay_ms)
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


def expect_deadline_exceeded(
    mut stub: StatusProbeStub,
    timeout_ms: Int,
    delay_ms: Int,
) raises:
    """Call the server with a delay > timeout and assert the client raises
    DEADLINE_EXCEEDED. We don't assert on wall-clock here — Mojo's perf_counter
    isn't worth the extra surface area; libcurl's own timeout is enough.
    """
    var saw_error = False
    var error_text = String("")
    try:
        _ = stub.Run(
            make_request(
                GRPC_STATUS_OK,
                String(""),
                String("should never arrive"),
                delay_ms,
            ),
            timeout_ms,
        )
    except e:
        saw_error = True
        error_text = String(e)

    if not saw_error:
        raise Error(
            "expected DEADLINE_EXCEEDED for timeout_ms="
            + String(timeout_ms)
            + " delay_ms="
            + String(delay_ms)
            + " but call returned normally"
        )

    var name = grpc_status_name(GRPC_STATUS_DEADLINE_EXCEEDED)
    if name not in error_text:
        raise Error("expected " + name + " — got: " + error_text)
    print(
        "  PASS DEADLINE_EXCEEDED (timeout="
        + String(timeout_ms)
        + "ms, server delay="
        + String(delay_ms)
        + "ms)"
    )


def expect_ok_within_deadline(
    mut stub: StatusProbeStub,
    timeout_ms: Int,
    delay_ms: Int,
    echo: String,
) raises:
    """Call with delay < timeout: the call must succeed and round-trip the body."""
    var reply = stub.Run(
        make_request(GRPC_STATUS_OK, String(""), echo, delay_ms),
        timeout_ms,
    )
    var got = reply.echo.value() if reply.echo else String("")
    if got != echo:
        raise Error("OK echo mismatch within deadline: got '" + got + "'")
    print(
        "  PASS OK within deadline (timeout="
        + String(timeout_ms)
        + "ms, server delay="
        + String(delay_ms)
        + "ms)"
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

    print("\n=== deadlines ===")

    # Sanity: a generous deadline does not interfere with normal traffic.
    expect_ok_within_deadline(stub, 1000, 0, String("instant under deadline"))
    expect_ok_within_deadline(stub, 1000, 50, String("50ms server delay under 1s"))

    # Server sleeps longer than the deadline — must surface DEADLINE_EXCEEDED.
    expect_deadline_exceeded(stub, 50, 500)
    expect_deadline_exceeded(stub, 100, 800)

    # Channel must still be usable after a timeout: setting timeout=0 on the
    # next call has to clear the persistent CURLOPT_TIMEOUT_MS on the Easy
    # handle, otherwise *every* subsequent call would time out too.
    expect_ok(stub, String("OK after deadline"))

    print("\nall test assertions passed")
