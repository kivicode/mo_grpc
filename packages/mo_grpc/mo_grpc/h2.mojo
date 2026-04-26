"""Minimal HTTP/2 client for gRPC unary RPCs. Pure Mojo, no nghttp2 dependency.

Implements just enough HTTP/2 for unary request-response:
- Connection preface + SETTINGS
- HPACK literal header encoding/decoding (no dynamic table)
- HEADERS and DATA frame send/recv
- WINDOW_UPDATE handling
"""

from std.memory import UnsafePointer, memcpy
from mo_protobuf.common import Bytes
from mo_grpc.tls import TlsSocket
from mo_grpc.net import c_void
from std.ffi import c_int

# HTTP/2 frame types
comptime FRAME_DATA: UInt8 = 0x0
comptime FRAME_HEADERS: UInt8 = 0x1
comptime FRAME_SETTINGS: UInt8 = 0x4
comptime FRAME_PING: UInt8 = 0x6
comptime FRAME_GOAWAY: UInt8 = 0x7
comptime FRAME_RST_STREAM: UInt8 = 0x3
comptime FRAME_WINDOW_UPDATE: UInt8 = 0x8

# HTTP/2 flags
comptime FLAG_END_STREAM: UInt8 = 0x1
comptime FLAG_END_HEADERS: UInt8 = 0x4
comptime FLAG_ACK: UInt8 = 0x1

# HTTP/2 connection preface (24 bytes)
# "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
fn _h2_preface() -> Bytes:
    var b = Bytes()
    var s = String("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n")
    var sb = s.as_bytes()
    b.resize(len(sb), UInt8(0))
    for i in range(len(sb)):
        b[i] = sb[i]
    return b^


fn _write_u24_be(mut buf: Bytes, val: Int):
    buf.append(UInt8((val >> 16) & 0xFF))
    buf.append(UInt8((val >> 8) & 0xFF))
    buf.append(UInt8(val & 0xFF))


fn _write_u32_be(mut buf: Bytes, val: Int):
    buf.append(UInt8((val >> 24) & 0xFF))
    buf.append(UInt8((val >> 16) & 0xFF))
    buf.append(UInt8((val >> 8) & 0xFF))
    buf.append(UInt8(val & 0xFF))


fn _read_u24_be(buf: Bytes, offset: Int) -> Int:
    return (Int(buf[offset]) << 16) | (Int(buf[offset + 1]) << 8) | Int(buf[offset + 2])


fn _read_u32_be(buf: Bytes, offset: Int) -> Int:
    return (Int(buf[offset]) << 24) | (Int(buf[offset + 1]) << 16) | (Int(buf[offset + 2]) << 8) | Int(buf[offset + 3])


fn _build_frame(frame_type: UInt8, flags: UInt8, stream_id: Int, payload: Bytes) -> Bytes:
    """Build an HTTP/2 frame: 9-byte header + payload."""
    var frame = Bytes()
    frame.reserve(9 + len(payload))
    _write_u24_be(frame, len(payload))
    frame.append(frame_type)
    frame.append(flags)
    _write_u32_be(frame, stream_id & 0x7FFFFFFF)
    for i in range(len(payload)):
        frame.append(payload[i])
    return frame^


fn _build_settings_frame() -> Bytes:
    """Build SETTINGS frame with defaults (empty payload = use defaults)."""
    return _build_frame(FRAME_SETTINGS, UInt8(0), 0, Bytes())


fn _build_settings_ack() -> Bytes:
    return _build_frame(FRAME_SETTINGS, FLAG_ACK, 0, Bytes())


fn _build_window_update(stream_id: Int, increment: Int) -> Bytes:
    var payload = Bytes()
    _write_u32_be(payload, increment & 0x7FFFFFFF)
    return _build_frame(FRAME_WINDOW_UPDATE, UInt8(0), stream_id, payload^)


# HTTP/2 SETTINGS identifiers
comptime SETTINGS_HEADER_TABLE_SIZE: Int = 0x1
comptime SETTINGS_MAX_CONCURRENT_STREAMS: Int = 0x3
comptime SETTINGS_INITIAL_WINDOW_SIZE: Int = 0x4
comptime SETTINGS_MAX_FRAME_SIZE: Int = 0x5

# HTTP/2 defaults
comptime DEFAULT_MAX_FRAME_SIZE: Int = 16384
comptime DEFAULT_INITIAL_WINDOW_SIZE: Int = 65535


# RST_STREAM error codes
comptime H2_NO_ERROR: Int = 0
comptime H2_PROTOCOL_ERROR: Int = 1
comptime H2_INTERNAL_ERROR: Int = 2
comptime H2_CANCEL: Int = 8


fn _build_rst_stream(stream_id: Int, error_code: Int) -> Bytes:
    var payload = Bytes()
    _write_u32_be(payload, error_code)
    return _build_frame(FRAME_RST_STREAM, UInt8(0), stream_id, payload^)


fn _parse_settings_payload(payload: Bytes, mut max_frame_size: Int, mut initial_window_size: Int):
    """Parse SETTINGS frame payload (6 bytes per setting: 2-byte id + 4-byte value)."""
    var offset = 0
    while offset + 6 <= len(payload):
        var setting_id = (Int(payload[offset]) << 8) | Int(payload[offset + 1])
        var setting_val = _read_u32_be(payload, offset + 2)
        if setting_id == SETTINGS_MAX_FRAME_SIZE:
            max_frame_size = setting_val
        elif setting_id == SETTINGS_INITIAL_WINDOW_SIZE:
            initial_window_size = setting_val
        offset += 6


# --- HPACK Huffman decoding (RFC 7541 Appendix B) ---

# The Huffman table is represented as a binary tree in a flat array.
# Each node is 3 values: [symbol_or_flag, left_child_index, right_child_index]
# If symbol_or_flag >= 0 and < 256, it's a leaf node with that symbol.
# If symbol_or_flag == -1, it's a branch node (left=bit0, right=bit1).
# If symbol_or_flag == 256, it's the EOS marker.
# Node layout: _HUFF_TREE[i*3+0]=symbol (-1 for branch), _HUFF_TREE[i*3+1]=left, _HUFF_TREE[i*3+2]=right


