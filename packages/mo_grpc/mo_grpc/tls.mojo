"""OpenSSL FFI layer for TLS connections with ALPN h2 negotiation."""

from std import ffi
from std.ffi import c_char, c_int, c_size_t, c_ssize_t, c_uint
from std.memory import UnsafePointer, memcpy
from std.sys.info import CompilationTarget
from std.os import getenv
import std.pathlib
from mo_protobuf.common import Bytes
from mo_grpc.net import TcpSocket, c_void


comptime SSL_ERROR_WANT_READ: c_int = 2
comptime SSL_ERROR_WANT_WRITE: c_int = 3
comptime SSL_CTRL_SET_TLSEXT_HOSTNAME: c_int = 55
comptime SSL_FILETYPE_PEM_VAL: c_int = 1
comptime SSL_VERIFY_PEER_VAL: c_int = 1
comptime SSL_VERIFY_FAIL_IF_NO_PEER_CERT: c_int = 2

comptime SSL_CTX_ptr = UnsafePointer[c_void, MutExternalOrigin]
comptime SSL_ptr = UnsafePointer[c_void, MutExternalOrigin]
comptime SSL_METHOD_ptr = UnsafePointer[c_void, MutExternalOrigin]
comptime OpaquePtr = UnsafePointer[c_void, MutExternalOrigin]


fn _to_opaque(ptr: UnsafePointer[c_void, _]) -> OpaquePtr:
    """Cast any void pointer to MutExternalOrigin for FFI calls."""
    return UnsafePointer[c_void, MutExternalOrigin](unsafe_from_address=Int(ptr))


fn _to_opaque_from_uint8(ptr: UnsafePointer[UInt8, _]) -> OpaquePtr:
    return UnsafePointer[c_void, MutExternalOrigin](unsafe_from_address=Int(ptr))


fn _to_opaque_from_char(ptr: UnsafePointer[c_char, _]) -> OpaquePtr:
    return UnsafePointer[c_void, MutExternalOrigin](unsafe_from_address=Int(ptr))


fn _get_ssl_lib_path() raises -> String:
    var path = getenv("LIBSSL_PATH")
    if path != "":
        return path
    comptime if CompilationTarget.is_macos():
        return String(std.pathlib.cwd()) + String("/.pixi/envs/default/lib/libssl.dylib")
    else:
        return String(std.pathlib.cwd()) + String("/.pixi/envs/default/lib/libssl.so")


