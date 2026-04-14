"""End-to-end tests for `grpc-status` trailers, deadlines, and request metadata.

Hits the local Python `StatusProbe` server (started by `bench/run.sh`) and
asserts:
  * an OK reply round-trips the body unchanged
  * non-OK replies raise `GrpcError` with the right code + message
  * a slow server beyond the client deadline raises DEADLINE_EXCEEDED
  * custom request metadata round-trips end-to-end (auth, tenant, request id)
  * mixed-case metadata keys are lowercased per HTTP/2
  * reserved / malformed metadata keys raise *before* hitting the wire
  * the channel is reusable after every error path

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


def expect_metadata_echo(
    mut stub: StatusProbeStub,
    var metadata: Dict[String, String],
    var expected_sorted: List[String],
    label: String,
) raises:
    """Call with `metadata`, assert the server saw exactly `expected_sorted`
    (a pre-sorted list of "key=value" strings)."""
    var reply = stub.Run(
        make_request(GRPC_STATUS_OK, String(""), String("md-echo")),
        0,
        metadata^,
    )

    if len(reply.seen_metadata) != len(expected_sorted):
        var dump = String("")
        for item in reply.seen_metadata:
            dump += String("\n    ") + item
        raise Error(
            label
            + ": expected "
            + String(len(expected_sorted))
            + " metadata entries, server saw "
            + String(len(reply.seen_metadata))
            + dump
        )

    for i in range(len(expected_sorted)):
        if reply.seen_metadata[i] != expected_sorted[i]:
            raise Error(
                label
                + ": metadata[" + String(i) + "] expected '"
                + expected_sorted[i] + "', got '" + reply.seen_metadata[i] + "'"
            )
    print("  PASS " + label)


def expect_metadata_rejected(
    mut stub: StatusProbeStub,
    var metadata: Dict[String, String],
    fragment: String,
    label: String,
) raises:
    """Assert that calling Run with `metadata` raises a client-side error
    whose text contains `fragment` — the call must NOT reach the server."""
    var saw_error = False
    var error_text = String("")
    try:
        _ = stub.Run(
            make_request(GRPC_STATUS_OK, String(""), String("rejected")),
            0,
            metadata^,
        )
    except e:
        saw_error = True
        error_text = String(e)

    if not saw_error:
        raise Error(label + ": expected client-side rejection, got success")
    if fragment not in error_text:
        raise Error(
            label
            + ": expected error to contain '"
            + fragment
            + "' — got: "
            + error_text
        )
    print("  PASS " + label + " (rejected: " + fragment + ")")


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

    # Server sleeps longer than the deadline - must surface DEADLINE_EXCEEDED.
    expect_deadline_exceeded(stub, 50, 500)
    expect_deadline_exceeded(stub, 100, 800)

    # Channel must still be usable after a timeout: setting timeout=0 on the
    # next call has to clear the persistent CURLOPT_TIMEOUT_MS on the Easy
    # handle, otherwise *every* subsequent call would time out too.
    expect_ok(stub, String("OK after deadline"))

    print("\n=== request metadata + auth ===")

    # Empty metadata: the server must see zero application-set entries.
    var no_meta = Dict[String, String]()
    var no_expected = List[String]()
    expect_metadata_echo(stub, no_meta^, no_expected^, String("no metadata"))

    # Single auth header (the bearer-token case).
    var auth_meta = Dict[String, String]()
    auth_meta[String("authorization")] = String("Bearer test-token-abc123")
    var auth_expected = List[String]()
    auth_expected.append(String("authorization=Bearer test-token-abc123"))
    expect_metadata_echo(stub, auth_meta^, auth_expected^, String("authorization bearer"))

    # Multiple custom headers (tenant + correlation id) plus auth, mixed-case
    # keys to exercise the lowercase normalization path.
    var multi_meta = Dict[String, String]()
    multi_meta[String("Authorization")] = String("Bearer xyz")
    multi_meta[String("X-Tenant")] = String("acme")
    multi_meta[String("x-request-id")] = String("req-42")
    var multi_expected = List[String]()
    multi_expected.append(String("authorization=Bearer xyz"))
    multi_expected.append(String("x-request-id=req-42"))
    multi_expected.append(String("x-tenant=acme"))
    expect_metadata_echo(stub, multi_meta^, multi_expected^, String("multiple custom headers"))

    # Reserved / forbidden keys: the call must fail client-side, never reach
    # the server. Each category gets its own assertion so a regression in one
    # branch doesn't hide behind another.
    var bad1 = Dict[String, String]()
    bad1[String("grpc-encoding")] = String("identity")
    expect_metadata_rejected(stub, bad1^, String("grpc-"), String("grpc- prefix"))

    var bad2 = Dict[String, String]()
    bad2[String("Content-Type")] = String("application/grpc+json")
    expect_metadata_rejected(stub, bad2^, String("content-type"), String("content-type override"))

    var bad3 = Dict[String, String]()
    bad3[String("user-agent")] = String("mine")
    expect_metadata_rejected(stub, bad3^, String("user-agent"), String("user-agent override"))

    var bad4 = Dict[String, String]()
    bad4[String(":authority")] = String("example.com")
    expect_metadata_rejected(stub, bad4^, String("pseudo-header"), String("HTTP/2 pseudo-header"))

    var bad5 = Dict[String, String]()
    bad5[String("x-blob-bin")] = String("not-binary")
    expect_metadata_rejected(stub, bad5^, String("-bin"), String("binary metadata key"))

    var bad6 = Dict[String, String]()
    bad6[String("x bad key")] = String("v")
    expect_metadata_rejected(stub, bad6^, String("illegal character"), String("illegal key char"))

    var bad7 = Dict[String, String]()
    bad7[String("x-injection")] = String("ok\r\nx-evil: hi")
    expect_metadata_rejected(stub, bad7^, String("non-printable"), String("CRLF injection in value"))

    # And: after every reject + every success, the channel still works.
    expect_ok(stub, String("OK after metadata"))

    print("\nall test assertions passed")