fn _huffman_build_tree() -> List[Int]:
    """Build the HPACK Huffman decode tree from the code table.

    Returns a flat array of nodes. Each node is 3 ints:
      [symbol, left_child_node_index, right_child_node_index]
    symbol == -1 means internal/branch node.
    """
    # RFC 7541 Appendix B Huffman codes: (code_value, bit_length) for symbols 0..256
    # Stored as pairs in a flat list: [code0, len0, code1, len1, ...]
    var codes = List[Int]()
    codes.reserve(514)

    # sym 0: 0x1ff8, 13
    codes.append(0x1ff8); codes.append(13)
    # sym 1: 0x7fffd8, 23
    codes.append(0x7fffd8); codes.append(23)
    # sym 2: 0xfffffe2, 28
    codes.append(0xfffffe2); codes.append(28)
    # sym 3: 0xfffffe3, 28
    codes.append(0xfffffe3); codes.append(28)
    # sym 4: 0xfffffe4, 28
    codes.append(0xfffffe4); codes.append(28)
    # sym 5: 0xfffffe5, 28
    codes.append(0xfffffe5); codes.append(28)
    # sym 6: 0xfffffe6, 28
    codes.append(0xfffffe6); codes.append(28)
    # sym 7: 0xfffffe7, 28
    codes.append(0xfffffe7); codes.append(28)
    # sym 8: 0xfffffe8, 28
    codes.append(0xfffffe8); codes.append(28)
    # sym 9: 0xffffea, 24
    codes.append(0xffffea); codes.append(24)
    # sym 10: 0x3ffffffc, 30
    codes.append(0x3ffffffc); codes.append(30)
    # sym 11: 0xfffffe9, 28
    codes.append(0xfffffe9); codes.append(28)
    # sym 12: 0xfffffea, 28
    codes.append(0xfffffea); codes.append(28)
    # sym 13: 0x3ffffffd, 30
    codes.append(0x3ffffffd); codes.append(30)
    # sym 14: 0xfffffeb, 28
    codes.append(0xfffffeb); codes.append(28)
    # sym 15: 0xfffffec, 28
    codes.append(0xfffffec); codes.append(28)
    # sym 16: 0xfffffed, 28
    codes.append(0xfffffed); codes.append(28)
    # sym 17: 0xfffffee, 28
    codes.append(0xfffffee); codes.append(28)
    # sym 18: 0xfffffef, 28
    codes.append(0xfffffef); codes.append(28)
    # sym 19: 0xffffff0, 28
    codes.append(0xffffff0); codes.append(28)
    # sym 20: 0xffffff1, 28
    codes.append(0xffffff1); codes.append(28)
    # sym 21: 0xffffff2, 28
    codes.append(0xffffff2); codes.append(28)
    # sym 22: 0x3ffffffe, 30
    codes.append(0x3ffffffe); codes.append(30)
    # sym 23: 0xffffff3, 28
    codes.append(0xffffff3); codes.append(28)
    # sym 24: 0xffffff4, 28
    codes.append(0xffffff4); codes.append(28)
    # sym 25: 0xffffff5, 28
    codes.append(0xffffff5); codes.append(28)
    # sym 26: 0xffffff6, 28
    codes.append(0xffffff6); codes.append(28)
    # sym 27: 0xffffff7, 28
    codes.append(0xffffff7); codes.append(28)
    # sym 28: 0xffffff8, 28
    codes.append(0xffffff8); codes.append(28)
    # sym 29: 0xffffff9, 28
    codes.append(0xffffff9); codes.append(28)
    # sym 30: 0xffffffa, 28
    codes.append(0xffffffa); codes.append(28)
    # sym 31: 0xffffffb, 28
    codes.append(0xffffffb); codes.append(28)
    # sym 32 (space): 0x14, 6
    codes.append(0x14); codes.append(6)
    # sym 33 (!): 0x3f8, 10
    codes.append(0x3f8); codes.append(10)
    # sym 34 ("): 0x3f9, 10
    codes.append(0x3f9); codes.append(10)
    # sym 35 (#): 0xffa, 12
    codes.append(0xffa); codes.append(12)
    # sym 36 ($): 0x1ff9, 13
    codes.append(0x1ff9); codes.append(13)
    # sym 37 (%): 0x15, 6
    codes.append(0x15); codes.append(6)
    # sym 38 (&): 0xf8, 8
    codes.append(0xf8); codes.append(8)
    # sym 39 ('): 0x7fa, 11
    codes.append(0x7fa); codes.append(11)
    # sym 40 ((: 0x3fa, 10
    codes.append(0x3fa); codes.append(10)
    # sym 41 ()): 0x3fb, 10
    codes.append(0x3fb); codes.append(10)
    # sym 42 (*): 0xf9, 8
    codes.append(0xf9); codes.append(8)
    # sym 43 (+): 0x7fb, 11
    codes.append(0x7fb); codes.append(11)
    # sym 44 (,): 0xfa, 8
    codes.append(0xfa); codes.append(8)
    # sym 45 (-): 0x16, 6
    codes.append(0x16); codes.append(6)
    # sym 46 (.): 0x17, 6
    codes.append(0x17); codes.append(6)
    # sym 47 (/): 0x18, 6
    codes.append(0x18); codes.append(6)
    # sym 48 (0): 0x0, 5
    codes.append(0x0); codes.append(5)
    # sym 49 (1): 0x1, 5
    codes.append(0x1); codes.append(5)
    # sym 50 (2): 0x2, 5
    codes.append(0x2); codes.append(5)
    # sym 51 (3): 0x19, 6
    codes.append(0x19); codes.append(6)
    # sym 52 (4): 0x1a, 6
    codes.append(0x1a); codes.append(6)
    # sym 53 (5): 0x1b, 6
    codes.append(0x1b); codes.append(6)
    # sym 54 (6): 0x1c, 6
    codes.append(0x1c); codes.append(6)
    # sym 55 (7): 0x1d, 6
    codes.append(0x1d); codes.append(6)
    # sym 56 (8): 0x1e, 6
    codes.append(0x1e); codes.append(6)
    # sym 57 (9): 0x1f, 6
    codes.append(0x1f); codes.append(6)
    # sym 58 (:): 0x5c, 7
    codes.append(0x5c); codes.append(7)
    # sym 59 (;): 0xfb, 8
    codes.append(0xfb); codes.append(8)
    # sym 60 (<): 0x7ffc, 15
    codes.append(0x7ffc); codes.append(15)
    # sym 61 (=): 0x20, 6
    codes.append(0x20); codes.append(6)
    # sym 62 (>): 0xffb, 12
    codes.append(0xffb); codes.append(12)
    # sym 63 (?): 0x3fc, 10
    codes.append(0x3fc); codes.append(10)
    # sym 64 (@): 0x1ffa, 13
    codes.append(0x1ffa); codes.append(13)
    # sym 65 (A): 0x21, 6
    codes.append(0x21); codes.append(6)
    # sym 66 (B): 0x5d, 7
    codes.append(0x5d); codes.append(7)
    # sym 67 (C): 0x5e, 7
    codes.append(0x5e); codes.append(7)
    # sym 68 (D): 0x5f, 7
    codes.append(0x5f); codes.append(7)
    # sym 69 (E): 0x60, 7
    codes.append(0x60); codes.append(7)
    # sym 70 (F): 0x61, 7
    codes.append(0x61); codes.append(7)
    # sym 71 (G): 0x62, 7
    codes.append(0x62); codes.append(7)
    # sym 72 (H): 0x63, 7
    codes.append(0x63); codes.append(7)
    # sym 73 (I): 0x64, 7
    codes.append(0x64); codes.append(7)
    # sym 74 (J): 0x65, 7
    codes.append(0x65); codes.append(7)
    # sym 75 (K): 0x66, 7
    codes.append(0x66); codes.append(7)
    # sym 76 (L): 0x67, 7
    codes.append(0x67); codes.append(7)
    # sym 77 (M): 0x68, 7
    codes.append(0x68); codes.append(7)
    # sym 78 (N): 0x69, 7
    codes.append(0x69); codes.append(7)
    # sym 79 (O): 0x6a, 7
    codes.append(0x6a); codes.append(7)
    # sym 80 (P): 0x6b, 7
    codes.append(0x6b); codes.append(7)
    # sym 81 (Q): 0x6c, 7
    codes.append(0x6c); codes.append(7)
    # sym 82 (R): 0x6d, 7
    codes.append(0x6d); codes.append(7)
    # sym 83 (S): 0x6e, 7
    codes.append(0x6e); codes.append(7)
    # sym 84 (T): 0x6f, 7
    codes.append(0x6f); codes.append(7)
    # sym 85 (U): 0x70, 7
    codes.append(0x70); codes.append(7)
    # sym 86 (V): 0x71, 7
    codes.append(0x71); codes.append(7)
    # sym 87 (W): 0x72, 7
    codes.append(0x72); codes.append(7)
    # sym 88 (X): 0xfc, 8
    codes.append(0xfc); codes.append(8)
    # sym 89 (Y): 0x73, 7
    codes.append(0x73); codes.append(7)
    # sym 90 (Z): 0xfd, 8
    codes.append(0xfd); codes.append(8)
    # sym 91 ([): 0x1ffb, 13
    codes.append(0x1ffb); codes.append(13)
    # sym 92 (\): 0x7fff0, 19
    codes.append(0x7fff0); codes.append(19)
    # sym 93 (]): 0x1ffc, 13
    codes.append(0x1ffc); codes.append(13)
    # sym 94 (^): 0x3ffc, 14
    codes.append(0x3ffc); codes.append(14)
    # sym 95 (_): 0x22, 6
    codes.append(0x22); codes.append(6)
    # sym 96 (`): 0x7ffd, 15
    codes.append(0x7ffd); codes.append(15)
    # sym 97 (a): 0x3, 5
    codes.append(0x3); codes.append(5)
    # sym 98 (b): 0x23, 6
    codes.append(0x23); codes.append(6)
    # sym 99 (c): 0x4, 5
    codes.append(0x4); codes.append(5)
    # sym 100 (d): 0x24, 6
    codes.append(0x24); codes.append(6)
    # sym 101 (e): 0x5, 5
    codes.append(0x5); codes.append(5)
    # sym 102 (f): 0x25, 6
    codes.append(0x25); codes.append(6)
    # sym 103 (g): 0x26, 6
    codes.append(0x26); codes.append(6)
    # sym 104 (h): 0x27, 6
    codes.append(0x27); codes.append(6)
    # sym 105 (i): 0x6, 5
    codes.append(0x6); codes.append(5)
    # sym 106 (j): 0x74, 7
    codes.append(0x74); codes.append(7)
    # sym 107 (k): 0x75, 7
    codes.append(0x75); codes.append(7)
    # sym 108 (l): 0x28, 6
    codes.append(0x28); codes.append(6)
    # sym 109 (m): 0x29, 6
    codes.append(0x29); codes.append(6)
    # sym 110 (n): 0x2a, 6
    codes.append(0x2a); codes.append(6)
    # sym 111 (o): 0x7, 5
    codes.append(0x7); codes.append(5)
    # sym 112 (p): 0x2b, 6
    codes.append(0x2b); codes.append(6)
    # sym 113 (q): 0x76, 7
    codes.append(0x76); codes.append(7)
    # sym 114 (r): 0x2c, 6
    codes.append(0x2c); codes.append(6)
    # sym 115 (s): 0x8, 5
    codes.append(0x8); codes.append(5)
    # sym 116 (t): 0x9, 5
    codes.append(0x9); codes.append(5)
    # sym 117 (u): 0x2d, 6
    codes.append(0x2d); codes.append(6)
    # sym 118 (v): 0x77, 7
    codes.append(0x77); codes.append(7)
    # sym 119 (w): 0x78, 7
    codes.append(0x78); codes.append(7)
    # sym 120 (x): 0x79, 7
    codes.append(0x79); codes.append(7)
    # sym 121 (y): 0x7a, 7
    codes.append(0x7a); codes.append(7)
    # sym 122 (z): 0x7b, 7
    codes.append(0x7b); codes.append(7)
    # sym 123 ({): 0x7ffe, 15
    codes.append(0x7ffe); codes.append(15)
    # sym 124 (|): 0x7fc, 11
    codes.append(0x7fc); codes.append(11)
    # sym 125 (}): 0x3ffd, 14
    codes.append(0x3ffd); codes.append(14)
    # sym 126 (~): 0x1ffd, 13
    codes.append(0x1ffd); codes.append(13)
    # sym 127: 0xffffffc, 28
    codes.append(0xffffffc); codes.append(28)
    # sym 128: 0xfffe6, 20
    codes.append(0xfffe6); codes.append(20)
    # sym 129: 0x3fffd2, 22
    codes.append(0x3fffd2); codes.append(22)
    # sym 130: 0xfffe7, 20
    codes.append(0xfffe7); codes.append(20)
    # sym 131: 0xfffe8, 20
    codes.append(0xfffe8); codes.append(20)
    # sym 132: 0x3fffd3, 22
    codes.append(0x3fffd3); codes.append(22)
    # sym 133: 0x3fffd4, 22
    codes.append(0x3fffd4); codes.append(22)
    # sym 134: 0x3fffd5, 22
    codes.append(0x3fffd5); codes.append(22)
    # sym 135: 0x7fffd9, 23
    codes.append(0x7fffd9); codes.append(23)
    # sym 136: 0x3fffd6, 22
    codes.append(0x3fffd6); codes.append(22)
    # sym 137: 0x7fffda, 23
    codes.append(0x7fffda); codes.append(23)
    # sym 138: 0x7fffdb, 23
    codes.append(0x7fffdb); codes.append(23)
    # sym 139: 0x7fffdc, 23
    codes.append(0x7fffdc); codes.append(23)
    # sym 140: 0x7fffdd, 23
    codes.append(0x7fffdd); codes.append(23)
    # sym 141: 0x7fffde, 23
    codes.append(0x7fffde); codes.append(23)
    # sym 142: 0xffffeb, 24
    codes.append(0xffffeb); codes.append(24)
    # sym 143: 0x7fffdf, 23
    codes.append(0x7fffdf); codes.append(23)
    # sym 144: 0xffffec, 24
    codes.append(0xffffec); codes.append(24)
    # sym 145: 0xffffed, 24
    codes.append(0xffffed); codes.append(24)
    # sym 146: 0x3fffd7, 22
    codes.append(0x3fffd7); codes.append(22)
    # sym 147: 0x7fffe0, 23
    codes.append(0x7fffe0); codes.append(23)
    # sym 148: 0xffffee, 24
    codes.append(0xffffee); codes.append(24)
    # sym 149: 0x7fffe1, 23
    codes.append(0x7fffe1); codes.append(23)
    # sym 150: 0x7fffe2, 23
    codes.append(0x7fffe2); codes.append(23)
    # sym 151: 0x7fffe3, 23
    codes.append(0x7fffe3); codes.append(23)
    # sym 152: 0x7fffe4, 23
    codes.append(0x7fffe4); codes.append(23)
    # sym 153: 0x1fffdc, 21
    codes.append(0x1fffdc); codes.append(21)
    # sym 154: 0x3fffd8, 22
    codes.append(0x3fffd8); codes.append(22)
    # sym 155: 0x7fffe5, 23
    codes.append(0x7fffe5); codes.append(23)
    # sym 156: 0x3fffd9, 22
    codes.append(0x3fffd9); codes.append(22)
    # sym 157: 0x7fffe6, 23
    codes.append(0x7fffe6); codes.append(23)
    # sym 158: 0x7fffe7, 23
    codes.append(0x7fffe7); codes.append(23)
    # sym 159: 0xffffef, 24
    codes.append(0xffffef); codes.append(24)
    # sym 160: 0x3fffda, 22
    codes.append(0x3fffda); codes.append(22)
    # sym 161: 0x1fffdd, 21
    codes.append(0x1fffdd); codes.append(21)
    # sym 162: 0xfffe9, 20
    codes.append(0xfffe9); codes.append(20)
    # sym 163: 0x3fffdb, 22
    codes.append(0x3fffdb); codes.append(22)
    # sym 164: 0x3fffdc, 22
    codes.append(0x3fffdc); codes.append(22)
    # sym 165: 0x7fffe8, 23
    codes.append(0x7fffe8); codes.append(23)
    # sym 166: 0x7fffe9, 23
    codes.append(0x7fffe9); codes.append(23)
    # sym 167: 0x1fffde, 21
    codes.append(0x1fffde); codes.append(21)
    # sym 168: 0x7fffea, 23
    codes.append(0x7fffea); codes.append(23)
    # sym 169: 0x3fffdd, 22
    codes.append(0x3fffdd); codes.append(22)
    # sym 170: 0x3fffde, 22
    codes.append(0x3fffde); codes.append(22)
    # sym 171: 0xfffff0, 24
    codes.append(0xfffff0); codes.append(24)
    # sym 172: 0x1fffdf, 21
    codes.append(0x1fffdf); codes.append(21)
    # sym 173: 0x3fffdf, 22
    codes.append(0x3fffdf); codes.append(22)
    # sym 174: 0x7fffeb, 23
    codes.append(0x7fffeb); codes.append(23)
    # sym 175: 0x7fffec, 23
    codes.append(0x7fffec); codes.append(23)
    # sym 176: 0x1fffe0, 21
    codes.append(0x1fffe0); codes.append(21)
    # sym 177: 0x1fffe1, 21
    codes.append(0x1fffe1); codes.append(21)
    # sym 178: 0x3fffe0, 22
    codes.append(0x3fffe0); codes.append(22)
    # sym 179: 0x1fffe2, 21
    codes.append(0x1fffe2); codes.append(21)
    # sym 180: 0x7fffed, 23
    codes.append(0x7fffed); codes.append(23)
    # sym 181: 0x3fffe1, 22
    codes.append(0x3fffe1); codes.append(22)
    # sym 182: 0x7fffee, 23
    codes.append(0x7fffee); codes.append(23)
    # sym 183: 0x7fffef, 23
    codes.append(0x7fffef); codes.append(23)
    # sym 184: 0xfffea, 20
    codes.append(0xfffea); codes.append(20)
    # sym 185: 0x3fffe2, 22
    codes.append(0x3fffe2); codes.append(22)
    # sym 186: 0x3fffe3, 22
    codes.append(0x3fffe3); codes.append(22)
    # sym 187: 0x3fffe4, 22
    codes.append(0x3fffe4); codes.append(22)
    # sym 188: 0x7ffff0, 23
    codes.append(0x7ffff0); codes.append(23)
    # sym 189: 0x3fffe5, 22
    codes.append(0x3fffe5); codes.append(22)
    # sym 190: 0x3fffe6, 22
    codes.append(0x3fffe6); codes.append(22)
    # sym 191: 0x7ffff1, 23
    codes.append(0x7ffff1); codes.append(23)
    # sym 192: 0x3ffffe0, 26
    codes.append(0x3ffffe0); codes.append(26)
    # sym 193: 0x3ffffe1, 26
    codes.append(0x3ffffe1); codes.append(26)
    # sym 194: 0xfffeb, 20
    codes.append(0xfffeb); codes.append(20)
    # sym 195: 0x7fff1, 19
    codes.append(0x7fff1); codes.append(19)
    # sym 196: 0x3fffe7, 22
    codes.append(0x3fffe7); codes.append(22)
    # sym 197: 0x7ffff2, 23
    codes.append(0x7ffff2); codes.append(23)
    # sym 198: 0x3fffe8, 22
    codes.append(0x3fffe8); codes.append(22)
    # sym 199: 0x1ffffec, 25
    codes.append(0x1ffffec); codes.append(25)
    # sym 200: 0x3ffffe2, 26
    codes.append(0x3ffffe2); codes.append(26)
    # sym 201: 0x3ffffe3, 26
    codes.append(0x3ffffe3); codes.append(26)
    # sym 202: 0x3ffffe4, 26
    codes.append(0x3ffffe4); codes.append(26)
    # sym 203: 0x7ffffde, 27
    codes.append(0x7ffffde); codes.append(27)
    # sym 204: 0x7ffffdf, 27
    codes.append(0x7ffffdf); codes.append(27)
    # sym 205: 0x3ffffe5, 26
    codes.append(0x3ffffe5); codes.append(26)
    # sym 206: 0xfffff1, 24
    codes.append(0xfffff1); codes.append(24)
    # sym 207: 0x1ffffed, 25
    codes.append(0x1ffffed); codes.append(25)
    # sym 208: 0x7fff2, 19
    codes.append(0x7fff2); codes.append(19)
    # sym 209: 0x1fffe3, 21
    codes.append(0x1fffe3); codes.append(21)
    # sym 210: 0x3ffffe6, 26
    codes.append(0x3ffffe6); codes.append(26)
    # sym 211: 0x7ffffe0, 27
    codes.append(0x7ffffe0); codes.append(27)
    # sym 212: 0x7ffffe1, 27
    codes.append(0x7ffffe1); codes.append(27)
    # sym 213: 0x3ffffe7, 26
    codes.append(0x3ffffe7); codes.append(26)
    # sym 214: 0x7ffffe2, 27
    codes.append(0x7ffffe2); codes.append(27)
    # sym 215: 0xfffff2, 24
    codes.append(0xfffff2); codes.append(24)
    # sym 216: 0x1fffe4, 21
    codes.append(0x1fffe4); codes.append(21)
    # sym 217: 0x1fffe5, 21
    codes.append(0x1fffe5); codes.append(21)
    # sym 218: 0x3ffffe8, 26
    codes.append(0x3ffffe8); codes.append(26)
    # sym 219: 0x3ffffe9, 26
    codes.append(0x3ffffe9); codes.append(26)
    # sym 220: 0xffffffd, 28
    codes.append(0xffffffd); codes.append(28)
    # sym 221: 0x7ffffe3, 27
    codes.append(0x7ffffe3); codes.append(27)
    # sym 222: 0x7ffffe4, 27
    codes.append(0x7ffffe4); codes.append(27)
    # sym 223: 0x7ffffe5, 27
    codes.append(0x7ffffe5); codes.append(27)
    # sym 224: 0xfffec, 20
    codes.append(0xfffec); codes.append(20)
    # sym 225: 0xfffff3, 24
    codes.append(0xfffff3); codes.append(24)
    # sym 226: 0xfffed, 20
    codes.append(0xfffed); codes.append(20)
    # sym 227: 0x1fffe6, 21
    codes.append(0x1fffe6); codes.append(21)
    # sym 228: 0x3fffe9, 22
    codes.append(0x3fffe9); codes.append(22)
    # sym 229: 0x1fffe7, 21
    codes.append(0x1fffe7); codes.append(21)
    # sym 230: 0x1fffe8, 21
    codes.append(0x1fffe8); codes.append(21)
    # sym 231: 0x7ffff3, 23
    codes.append(0x7ffff3); codes.append(23)
    # sym 232: 0x3fffea, 22
    codes.append(0x3fffea); codes.append(22)
    # sym 233: 0x3fffeb, 22
    codes.append(0x3fffeb); codes.append(22)
    # sym 234: 0x1ffffee, 25
    codes.append(0x1ffffee); codes.append(25)
    # sym 235: 0x1ffffef, 25
    codes.append(0x1ffffef); codes.append(25)
    # sym 236: 0xfffff4, 24
    codes.append(0xfffff4); codes.append(24)
    # sym 237: 0xfffff5, 24
    codes.append(0xfffff5); codes.append(24)
    # sym 238: 0x3ffffea, 26
    codes.append(0x3ffffea); codes.append(26)
    # sym 239: 0x7ffff4, 23
    codes.append(0x7ffff4); codes.append(23)
    # sym 240: 0x3ffffeb, 26
    codes.append(0x3ffffeb); codes.append(26)
    # sym 241: 0x7ffffe6, 27
    codes.append(0x7ffffe6); codes.append(27)
    # sym 242: 0x3ffffec, 26
    codes.append(0x3ffffec); codes.append(26)
    # sym 243: 0x3ffffed, 26
    codes.append(0x3ffffed); codes.append(26)
    # sym 244: 0x7ffffe7, 27
    codes.append(0x7ffffe7); codes.append(27)
    # sym 245: 0x7ffffe8, 27
    codes.append(0x7ffffe8); codes.append(27)
    # sym 246: 0x7ffffe9, 27
    codes.append(0x7ffffe9); codes.append(27)
    # sym 247: 0x7ffffea, 27
    codes.append(0x7ffffea); codes.append(27)
    # sym 248: 0x7ffffeb, 27
    codes.append(0x7ffffeb); codes.append(27)
    # sym 249: 0xffffffe, 28
    codes.append(0xffffffe); codes.append(28)
    # sym 250: 0x7ffffec, 27
    codes.append(0x7ffffec); codes.append(27)
    # sym 251: 0x7ffffed, 27
    codes.append(0x7ffffed); codes.append(27)
    # sym 252: 0x7ffffee, 27
    codes.append(0x7ffffee); codes.append(27)
    # sym 253: 0x7ffffef, 27
    codes.append(0x7ffffef); codes.append(27)
    # sym 254: 0x7fffff0, 27
    codes.append(0x7fffff0); codes.append(27)
    # sym 255: 0x3ffffee, 26
    codes.append(0x3ffffee); codes.append(26)
    # sym 256 (EOS): 0x3fffffff, 30
    codes.append(0x3fffffff); codes.append(30)

    # Build tree: start with root node (index 0)
    # Each node: [symbol, left_child, right_child]
    # symbol == -1 means branch node; -2 means "no child" (empty slot)
    var tree = List[Int]()
    # Root node at index 0
    tree.append(-1)  # symbol (branch)
    tree.append(-2)  # left child (none)
    tree.append(-2)  # right child (none)
    var num_nodes = 1

    # Insert each symbol into the tree
    for sym in range(257):
        var code = codes[sym * 2]
        var nbits = codes[sym * 2 + 1]
        var node_idx = 0  # start at root

        for bit_pos in range(nbits):
            # Read bits from MSB to LSB
            var bit = (code >> (nbits - 1 - bit_pos)) & 1
            var child_slot = node_idx * 3 + 1 + bit

            if bit_pos == nbits - 1:
                # Last bit: create leaf node
                var leaf_idx = num_nodes
                tree.append(sym)   # symbol (0-255 or 256 for EOS)
                tree.append(-2)
                tree.append(-2)
                num_nodes += 1
                tree[child_slot] = leaf_idx
            else:
                # Not last bit: follow or create branch
                var child_idx = tree[child_slot]
                if child_idx == -2:
                    # Create new branch node
                    child_idx = num_nodes
                    tree.append(-1)   # branch
                    tree.append(-2)   # left (none)
                    tree.append(-2)   # right (none)
                    num_nodes += 1
                    tree[child_slot] = child_idx
                node_idx = child_idx

    return tree^


