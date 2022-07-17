const std = @import("std");

const compressor = @import("compressor/compressor.zig");

// compresses with deflate and conforms to rfc 1950 specification
pub fn encodeZlibStream(a: std.mem.Allocator, writer: anytype, data: []u8) !void {
    var hasher = std.hash.Adler32.init();

    // from: https://www.ietf.org/rfc/rfc1950.txt
    //  CMF (Compression Method and flags)
    //  This byte is divided into a 4-bit compression method and a 4-
    //  bit information field depending on the compression method.

    //     bits 0 to 3  CM     Compression method
    //     bits 4 to 7  CINFO  Compression info

    // CM (Compression method)
    //  This identifies the compression method used in the file. CM = 8
    //  denotes the "deflate" compression method with a window size up
    //  to 32K.  This is the method used by gzip and PNG (see
    //  references [1] and [2] in Chapter 3, below, for the reference
    //  documents).  CM = 15 is reserved.  It might be used in a future
    //  version of this specification to indicate the presence of an
    //  extra field before the compressed data.
    // CINFO (Compression info)
    //     For CM = 8, CINFO is the base-2 logarithm of the LZ77 window
    //     size, minus eight (CINFO=7 indicates a 32K window size). Values
    //     of CINFO above 7 are not allowed in this version of the
    //     specification.  CINFO is not defined in this specification for
    //     CM not equal to 8.
    // FLG (FLaGs)
    //  This flag byte is divided as follows:

    //     bits 0 to 4  FCHECK  (check bits for CMF and FLG)
    //     bit  5       FDICT   (preset dictionary)
    //     bits 6 to 7  FLEVEL  (compression level)

    //  The FCHECK value must be such that CMF and FLG, when viewed as
    //  a 16-bit unsigned integer stored in MSB order (CMF*256 + FLG),
    //  is a multiple of 31.
    var zlib_header: [2]u8 = undefined;
    zlib_header[0] = 8; // CM (8 indicates deflate)
    zlib_header[0] |= 7 << 4; // CFINFO (7 indicates 32k window size)

    // by setting the whole flag byte to 0 dict & compression level are set to 0
    zlib_header[1] = 0;

    // setting mod 31 checksum; only write to the first 4 bits...
    zlib_header[1] += 31 - @truncate(u8, ((@as(u16, zlib_header[0]) << 8) + @as(u16, zlib_header[1])) % 31);

    try writer.writeAll(&zlib_header);
    var comp = try compressor.compressor(a, writer, .{ .level = compressor.Compression.huffman_only });
    _ = try comp.write(data);
    try comp.close();
    comp.deinit();

    hasher.update(data);
    // todo => do proper relative to host bs
    try writer.writeIntBig(u32, hasher.final());
}
