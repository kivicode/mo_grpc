"""
HTTP/2 + TLS transport for gRPC.
"""

from std.ffi import c_char, c_size_t
from std.memory import UnsafePointer, memcpy
from mojo_curl import Easy, CurlList
from mojo_curl.c.types import (
    MutExternalOpaquePointer,
    MutExternalPointer,
    Result,
)
from mo_protobuf.common import Bytes


# HTTP_VERSION enum values, mirroring `CURL_HTTP_VERSION_*` from `curl.h`.
comptime HTTP_VERSION_NONE = 0
comptime HTTP_VERSION_1_0 = 1
comptime HTTP_VERSION_1_1 = 2
comptime HTTP_VERSION_2_0 = 3
comptime HTTP_VERSION_2TLS = 4         # negotiate HTTP/2 over TLS, fall back to 1.1
comptime HTTP_VERSION_2_PRIOR = 5      # cleartext HTTP/2 without upgrade


def _write_cb(
    ptr: MutExternalPointer[c_char],
    size: c_size_t,
    nmemb: c_size_t,
    userdata: MutExternalOpaquePointer,
) -> c_size_t:
    """libcurl write callback. `userdata` is a pointer to the response `Bytes`
    buffer that was passed via `CURLOPT_WRITEDATA`.

    Bulk-copies via `memcpy` — the previous per-byte append loop dominated
    unary RPC time on payloads larger than a few KB.
    """
    var chunk_len = Int(size * nmemb)
    var buffer = userdata.bitcast[Bytes]()
    var start = len(buffer[])

    buffer[].resize(start + chunk_len, UInt8(0))
    var dst = buffer[].unsafe_ptr() + start
    var src = ptr.bitcast[UInt8]()
    memcpy(dest=dst, src=src, count=chunk_len)

    return size * nmemb


def grpc_headers(content_type: String = "application/grpc") raises -> CurlList:
    """Build the standard gRPC client header set. Caller owns the returned
    list and must `.free()` it once libcurl is done with it.
    """
    return CurlList(
        {
            "Content-Type": content_type,
            "TE": "trailers",
            "User-Agent": "grpc-mojo/0.1",
        }
    )


def perform_post(
    mut easy: Easy,
    mut headers: CurlList,
    url: String,
    body: Bytes,
) raises -> Bytes:
    """Run a single POST on a borrowed Easy handle and return the response body.

    The caller owns both `easy` and `headers`. Reusing one Easy across many
    `perform_post` calls is the whole point of `GrpcChannel`: libcurl pools
    the underlying TCP / TLS / HTTP-2 connection on the easy handle.
    """
    var response = Bytes()
    var status: Result

    status = easy.url(url)
    if status != Result.OK:
        raise Error("curl.url: " + easy.describe_error(status))

    # `POSTFIELDSIZE` must be set *before* `COPYPOSTFIELDS` so libcurl knows
    # how many bytes to copy. (For plain `CURLOPT_POSTFIELDS` the size also
    # has to be set *after* — setting POSTFIELDS resets POSTFIELDSIZE to -1,
    # which makes libcurl fall back to `strlen()` and truncate any binary
    # body that begins with a null byte. gRPC frames always do.)
    status = easy.post_field_size(len(body))
    if status != Result.OK:
        raise Error("curl.post_field_size: " + easy.describe_error(status))

    status = easy.post_fields_copy(body)
    if status != Result.OK:
        raise Error("curl.post_fields: " + easy.describe_error(status))

    status = easy.http_version(HTTP_VERSION_2TLS)
    if status != Result.OK:
        raise Error("curl.http_version: " + easy.describe_error(status))

    status = easy.write_function(_write_cb)
    if status != Result.OK:
        raise Error("curl.write_function: " + easy.describe_error(status))

    status = easy.write_data(UnsafePointer(to=response).bitcast[NoneType]())
    if status != Result.OK:
        raise Error("curl.write_data: " + easy.describe_error(status))

    status = easy.http_headers(headers)
    if status != Result.OK:
        raise Error("curl.http_headers: " + easy.describe_error(status))

    status = easy.perform()
    if status != Result.OK:
        raise Error("curl.perform: " + easy.describe_error(status))

    return response^


def http_post(
    url: String,
    body: Bytes,
    content_type: String = "application/grpc",
) raises -> Bytes:
    """One-shot POST: builds a fresh Easy handle and discards it.

    Prefer `GrpcChannel`, which keeps a long-lived Easy and reuses the
    underlying connection.
    """
    var easy = Easy()
    var headers = grpc_headers(content_type)
    try:
        var response = perform_post(easy, headers, url, body)
        headers^.free()
        return response^
    except e:
        headers^.free()
        raise e