fn _huffman_decode(encoded: Bytes) -> Bytes:
    """Decode HPACK Huffman-encoded bytes using tree traversal."""
    var tree = _huffman_build_tree()
    var result = Bytes()
    var node_idx = 0  # start at root

    for byte_idx in range(len(encoded)):
        var byte_val = Int(encoded[byte_idx])
        for bit_pos in range(8):
            var bit = (byte_val >> (7 - bit_pos)) & 1
            var next_idx: Int
            if bit == 0:
                next_idx = tree[node_idx * 3 + 1]
            else:
                next_idx = tree[node_idx * 3 + 2]

            if next_idx < 0:
                # Invalid or missing node; likely padding bits at end
                return result^

            node_idx = next_idx
            var sym = tree[node_idx * 3]
            if sym >= 0:
                if sym == 256:
                    # EOS - stop decoding
                    return result^
                result.append(UInt8(sym))
                node_idx = 0  # back to root

    # If we end in a non-root node, that's the padding bits (should be all 1s)
    # Per RFC 7541, padding with 1-bits up to byte boundary is valid
    return result^


# --- HPACK: literal-only encoding (no Huffman, no dynamic table) ---

fn _hpack_encode_literal(mut buf: Bytes, name: String, value: String):
    """Encode a header as 'Literal Header Field without Indexing' (0000 prefix)."""
    var name_bytes = name.as_bytes()
    var value_bytes = value.as_bytes()
    buf.append(UInt8(0x00))  # literal without indexing, new name
    _hpack_encode_integer(buf, len(name_bytes), 7)
    for i in range(len(name_bytes)):
        buf.append(name_bytes[i])
    _hpack_encode_integer(buf, len(value_bytes), 7)
    for i in range(len(value_bytes)):
        buf.append(value_bytes[i])