struct SslLib(Movable):
    """Holds the loaded OpenSSL DLHandle and provides typed function lookups."""
    var handle: ffi.OwnedDLHandle

    fn __init__(out self) raises:
        self.handle = ffi.OwnedDLHandle(_get_ssl_lib_path(), ffi.RTLD.LAZY)

    fn __moveinit__(out self: SslLib, deinit take: SslLib):
        self.handle = take.handle^

    fn TLS_client_method(self) -> SSL_METHOD_ptr:
        return self.handle.get_function[fn () -> SSL_METHOD_ptr]("TLS_client_method")()

    fn SSL_CTX_new(self, method: SSL_METHOD_ptr) -> SSL_CTX_ptr:
        return self.handle.get_function[fn (SSL_METHOD_ptr) -> SSL_CTX_ptr]("SSL_CTX_new")(method)

    fn SSL_CTX_free(self, ctx: SSL_CTX_ptr):
        self.handle.get_function[fn (SSL_CTX_ptr) -> NoneType]("SSL_CTX_free")(ctx)

    fn SSL_CTX_set_default_verify_paths(self, ctx: SSL_CTX_ptr) -> c_int:
        return self.handle.get_function[fn (SSL_CTX_ptr) -> c_int]("SSL_CTX_set_default_verify_paths")(ctx)

    fn SSL_CTX_set_alpn_protos(self, ctx: SSL_CTX_ptr, protos: UnsafePointer[UInt8, _], protos_len: c_uint) -> c_int:
        return self.handle.get_function[fn (OpaquePtr, OpaquePtr, c_uint) -> c_int]("SSL_CTX_set_alpn_protos")(ctx, _to_opaque_from_uint8(protos), protos_len)

    fn SSL_new(self, ctx: SSL_CTX_ptr) -> SSL_ptr:
        return self.handle.get_function[fn (SSL_CTX_ptr) -> SSL_ptr]("SSL_new")(ctx)

    fn SSL_free(self, ssl: SSL_ptr):
        self.handle.get_function[fn (SSL_ptr) -> NoneType]("SSL_free")(ssl)

    fn SSL_set_fd(self, ssl: SSL_ptr, fd: c_int) -> c_int:
        return self.handle.get_function[fn (SSL_ptr, c_int) -> c_int]("SSL_set_fd")(ssl, fd)

    fn SSL_ctrl(self, ssl: SSL_ptr, cmd: c_int, larg: c_int, parg: UnsafePointer[c_char, _]) -> c_int:
        return self.handle.get_function[fn (OpaquePtr, c_int, c_int, OpaquePtr) -> c_int]("SSL_ctrl")(ssl, cmd, larg, _to_opaque_from_char(parg))

    fn SSL_connect(self, ssl: SSL_ptr) -> c_int:
        return self.handle.get_function[fn (SSL_ptr) -> c_int]("SSL_connect")(ssl)

    fn SSL_read(self, ssl: SSL_ptr, buf: UnsafePointer[c_void, _], num: c_int) -> c_int:
        return self.handle.get_function[fn (OpaquePtr, OpaquePtr, c_int) -> c_int]("SSL_read")(ssl, _to_opaque(buf), num)

    fn SSL_write(self, ssl: SSL_ptr, buf: UnsafePointer[c_void, _], num: c_int) -> c_int:
        return self.handle.get_function[fn (OpaquePtr, OpaquePtr, c_int) -> c_int]("SSL_write")(ssl, _to_opaque(buf), num)

    fn SSL_shutdown(self, ssl: SSL_ptr) -> c_int:
        return self.handle.get_function[fn (SSL_ptr) -> c_int]("SSL_shutdown")(ssl)

    fn SSL_get_error(self, ssl: SSL_ptr, ret: c_int) -> c_int:
        return self.handle.get_function[fn (SSL_ptr, c_int) -> c_int]("SSL_get_error")(ssl, ret)

    # --- Server TLS ---

    fn TLS_server_method(self) -> SSL_METHOD_ptr:
        return self.handle.get_function[fn () -> SSL_METHOD_ptr]("TLS_server_method")()

    fn SSL_CTX_use_certificate_file(self, ctx: SSL_CTX_ptr, file: UnsafePointer[c_char, _], type: c_int) -> c_int:
        return self.handle.get_function[fn (OpaquePtr, OpaquePtr, c_int) -> c_int]("SSL_CTX_use_certificate_file")(ctx, _to_opaque_from_char(file), type)

    fn SSL_CTX_use_PrivateKey_file(self, ctx: SSL_CTX_ptr, file: UnsafePointer[c_char, _], type: c_int) -> c_int:
        return self.handle.get_function[fn (OpaquePtr, OpaquePtr, c_int) -> c_int]("SSL_CTX_use_PrivateKey_file")(ctx, _to_opaque_from_char(file), type)

    fn SSL_CTX_check_private_key(self, ctx: SSL_CTX_ptr) -> c_int:
        return self.handle.get_function[fn (SSL_CTX_ptr) -> c_int]("SSL_CTX_check_private_key")(ctx)

    fn SSL_accept(self, ssl: SSL_ptr) -> c_int:
        return self.handle.get_function[fn (SSL_ptr) -> c_int]("SSL_accept")(ssl)

    # --- mTLS ---

    fn SSL_CTX_set_verify(self, ctx: SSL_CTX_ptr, mode: c_int):
        self.handle.get_function[fn (SSL_CTX_ptr, c_int, OpaquePtr) -> NoneType]("SSL_CTX_set_verify")(ctx, mode, OpaquePtr())

    fn SSL_CTX_load_verify_locations(self, ctx: SSL_CTX_ptr, ca_file: UnsafePointer[c_char, _]) -> c_int:
        return self.handle.get_function[fn (OpaquePtr, OpaquePtr, OpaquePtr) -> c_int]("SSL_CTX_load_verify_locations")(ctx, _to_opaque_from_char(ca_file), OpaquePtr())

    fn SSL_get_verify_result(self, ssl: SSL_ptr) -> c_int:
        return self.handle.get_function[fn (SSL_ptr) -> c_int]("SSL_get_verify_result")(ssl)


