"""
HTTP/2 + TLS transport for gRPC
"""

from std.ffi import c_char, c_size_t
from memory import UnsafePointer
from mojo_curl import Easy, CurlList
from mojo_curl.c.types import (
    MutExternalOpaquePointer,
    MutExternalPointer,
    Result,
)
from mo_protobuf.common import Bytes


# libcurl calls this for each chunk of response data. `userdata` is a pointer to
# the response buffer (a Bytes == List[UInt8]), passed via CURLOPT_WRITEDATA.
def _write_cb(
    ptr: MutExternalPointer[c_char],
    size: c_size_t,
    nmemb: c_size_t,
    userdata: MutExternalOpaquePointer,
) -> c_size_t:
    var n = size * nmemb
    var buf = userdata.bitcast[Bytes]()
    buf[].reserve(len(buf[]) + Int(n))
    for i in range(Int(n)):
        buf[].append(UInt8(Int(ptr[i])))
    return n


# HTTP_VERSION enum values (from curl.h CURL_HTTP_VERSION_*)
alias HTTP_VERSION_NONE = 0
alias HTTP_VERSION_1_0 = 1
alias HTTP_VERSION_1_1 = 2
alias HTTP_VERSION_2_0 = 3
alias HTTP_VERSION_2TLS = 4  # upgrade to HTTP/2 over TLS, fall back to 1.1
alias HTTP_VERSION_2_PRIOR = 5  # cleartext HTTP/2 without upgrade


def http_post(url: String, body: Bytes, content_type: String = "application/grpc") raises -> Bytes:
    """POST `body` to `url` over HTTP/2 and return the response bytes.

    TLS is automatic for `https://` URLs. The gRPC content-type and trailer
    header are set by default.
    """
    var response = Bytes()
    var easy = Easy()

    var r: Result
    r = easy.url(url)
    if r != Result.OK:
        raise Error("curl.url: " + easy.describe_error(r))

    r = easy.post_fields(body)
    if r != Result.OK:
        raise Error("curl.post_fields: " + easy.describe_error(r))

    r = easy.http_version(HTTP_VERSION_2TLS)
    if r != Result.OK:
        raise Error("curl.http_version: " + easy.describe_error(r))

    r = easy.write_function(_write_cb)
    if r != Result.OK:
        raise Error("curl.write_function: " + easy.describe_error(r))

    r = easy.write_data(UnsafePointer(to=response).bitcast[NoneType]())
    if r != Result.OK:
        raise Error("curl.write_data: " + easy.describe_error(r))

    var headers = CurlList(
        {
            "Content-Type": content_type,
            "TE": "trailers",
            "User-Agent": "grpc-mojo/0.1",
        }
    )
    r = easy.http_headers(headers)
    if r != Result.OK:
        headers^.free()
        raise Error("curl.http_headers: " + easy.describe_error(r))

    r = easy.perform()
    headers^.free()
    if r != Result.OK:
        raise Error("curl.perform: " + easy.describe_error(r))

    return response^