fn _hpack_encode_integer(mut buf: Bytes, value: Int, prefix_bits: Int):
    """HPACK integer encoding (RFC 7541 Section 5.1)."""
    var max_prefix = (1 << prefix_bits) - 1
    if value < max_prefix:
        buf.append(UInt8(value))
    else:
        buf.append(UInt8(max_prefix))
        var remaining = value - max_prefix
        while remaining >= 128:
            buf.append(UInt8((remaining & 0x7F) | 0x80))
            remaining >>= 7
        buf.append(UInt8(remaining))


fn _hpack_decode_integer(buf: Bytes, mut offset: Int, prefix_bits: Int) -> Int:
    """Decode an HPACK integer."""
    var max_prefix = (1 << prefix_bits) - 1
    var val = Int(buf[offset]) & max_prefix
    offset += 1
    if val < max_prefix:
        return val
    var shift = 0
    while offset < len(buf):
        var byte = Int(buf[offset])
        offset += 1
        val += (byte & 0x7F) << shift
        shift += 7
        if (byte & 0x80) == 0:
            break
    return val


fn _hpack_decode_string(buf: Bytes, mut offset: Int) -> String:
    """Decode an HPACK string, with Huffman decoding support."""
    var huffman = (Int(buf[offset]) & 0x80) != 0
    var length = _hpack_decode_integer(buf, offset, 7)
    var raw = Bytes()
    raw.resize(length, UInt8(0))
    for i in range(length):
        if offset + i < len(buf):
            raw[i] = buf[offset + i]
    offset += length
    if huffman:
        var decoded = _huffman_decode(raw^)
        return String(unsafe_from_utf8=decoded^)
    return String(unsafe_from_utf8=raw^)