struct TlsSocket(Movable):
    """A TLS-wrapped TCP socket with ALPN h2 negotiation."""

    var _ssl_lib: SslLib
    var tcp: TcpSocket
    var ctx: SSL_CTX_ptr
    var ssl: SSL_ptr

    fn __init__(out self, fd: c_int, host: String) raises:
        self._ssl_lib = SslLib()
        self.tcp = TcpSocket(fd)
        self.ctx = self._ssl_lib.SSL_CTX_new(self._ssl_lib.TLS_client_method())
        self.ssl = SSL_ptr()

        if not self.ctx:
            raise Error("SSL_CTX_new failed")

        _ = self._ssl_lib.SSL_CTX_set_default_verify_paths(self.ctx)

        var alpn = List[UInt8]()
        alpn.append(2)
        alpn.append(UInt8(ord("h")))
        alpn.append(UInt8(ord("2")))
        _ = self._ssl_lib.SSL_CTX_set_alpn_protos(self.ctx, alpn.unsafe_ptr(), c_uint(3))

        self.ssl = self._ssl_lib.SSL_new(self.ctx)
        if not self.ssl:
            raise Error("SSL_new failed")

        _ = self._ssl_lib.SSL_set_fd(self.ssl, self.tcp.fd)

        var host_copy = host
        _ = self._ssl_lib.SSL_ctrl(self.ssl, SSL_CTRL_SET_TLSEXT_HOSTNAME, c_int(0), host_copy.as_c_string_slice().unsafe_ptr())

        var rc = self._ssl_lib.SSL_connect(self.ssl)
        if rc != 1:
            var err = self._ssl_lib.SSL_get_error(self.ssl, rc)
            raise Error("SSL_connect failed: SSL_get_error=" + String(Int(err)))

    fn __moveinit__(out self: TlsSocket, deinit take: TlsSocket):
        self._ssl_lib = take._ssl_lib^
        self.tcp = take.tcp^
        self.ctx = take.ctx
        self.ssl = take.ssl

    fn __del__(deinit self):
        if self.ssl:
            _ = self._ssl_lib.SSL_shutdown(self.ssl)
            self._ssl_lib.SSL_free(self.ssl)
        if self.ctx:
            self._ssl_lib.SSL_CTX_free(self.ctx)

    fn write(self, data: Span[UInt8, _]) raises:
        var total = 0
        var length = len(data)
        while total < length:
            var n = self._ssl_lib.SSL_write(
                self.ssl,
                (data.unsafe_ptr() + total).bitcast[c_void](),
                c_int(length - total),
            )
            if n <= 0:
                var err = self._ssl_lib.SSL_get_error(self.ssl, n)
                raise Error("SSL_write failed: SSL_get_error=" + String(Int(err)))
            total += Int(n)

    fn read(self, buf: UnsafePointer[UInt8, _], max_len: Int) raises -> Int:
        var n = self._ssl_lib.SSL_read(
            self.ssl,
            buf.bitcast[c_void](),
            c_int(max_len),
        )
        if n <= 0:
            var err = self._ssl_lib.SSL_get_error(self.ssl, n)
            if err == SSL_ERROR_WANT_READ or err == SSL_ERROR_WANT_WRITE:
                return 0
            raise Error("SSL_read failed: SSL_get_error=" + String(Int(err)))
        return Int(n)

    fn read_into(self, mut buf: Bytes, max_len: Int) raises -> Int:
        var start = len(buf)
        buf.resize(start + max_len, UInt8(0))
        var p = buf.unsafe_ptr() + start
        var n = self.read(p, max_len)
        buf.resize(start + n, UInt8(0))
        return n


