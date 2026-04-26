"""POSIX socket FFI layer for TCP connections."""

from std.ffi import c_char, c_int, c_uint, c_ushort, c_size_t, c_ssize_t, external_call, get_errno
from std.sys.info import CompilationTarget, size_of
from std.memory import UnsafePointer, memcpy, stack_allocation
from std.utils import StaticTuple
from mo_protobuf.common import Bytes


comptime AF_INET: c_int = 2
comptime SOCK_STREAM: c_int = 1
comptime IPPROTO_TCP: c_int = 6
comptime SOL_SOCKET: c_int = 0xFFFF
comptime SO_REUSEADDR: c_int = 0x0004
comptime SO_RCVTIMEO: c_int = 0x1006
comptime SO_SNDTIMEO: c_int = 0x1005

comptime sa_family_t = c_ushort
comptime socklen_t = c_uint
comptime in_addr_t = c_uint
comptime in_port_t = c_ushort
comptime c_void = NoneType


@fieldwise_init
struct in_addr(TrivialRegisterPassable):
    var s_addr: in_addr_t


struct sockaddr(TrivialRegisterPassable):
    var sa_family: sa_family_t
    var sa_data: StaticTuple[c_char, 14]

    fn __init__(out self):
        self.sa_family = 0
        self.sa_data = StaticTuple[c_char, 14]()


@fieldwise_init
struct sockaddr_in(TrivialRegisterPassable):
    var sin_family: sa_family_t
    var sin_port: in_port_t
    var sin_addr: in_addr
    var sin_zero: StaticTuple[c_char, 8]


@fieldwise_init
struct timeval(TrivialRegisterPassable):
    var tv_sec: Int64
    var tv_usec: Int32


# addrinfo layout differs between macOS and Linux (ai_canonname/ai_addr swap).
@fieldwise_init
struct addrinfo_macos(TrivialRegisterPassable):
    var ai_flags: c_int
    var ai_family: c_int
    var ai_socktype: c_int
    var ai_protocol: c_int
    var ai_addrlen: socklen_t
    var ai_canonname: UnsafePointer[c_char, MutExternalOrigin]
    var ai_addr: UnsafePointer[sockaddr, MutExternalOrigin]
    var ai_next: UnsafePointer[addrinfo_macos, MutExternalOrigin]


@fieldwise_init
struct addrinfo_linux(TrivialRegisterPassable):
    var ai_flags: c_int
    var ai_family: c_int
    var ai_socktype: c_int
    var ai_protocol: c_int
    var ai_addrlen: socklen_t
    var ai_addr: UnsafePointer[sockaddr, MutExternalOrigin]
    var ai_canonname: UnsafePointer[c_char, MutExternalOrigin]
    var ai_next: UnsafePointer[addrinfo_linux, MutExternalOrigin]


fn htons(hostshort: c_ushort) -> c_ushort:
    return external_call["htons", c_ushort, type_of(hostshort)](hostshort)


fn htonl(hostlong: c_uint) -> c_uint:
    return external_call["htonl", c_uint, type_of(hostlong)](hostlong)


fn _socket(domain: c_int, type: c_int, protocol: c_int) -> c_int:
    return external_call["socket", c_int, type_of(domain), type_of(type), type_of(protocol)](
        domain, type, protocol
    )


fn _connect[origin: ImmutOrigin](
    socket: c_int,
    address: UnsafePointer[sockaddr_in, origin],
    address_len: socklen_t,
) -> c_int:
    return external_call["connect", c_int, type_of(socket), type_of(address), type_of(address_len)](
        socket, address, address_len
    )


fn _send[origin: ImmutOrigin](
    socket: c_int,
    buffer: UnsafePointer[c_void, origin],
    length: c_size_t,
    flags: c_int,
) -> c_ssize_t:
    return external_call["send", c_ssize_t, type_of(socket), type_of(buffer), type_of(length), type_of(flags)](
        socket, buffer, length, flags
    )


fn _recv[origin: MutOrigin](
    socket: c_int,
    buffer: UnsafePointer[c_void, origin],
    length: c_size_t,
    flags: c_int,
) -> c_ssize_t:
    return external_call["recv", c_ssize_t, type_of(socket), type_of(buffer), type_of(length), type_of(flags)](
        socket, buffer, length, flags
    )


fn _close(fd: c_int) -> c_int:
    return external_call["close", c_int, type_of(fd)](fd)


fn _setsockopt[origin: ImmutOrigin](
    socket: c_int,
    level: c_int,
    option_name: c_int,
    option_value: UnsafePointer[c_void, origin],
    option_len: socklen_t,
) -> c_int:
    return external_call["setsockopt", c_int, type_of(socket), type_of(level), type_of(option_name), type_of(option_value), type_of(option_len)](
        socket, level, option_name, option_value, option_len
    )