fn _hpack_lookup(index: Int, mut dyn_table: List[Tuple[String, String]]) -> Tuple[String, String]:
    """Look up index in combined static+dynamic table."""
    if index <= 61:
        return _static_table_entry(index)
    var dyn_idx = index - 62
    if dyn_idx < len(dyn_table):
        return (dyn_table[dyn_idx][0], dyn_table[dyn_idx][1])
    return (String("x-unknown-" + String(index)), String(""))


fn _hpack_decode_headers(block: Bytes, mut dyn_table: List[Tuple[String, String]]) -> Dict[String, String]:
    """Decode HPACK header block into a dict, maintaining the dynamic table."""
    var headers = Dict[String, String]()
    var offset = 0
    while offset < len(block):
        var byte = Int(block[offset])
        if (byte & 0x80) != 0:
            # Indexed header field (RFC 7541 §6.1)
            var idx = _hpack_decode_integer(block, offset, 7)
            var entry = _hpack_lookup(idx, dyn_table)
            headers[entry[0]] = entry[1]
        elif (byte & 0xC0) == 0x40:
            # Literal with incremental indexing (§6.2.1) — adds to dynamic table
            var name_idx = _hpack_decode_integer(block, offset, 6)
            var name: String
            if name_idx == 0:
                name = _hpack_decode_string(block, offset)
            else:
                name = _hpack_lookup(name_idx, dyn_table)[0]
            var value = _hpack_decode_string(block, offset)
            # Insert at front of dynamic table (newest first)
            dyn_table.insert(0, (name, value))
            headers[name] = value
        elif (byte & 0xF0) == 0x00:
            # Literal without indexing (§6.2.2)
            var name_idx = _hpack_decode_integer(block, offset, 4)
            var name: String
            if name_idx == 0:
                name = _hpack_decode_string(block, offset)
            else:
                name = _hpack_lookup(name_idx, dyn_table)[0]
            var value = _hpack_decode_string(block, offset)
            headers[name] = value
        elif (byte & 0xF0) == 0x10:
            # Literal never indexed (§6.2.3)
            var name_idx = _hpack_decode_integer(block, offset, 4)
            var name: String
            if name_idx == 0:
                name = _hpack_decode_string(block, offset)
            else:
                name = _hpack_lookup(name_idx, dyn_table)[0]
            var value = _hpack_decode_string(block, offset)
            headers[name] = value
        elif (byte & 0xE0) == 0x20:
            # Dynamic table size update (§6.3) — skip
            _ = _hpack_decode_integer(block, offset, 5)
        else:
            offset += 1
    return headers^


