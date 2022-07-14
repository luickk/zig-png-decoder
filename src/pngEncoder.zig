const std = @import("std");
const mem = std.mem;
const magicNumbers = @import("magicNumbers.zig");
const zlibStreamEnc = @import("zlibStreamEnc.zig");

const print = std.debug.print;
const Allocator = std.mem.Allocator;

pub fn simpleEncodeRgba(a: Allocator, bitmap: []u8, width: u32, height: u32, bits_pp: u8) !std.ArrayList(u8) {
    _ = bits_pp;
    _ = width;
    _ = height;
    _ = bitmap;

    var writer_tmp = std.ArrayList(u8).init(a);

    // header
    try writer_tmp.appendSlice(&magicNumbers.PngStreamStart);

    // ihdr chunk
    var ihdr_data: [13]u8 = undefined;
    mem.writeIntBig(u32, ihdr_data[0..4], width);
    mem.writeIntBig(u32, ihdr_data[4..8], height);
    ihdr_data[8] = bits_pp;
    ihdr_data[9] = @enumToInt(magicNumbers.ImgColorType.truecolor_alpha);
    ihdr_data[10] = 0;
    ihdr_data[11] = 0;
    ihdr_data[12] = 0;

    var ihdr_chunk_enc = try encodeChunk(a, magicNumbers.ChunkType.ihdr, &ihdr_data);
    try writer_tmp.appendSlice(ihdr_chunk_enc);
    a.free(ihdr_chunk_enc);

    // idat chunk
    var zlib_stream = try zlibStreamEnc.encodeZlibStream(a, bitmap);
    defer zlib_stream.deinit();

    // std.debug.print("len: {d} {d} \n", .{ zlib_stream.items.len, zlib_stream.items });
    var idat_chunk_enc = try encodeChunk(a, magicNumbers.ChunkType.idat, zlib_stream.items);
    try writer_tmp.appendSlice(idat_chunk_enc);
    a.free(idat_chunk_enc);

    // iend chunk
    var iend_chunk_enc = try encodeChunk(a, magicNumbers.ChunkType.iend, &[0]u8{});
    try writer_tmp.appendSlice(iend_chunk_enc);
    a.free(iend_chunk_enc);

    return writer_tmp;
}

pub fn encodeChunk(a: Allocator, chunk_type: magicNumbers.ChunkType, data: []u8) ![]u8 {
    var encoded_chunk = try a.alloc(u8, 12 + data.len);
    // ihdr chunk
    mem.writeIntBig(u32, encoded_chunk[0..4], @truncate(u32, data.len));
    mem.writeIntNative(u32, encoded_chunk[4..8], @enumToInt(chunk_type));
    mem.copy(u8, encoded_chunk[8 .. 8 + data.len], data);
    var crc_hash = std.hash.Crc32.init();
    crc_hash.update(&@bitCast([4]u8, chunk_type));
    crc_hash.update(data);
    var f = crc_hash.final();
    mem.copy(u8, encoded_chunk[8 + data.len ..], &@bitCast([4]u8, @byteSwap(u32, f)));
    return encoded_chunk;
}