fn _memset[origin: MutOrigin](ptr: UnsafePointer[UInt8, origin], value: UInt8, count: Int):
    for i in range(count):
        ptr[i] = value


struct TcpSocket(Movable):
    var fd: c_int

    fn __init__(out self) raises:
        self.fd = _socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        if self.fd == -1:
            raise Error("socket() failed")

    fn __init__(out self, fd: c_int):
        self.fd = fd

    fn __moveinit__(out self: TcpSocket, deinit take: TcpSocket):
        self.fd = take.fd

    fn __del__(deinit self):
        if self.fd != -1:
            _ = _close(self.fd)

    fn connect(self, host: String, port: UInt16) raises:
        comptime if CompilationTarget.is_macos():
            self._connect_addrinfo[addrinfo_macos](host, port)
        else:
            self._connect_addrinfo[addrinfo_linux](host, port)

    fn _connect_addrinfo[T: TrivialRegisterPassable](self, host: String, port: UInt16) raises:
        var hints = stack_allocation[1, T]()
        _memset(hints.bitcast[UInt8](), 0, size_of[T]())
        var hints_as_ints = hints.bitcast[c_int]()
        hints_as_ints[1] = AF_INET       # ai_family
        hints_as_ints[2] = SOCK_STREAM   # ai_socktype

        var result_ptr = stack_allocation[1, UnsafePointer[T, MutExternalOrigin]]()
        result_ptr[0] = UnsafePointer[T, MutExternalOrigin]()

        var host_str = host
        var port_str = String(Int(port))
        var host_ptr = host_str.as_c_string_slice().unsafe_ptr()
        var port_ptr = port_str.as_c_string_slice().unsafe_ptr()

        var rc = external_call[
            "getaddrinfo",
            c_int,
            type_of(host_ptr),
            type_of(port_ptr),
            type_of(hints),
            type_of(result_ptr),
        ](
            host_ptr,
            port_ptr,
            hints,
            result_ptr,
        )

        if rc != 0:
            raise Error("getaddrinfo failed for " + host + ": error " + String(Int(rc)))

        var info_ptr = result_ptr[0]
        if not info_ptr:
            raise Error("getaddrinfo returned null for " + host)

        var addr_ptr: UnsafePointer[sockaddr, MutExternalOrigin]
        comptime if CompilationTarget.is_macos():
            addr_ptr = info_ptr.bitcast[addrinfo_macos]()[].ai_addr
        else:
            addr_ptr = info_ptr.bitcast[addrinfo_linux]()[].ai_addr

        if not addr_ptr:
            external_call["freeaddrinfo", NoneType, type_of(info_ptr)](info_ptr)
            raise Error("getaddrinfo returned null ai_addr for " + host)

        var connect_addr = addr_ptr.bitcast[sockaddr_in]()
        var rc2 = _connect(self.fd, UnsafePointer(to=connect_addr[]), socklen_t(size_of[sockaddr_in]()))

        external_call["freeaddrinfo", NoneType, type_of(info_ptr)](info_ptr)

        if rc2 == -1:
            raise Error("connect() failed for " + host + ":" + String(Int(port)))

    fn send_all(self, data: Span[UInt8, _]) raises:
        var total_sent = 0
        var length = len(data)
        while total_sent < length:
            var sent = _send(
                self.fd,
                (data.unsafe_ptr() + total_sent).bitcast[c_void](),
                c_size_t(length - total_sent),
                c_int(0),
            )
            if sent <= 0:
                raise Error("send() failed")
            total_sent += Int(sent)

    fn recv_into(self, mut buf: Bytes, max_len: Int) raises -> Int:
        var start = len(buf)
        buf.resize(start + max_len, UInt8(0))
        var n = _recv(
            self.fd,
            (buf.unsafe_ptr() + start).bitcast[c_void](),
            c_size_t(max_len),
            c_int(0),
        )
        if n < 0:
            buf.resize(start, UInt8(0))
            raise Error("recv() failed")
        buf.resize(start + Int(n), UInt8(0))
        return Int(n)

    fn set_timeout(self, timeout_ms: Int) raises:
        if timeout_ms <= 0:
            return
        var tv = timeval(tv_sec=Int64(timeout_ms // 1000), tv_usec=Int32((timeout_ms % 1000) * 1000))
        var rc = _setsockopt(
            self.fd,
            SOL_SOCKET,
            SO_RCVTIMEO,
            UnsafePointer(to=tv).bitcast[c_void](),
            socklen_t(size_of[timeval]()),
        )
        if rc != 0:
            raise Error("setsockopt(SO_RCVTIMEO) failed")
        rc = _setsockopt(
            self.fd,
            SOL_SOCKET,
            SO_SNDTIMEO,
            UnsafePointer(to=tv).bitcast[c_void](),
            socklen_t(size_of[timeval]()),
        )
        if rc != 0:
            raise Error("setsockopt(SO_SNDTIMEO) failed")

    fn close(mut self):
        if self.fd != -1:
            _ = _close(self.fd)
            self.fd = -1


# --- Server socket FFI ---

fn _bind[origin: ImmutOrigin](
    socket: c_int,
    address: UnsafePointer[sockaddr_in, origin],
    address_len: socklen_t,
) -> c_int:
    return external_call["bind", c_int, type_of(socket), type_of(address), type_of(address_len)](
        socket, address, address_len
    )


fn _listen(socket: c_int, backlog: c_int) -> c_int:
    return external_call["listen", c_int, type_of(socket), type_of(backlog)](socket, backlog)


fn _accept[o1: MutOrigin, o2: MutOrigin](
    socket: c_int,
    address: UnsafePointer[sockaddr, o1],
    address_len: UnsafePointer[socklen_t, o2],
) -> c_int:
    return external_call["accept", c_int, type_of(socket), type_of(address), type_of(address_len)](
        socket, address, address_len
    )


struct ListenSocket:
    """A TCP listening socket that accepts connections."""

    var fd: c_int

    fn __init__(out self, host: String, port: UInt16, backlog: Int = 128) raises:
        self.fd = _socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        if self.fd == -1:
            raise Error("socket() failed for listen")

        # SO_REUSEADDR for quick rebind after restart
        var one: c_int = 1
        _ = _setsockopt(
            self.fd, SOL_SOCKET, SO_REUSEADDR,
            UnsafePointer(to=one).bitcast[c_void](),
            socklen_t(size_of[c_int]()),
        )

        var addr = stack_allocation[1, sockaddr_in]()
        addr[0] = sockaddr_in(
            sin_family=sa_family_t(AF_INET),
            sin_port=htons(c_ushort(port)),
            sin_addr=in_addr(s_addr=in_addr_t(0)),
            sin_zero=StaticTuple[c_char, 8](),
        )

        var rc = _bind(self.fd, addr, socklen_t(size_of[sockaddr_in]()))
        if rc != 0:
            _ = _close(self.fd)
            raise Error("bind() failed on port " + String(Int(port)))

        rc = _listen(self.fd, c_int(backlog))
        if rc != 0:
            _ = _close(self.fd)
            raise Error("listen() failed")

    fn __del__(deinit self):
        if self.fd != -1:
            _ = _close(self.fd)

    fn accept(self) raises -> TcpSocket:
        """Accept one connection. Blocks until a client connects."""
        var client_addr = stack_allocation[1, sockaddr]()
        var addr_len = stack_allocation[1, socklen_t]()
        addr_len[0] = socklen_t(size_of[sockaddr]())
        var client_fd = _accept(self.fd, client_addr, addr_len)
        if client_fd == -1:
            raise Error("accept() failed")
        return TcpSocket(client_fd)


struct ParsedUrl:
    var host: String
    var port: UInt16
    var path: String

    fn __init__(out self, host: String, port: UInt16, path: String):
        self.host = host
        self.port = port
        self.path = path


def parse_url(url: String) raises -> ParsedUrl:
    """Parse a URL into host, port, path. Supports https://host:port/path format."""
    var url_bytes = url.as_bytes()
    var start: Int
    var default_port: UInt16

    if url.startswith("https://"):
        start = 8
        default_port = 443
    elif url.startswith("http://"):
        start = 7
        default_port = 80
    else:
        raise Error("unsupported URL scheme: " + url)

    # Find end of host:port (first slash after scheme)
    var authority_end = len(url_bytes)
    for i in range(start, len(url_bytes)):
        if url_bytes[i] == UInt8(ord("/")):
            authority_end = i
            break

    # Extract path
    var path = String("/")
    if authority_end < len(url_bytes):
        path = _substr(url, authority_end, len(url_bytes))

    # Extract host and port from authority
    var authority = _substr(url, start, authority_end)
    var host = authority
    var port = default_port
    var colon_pos = _find_char(authority, ":")
    if colon_pos >= 0:
        host = _substr(authority, 0, colon_pos)
        var port_str = _substr(authority, colon_pos + 1, len(authority))
        port = UInt16(atol(port_str))

    return ParsedUrl(host, port, path)


fn _substr(s: String, start: Int, end: Int) -> String:
    var s_bytes = s.as_bytes()
    var length = end - start
    var out = Bytes()
    out.resize(length, UInt8(0))
    for i in range(length):
        out[i] = s_bytes[start + i]
    return String(unsafe_from_utf8=out^)


fn _find_char(s: String, c: String) -> Int:
    var s_bytes = s.as_bytes()
    var c_byte = c.as_bytes()[0]
    for i in range(len(s_bytes)):
        if s_bytes[i] == c_byte:
            return i
    return -1