fn _static_table_entry(index: Int) -> Tuple[String, String]:
    """HPACK static table (RFC 7541, Appendix A). Returns (name, value)."""
    if index == 1: return (String(":authority"), String(""))
    if index == 2: return (String(":method"), String("GET"))
    if index == 3: return (String(":method"), String("POST"))
    if index == 4: return (String(":path"), String("/"))
    if index == 5: return (String(":path"), String("/index.html"))
    if index == 6: return (String(":scheme"), String("http"))
    if index == 7: return (String(":scheme"), String("https"))
    if index == 8: return (String(":status"), String("200"))
    if index == 9: return (String(":status"), String("204"))
    if index == 10: return (String(":status"), String("206"))
    if index == 11: return (String(":status"), String("304"))
    if index == 12: return (String(":status"), String("400"))
    if index == 13: return (String(":status"), String("404"))
    if index == 14: return (String(":status"), String("500"))
    if index == 15: return (String("accept-charset"), String(""))
    if index == 16: return (String("accept-encoding"), String("gzip, deflate"))
    if index == 17: return (String("accept-language"), String(""))
    if index == 18: return (String("accept-ranges"), String(""))
    if index == 19: return (String("accept"), String(""))
    if index == 20: return (String("access-control-allow-origin"), String(""))
    if index == 21: return (String("age"), String(""))
    if index == 22: return (String("allow"), String(""))
    if index == 23: return (String("authorization"), String(""))
    if index == 24: return (String("cache-control"), String(""))
    if index == 25: return (String("content-disposition"), String(""))
    if index == 26: return (String("content-encoding"), String(""))
    if index == 27: return (String("content-language"), String(""))
    if index == 28: return (String("content-length"), String(""))
    if index == 29: return (String("content-location"), String(""))
    if index == 30: return (String("content-range"), String(""))
    if index == 31: return (String("content-type"), String(""))
    if index == 32: return (String("cookie"), String(""))
    if index == 33: return (String("date"), String(""))
    if index == 34: return (String("etag"), String(""))
    if index == 35: return (String("expect"), String(""))
    if index == 36: return (String("expires"), String(""))
    if index == 37: return (String("from"), String(""))
    if index == 38: return (String("host"), String(""))
    if index == 39: return (String("if-match"), String(""))
    if index == 40: return (String("if-modified-since"), String(""))
    if index == 41: return (String("if-none-match"), String(""))
    if index == 42: return (String("if-range"), String(""))
    if index == 43: return (String("if-unmodified-since"), String(""))
    if index == 44: return (String("last-modified"), String(""))
    if index == 45: return (String("link"), String(""))
    if index == 46: return (String("location"), String(""))
    if index == 47: return (String("max-forwards"), String(""))
    if index == 48: return (String("proxy-authenticate"), String(""))
    if index == 49: return (String("proxy-authorization"), String(""))
    if index == 50: return (String("range"), String(""))
    if index == 51: return (String("referer"), String(""))
    if index == 52: return (String("refresh"), String(""))
    if index == 53: return (String("retry-after"), String(""))
    if index == 54: return (String("server"), String(""))
    if index == 55: return (String("set-cookie"), String(""))
    if index == 56: return (String("strict-transport-security"), String(""))
    if index == 57: return (String("transfer-encoding"), String(""))
    if index == 58: return (String("user-agent"), String(""))
    if index == 59: return (String("vary"), String(""))
    if index == 60: return (String("via"), String(""))
    if index == 61: return (String("www-authenticate"), String(""))
    return (String("x-unknown-" + String(index)), String(""))


# --- H2 Session State ---

struct H2Response(Movable):
    var headers: Dict[String, String]
    var trailers: Dict[String, String]
    var body: Bytes

    fn __init__(out self):
        self.headers = Dict[String, String]()
        self.trailers = Dict[String, String]()
        self.body = Bytes()

    fn __moveinit__(out self: H2Response, deinit take: H2Response):
        self.headers = take.headers^
        self.trailers = take.trailers^
        self.body = take.body^