struct ServerTlsSocket(Movable):
    """Server-side TLS socket: loads cert+key, does SSL_accept."""

    var _ssl_lib: SslLib
    var tcp: TcpSocket
    var ctx: SSL_CTX_ptr
    var ssl: SSL_ptr

    fn __init__(
        out self, fd: c_int,
        cert_path: String, key_path: String,
        ca_path: String = String(""),
    ) raises:
        self._ssl_lib = SslLib()
        self.tcp = TcpSocket(fd)
        self.ctx = self._ssl_lib.SSL_CTX_new(self._ssl_lib.TLS_server_method())
        self.ssl = SSL_ptr()

        if not self.ctx:
            raise Error("SSL_CTX_new (server) failed")

        # Load server certificate + key
        var cert_s = cert_path
        var rc = self._ssl_lib.SSL_CTX_use_certificate_file(
            self.ctx, cert_s.as_c_string_slice().unsafe_ptr(), SSL_FILETYPE_PEM_VAL
        )
        if rc != 1:
            raise Error("SSL_CTX_use_certificate_file failed")

        var key_s = key_path
        rc = self._ssl_lib.SSL_CTX_use_PrivateKey_file(
            self.ctx, key_s.as_c_string_slice().unsafe_ptr(), SSL_FILETYPE_PEM_VAL
        )
        if rc != 1:
            raise Error("SSL_CTX_use_PrivateKey_file failed")

        rc = self._ssl_lib.SSL_CTX_check_private_key(self.ctx)
        if rc != 1:
            raise Error("SSL_CTX_check_private_key failed: cert/key mismatch")

        # mTLS: require + verify client cert if CA path provided
        if len(ca_path) > 0:
            var ca_s = ca_path
            rc = self._ssl_lib.SSL_CTX_load_verify_locations(
                self.ctx, ca_s.as_c_string_slice().unsafe_ptr()
            )
            if rc != 1:
                raise Error("SSL_CTX_load_verify_locations failed for " + ca_path)
            self._ssl_lib.SSL_CTX_set_verify(
                self.ctx, SSL_VERIFY_PEER_VAL | SSL_VERIFY_FAIL_IF_NO_PEER_CERT
            )

        # Create SSL session and do server-side handshake
        self.ssl = self._ssl_lib.SSL_new(self.ctx)
        if not self.ssl:
            raise Error("SSL_new (server) failed")

        _ = self._ssl_lib.SSL_set_fd(self.ssl, self.tcp.fd)

        rc = self._ssl_lib.SSL_accept(self.ssl)
        if rc != 1:
            var err = self._ssl_lib.SSL_get_error(self.ssl, rc)
            raise Error("SSL_accept failed: SSL_get_error=" + String(Int(err)))

    fn __moveinit__(out self: ServerTlsSocket, deinit take: ServerTlsSocket):
        self._ssl_lib = take._ssl_lib^
        self.tcp = take.tcp^
        self.ctx = take.ctx
        self.ssl = take.ssl

    fn __del__(deinit self):
        if self.ssl:
            _ = self._ssl_lib.SSL_shutdown(self.ssl)
            self._ssl_lib.SSL_free(self.ssl)
        if self.ctx:
            self._ssl_lib.SSL_CTX_free(self.ctx)

    fn write(self, data: Span[UInt8, _]) raises:
        var total = 0
        var length = len(data)
        while total < length:
            var n = self._ssl_lib.SSL_write(
                self.ssl,
                (data.unsafe_ptr() + total).bitcast[c_void](),
                c_int(length - total),
            )
            if n <= 0:
                var err = self._ssl_lib.SSL_get_error(self.ssl, n)
                raise Error("SSL_write failed: SSL_get_error=" + String(Int(err)))
            total += Int(n)

    fn read(self, buf: UnsafePointer[UInt8, _], max_len: Int) raises -> Int:
        var n = self._ssl_lib.SSL_read(
            self.ssl,
            buf.bitcast[c_void](),
            c_int(max_len),
        )
        if n <= 0:
            var err = self._ssl_lib.SSL_get_error(self.ssl, n)
            if err == SSL_ERROR_WANT_READ or err == SSL_ERROR_WANT_WRITE:
                return 0
            raise Error("SSL_read failed: SSL_get_error=" + String(Int(err)))
        return Int(n)

    fn read_into(self, mut buf: Bytes, max_len: Int) raises -> Int:
        var start = len(buf)
        buf.resize(start + max_len, UInt8(0))
        var p = buf.unsafe_ptr() + start
        var n = self.read(p, max_len)
        buf.resize(start + n, UInt8(0))
        return n