struct H2FrameEvent(Movable):
    """Result of reading one relevant frame from the HTTP/2 connection."""
    var data: Bytes
    var trailers: Dict[String, String]
    var is_data: Bool
    var is_trailers: Bool
    var is_rst_stream: Bool
    var rst_error_code: Int
    var is_end_stream: Bool

    fn __init__(out self):
        self.data = Bytes()
        self.trailers = Dict[String, String]()
        self.is_data = False
        self.is_trailers = False
        self.is_rst_stream = False
        self.rst_error_code = 0
        self.is_end_stream = False

    fn __moveinit__(out self: H2FrameEvent, deinit take: H2FrameEvent):
        self.data = take.data^
        self.trailers = take.trailers^
        self.is_data = take.is_data
        self.is_trailers = take.is_trailers
        self.is_rst_stream = take.is_rst_stream
        self.rst_error_code = take.rst_error_code
        self.is_end_stream = take.is_end_stream

    @staticmethod
    def make_data(data: Bytes, end_stream: Bool) -> H2FrameEvent:
        var ev = H2FrameEvent()
        ev.data = data.copy()
        ev.is_data = True
        ev.is_end_stream = end_stream
        return ev^

    @staticmethod
    fn make_rst_stream(error_code: Int) -> H2FrameEvent:
        var ev = H2FrameEvent()
        ev.is_rst_stream = True
        ev.rst_error_code = error_code
        ev.is_end_stream = True
        return ev^

    @staticmethod
    def make_trailers(trailers: Dict[String, String], end_stream: Bool) -> H2FrameEvent:
        var ev = H2FrameEvent()
        ev.trailers = trailers.copy()
        ev.is_trailers = True
        ev.is_end_stream = end_stream
        return ev^


# --- H2 Connection ---

struct H2Connection(Movable):
    """An HTTP/2 connection over TLS. Pure Mojo, no nghttp2."""

    var tls: TlsSocket
    var next_stream_id: Int
    var response: H2Response
    var hpack_dyn_table: List[Tuple[String, String]]
    var peer_max_frame_size: Int
    var conn_window: Int
    var stream_window: Int

    fn __init__(out self, fd: c_int, host: String) raises:
        """Create H2Connection: TLS handshake + HTTP/2 preface + SETTINGS exchange."""
        self.tls = TlsSocket(fd, host)
        self.next_stream_id = 1
        self.response = H2Response()
        self.hpack_dyn_table = List[Tuple[String, String]]()
        self.peer_max_frame_size = DEFAULT_MAX_FRAME_SIZE
        self.conn_window = DEFAULT_INITIAL_WINDOW_SIZE
        self.stream_window = DEFAULT_INITIAL_WINDOW_SIZE

        # Send connection preface + our SETTINGS
        var preface = _h2_preface()
        self.tls.write(Span(preface))
        var settings = _build_settings_frame()
        self.tls.write(Span(settings))

        # Read server's SETTINGS (may come before or after our ACK)
        self._read_and_process_settings()

    fn __moveinit__(out self: H2Connection, deinit take: H2Connection):
        self.tls = take.tls^
        self.next_stream_id = take.next_stream_id
        self.response = take.response^
        self.hpack_dyn_table = take.hpack_dyn_table^
        self.peer_max_frame_size = take.peer_max_frame_size
        self.conn_window = take.conn_window
        self.stream_window = take.stream_window

    fn _read_and_process_settings(mut self) raises:
        """Read frames until we get the server's SETTINGS (non-ACK)."""
        while True:
            var frame_header = Bytes()
            self._read_exact(frame_header, 9)
            var payload_len = _read_u24_be(frame_header, 0)
            var frame_type = frame_header[3]
            var flags = frame_header[4]

            var payload = Bytes()
            if payload_len > 0:
                self._read_exact(payload, payload_len)

            if frame_type == FRAME_SETTINGS:
                if (Int(flags) & Int(FLAG_ACK)) == 0:
                    _parse_settings_payload(
                        payload, self.peer_max_frame_size, self.stream_window
                    )
                    self.conn_window = self.stream_window
                    var ack = _build_settings_ack()
                    self.tls.write(Span(ack))
                    return
                # else: SETTINGS ACK — keep reading
            elif frame_type == FRAME_WINDOW_UPDATE:
                if payload_len >= 4:
                    var increment = _read_u32_be(payload, 0) & 0x7FFFFFFF
                    self.conn_window += increment

    fn submit_request(
        mut self,
        method: String,
        path: String,
        authority: String,
        headers: Dict[String, String],
        body: Bytes,
    ) raises -> Int:
        """Submit an HTTP/2 request. Returns the stream ID."""
        var stream_id = self.next_stream_id
        self.next_stream_id += 2

        self.response = H2Response()
        # Reset stream window for this new stream
        self.stream_window = DEFAULT_INITIAL_WINDOW_SIZE

        # Build HPACK header block
        var hpack_block = Bytes()
        _hpack_encode_literal(hpack_block, String(":method"), method)
        _hpack_encode_literal(hpack_block, String(":path"), path)
        _hpack_encode_literal(hpack_block, String(":scheme"), String("https"))
        _hpack_encode_literal(hpack_block, String(":authority"), authority)
        for entry in headers.items():
            _hpack_encode_literal(hpack_block, entry.key, entry.value)

        # Send HEADERS frame
        var headers_flags = FLAG_END_HEADERS
        if len(body) == 0:
            headers_flags = headers_flags | FLAG_END_STREAM
        var headers_frame = _build_frame(FRAME_HEADERS, headers_flags, stream_id, hpack_block^)
        self.tls.write(Span(headers_frame))

        # Send DATA frames, split by max frame size and flow control window
        if len(body) > 0:
            self._send_data(stream_id, body)

        return stream_id

    fn _send_data(mut self, stream_id: Int, body: Bytes) raises:
        """Send body as one or more DATA frames, respecting frame size and flow control."""
        var offset = 0
        var total = len(body)
        while offset < total:
            var remaining = total - offset
            # Respect both max frame size and flow control windows
            var chunk_size = remaining
            if chunk_size > self.peer_max_frame_size:
                chunk_size = self.peer_max_frame_size
            if chunk_size > self.conn_window:
                chunk_size = self.conn_window
            if chunk_size > self.stream_window:
                chunk_size = self.stream_window

            # If window is exhausted, read frames until we get WINDOW_UPDATE
            if chunk_size <= 0:
                self._wait_for_window_update(stream_id)
                continue

            var is_last = (offset + chunk_size >= total)
            var flags = FLAG_END_STREAM if is_last else UInt8(0)

            # Build DATA frame with chunk
            var chunk = Bytes()
            chunk.resize(chunk_size, UInt8(0))
            memcpy(dest=chunk.unsafe_ptr(), src=body.unsafe_ptr() + offset, count=chunk_size)

            var frame = _build_frame(FRAME_DATA, flags, stream_id, chunk^)
            self.tls.write(Span(frame))

            self.conn_window -= chunk_size
            self.stream_window -= chunk_size
            offset += chunk_size

    fn _wait_for_window_update(mut self, stream_id: Int) raises:
        """Read frames until we get a WINDOW_UPDATE that opens the window."""
        while self.conn_window <= 0 or self.stream_window <= 0:
            var frame_header = Bytes()
            self._read_exact(frame_header, 9)
            var payload_len = _read_u24_be(frame_header, 0)
            var frame_type = frame_header[3]
            var flags = frame_header[4]
            var frame_stream_id = _read_u32_be(frame_header, 5) & 0x7FFFFFFF

            var payload = Bytes()
            if payload_len > 0:
                self._read_exact(payload, payload_len)

            if frame_type == FRAME_WINDOW_UPDATE and payload_len >= 4:
                var increment = _read_u32_be(payload, 0) & 0x7FFFFFFF
                if frame_stream_id == 0:
                    self.conn_window += increment
                elif frame_stream_id == stream_id:
                    self.stream_window += increment
            elif frame_type == FRAME_SETTINGS:
                if (Int(flags) & Int(FLAG_ACK)) == 0:
                    _parse_settings_payload(
                        payload, self.peer_max_frame_size, self.stream_window
                    )
                    var ack = _build_settings_ack()
                    self.tls.write(Span(ack))
            elif frame_type == FRAME_PING:
                if (Int(flags) & Int(FLAG_ACK)) == 0:
                    var pong = _build_frame(FRAME_PING, FLAG_ACK, 0, payload^)
                    self.tls.write(Span(pong))
            elif frame_type == FRAME_GOAWAY:
                var error_code = 0
                if len(payload) >= 8:
                    error_code = _read_u32_be(payload, 4)
                raise Error("server sent GOAWAY, error=" + String(error_code))

    fn read_next_event(mut self, stream_id: Int) raises -> H2FrameEvent:
        """Read frames until we get a DATA or HEADERS frame for our stream.

        Control frames (SETTINGS, PING, WINDOW_UPDATE, GOAWAY) are handled
        inline. Returns an H2FrameEvent with either data or trailers.
        """
        while True:
            var frame_header = Bytes()
            self._read_exact(frame_header, 9)

            var payload_len = _read_u24_be(frame_header, 0)
            var frame_type = frame_header[3]
            var flags = frame_header[4]
            var frame_stream_id = _read_u32_be(frame_header, 5) & 0x7FFFFFFF

            var payload = Bytes()
            if payload_len > 0:
                self._read_exact(payload, payload_len)

            var end_stream = (Int(flags) & Int(FLAG_END_STREAM)) != 0

            if frame_type == FRAME_DATA and frame_stream_id == stream_id:
                if payload_len > 0:
                    var wu_conn = _build_window_update(0, payload_len)
                    var wu_stream = _build_window_update(stream_id, payload_len)
                    self.tls.write(Span(wu_conn))
                    self.tls.write(Span(wu_stream))
                return H2FrameEvent.make_data(payload^, end_stream)
            elif frame_type == FRAME_HEADERS and frame_stream_id == stream_id:
                var decoded = _hpack_decode_headers(payload^, self.hpack_dyn_table)
                return H2FrameEvent.make_trailers(decoded^, end_stream)
            elif frame_type == FRAME_RST_STREAM and frame_stream_id == stream_id:
                var error_code = 0
                if payload_len >= 4:
                    error_code = _read_u32_be(payload, 0)
                return H2FrameEvent.make_rst_stream(error_code)
            elif frame_type == FRAME_SETTINGS:
                if (Int(flags) & Int(FLAG_ACK)) == 0:
                    var ack = _build_settings_ack()
                    self.tls.write(Span(ack))
            elif frame_type == FRAME_WINDOW_UPDATE:
                if payload_len >= 4:
                    var increment = _read_u32_be(payload, 0) & 0x7FFFFFFF
                    if frame_stream_id == 0:
                        self.conn_window += increment
                    elif frame_stream_id == stream_id:
                        self.stream_window += increment
            elif frame_type == FRAME_PING:
                if (Int(flags) & Int(FLAG_ACK)) == 0:
                    var pong = _build_frame(FRAME_PING, FLAG_ACK, 0, payload^)
                    self.tls.write(Span(pong))
            elif frame_type == FRAME_GOAWAY:
                var error_code = 0
                if len(payload) >= 8:
                    error_code = _read_u32_be(payload, 4)
                raise Error("server sent GOAWAY, error=" + String(error_code))

    fn cancel_stream(mut self, stream_id: Int) raises:
        """Send RST_STREAM(CANCEL) to abort a stream."""
        var frame = _build_rst_stream(stream_id, H2_CANCEL)
        self.tls.write(Span(frame))

    fn run_until_stream_close(mut self, stream_id: Int) raises:
        """Read frames until we get END_STREAM on our stream. For unary RPCs."""
        var got_end_stream = False
        var got_headers = False

        while not got_end_stream:
            var ev = self.read_next_event(stream_id)
            if ev.is_data:
                var start = len(self.response.body)
                self.response.body.resize(start + len(ev.data), UInt8(0))
                memcpy(
                    dest=self.response.body.unsafe_ptr() + start,
                    src=ev.data.unsafe_ptr(),
                    count=len(ev.data),
                )
            elif ev.is_trailers:
                if not got_headers:
                    self.response.headers = ev.trailers.copy()
                    got_headers = True
                else:
                    self.response.trailers = ev.trailers.copy()
            got_end_stream = ev.is_end_stream

    fn send_headers_only(
        mut self,
        method: String,
        path: String,
        authority: String,
        headers: Dict[String, String],
    ) raises -> Int:
        """Send HEADERS without END_STREAM (for client-streaming/bidi). Returns stream ID."""
        var stream_id = self.next_stream_id
        self.next_stream_id += 2
        self.response = H2Response()
        self.stream_window = DEFAULT_INITIAL_WINDOW_SIZE

        var hpack_block = Bytes()
        _hpack_encode_literal(hpack_block, String(":method"), method)
        _hpack_encode_literal(hpack_block, String(":path"), path)
        _hpack_encode_literal(hpack_block, String(":scheme"), String("https"))
        _hpack_encode_literal(hpack_block, String(":authority"), authority)
        for entry in headers.items():
            _hpack_encode_literal(hpack_block, entry.key, entry.value)

        var headers_frame = _build_frame(FRAME_HEADERS, FLAG_END_HEADERS, stream_id, hpack_block^)
        self.tls.write(Span(headers_frame))
        return stream_id

    fn send_data_frame(mut self, stream_id: Int, body: Bytes, end_stream: Bool) raises:
        """Send a single DATA frame, respecting flow control. Splits if needed."""
        var flags = FLAG_END_STREAM if end_stream else UInt8(0)
        if len(body) == 0:
            var frame = _build_frame(FRAME_DATA, flags, stream_id, body)
            self.tls.write(Span(frame))
            return

        var offset = 0
        var total = len(body)
        while offset < total:
            var remaining = total - offset
            var chunk_size = remaining
            if chunk_size > self.peer_max_frame_size:
                chunk_size = self.peer_max_frame_size
            if chunk_size > self.conn_window:
                chunk_size = self.conn_window
            if chunk_size > self.stream_window:
                chunk_size = self.stream_window

            if chunk_size <= 0:
                self._wait_for_window_update(stream_id)
                continue

            var is_last = (offset + chunk_size >= total)
            var chunk_flags = flags if is_last else UInt8(0)

            var chunk = Bytes()
            chunk.resize(chunk_size, UInt8(0))
            memcpy(dest=chunk.unsafe_ptr(), src=body.unsafe_ptr() + offset, count=chunk_size)

            var frame = _build_frame(FRAME_DATA, chunk_flags, stream_id, chunk^)
            self.tls.write(Span(frame))

            self.conn_window -= chunk_size
            self.stream_window -= chunk_size
            offset += chunk_size

    fn _read_exact(self, mut buf: Bytes, count: Int) raises:
        """Read exactly `count` bytes from TLS into buf."""
        var total = 0
        while total < count:
            var n: Int = 0
            try:
                n = self.tls.read_into(buf, count - total)
            except e:
                # Socket timeout manifests as SSL_read error
                raise Error("deadline_exceeded: " + String(e))
            if n == 0:
                raise Error("connection closed while reading")
            total += n
