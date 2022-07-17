const std = @import("std");
const magicNumbers = @import("magicNumbers.zig");
const zlibStreamEnc = @import("zlibStreamEnc.zig");

pub fn simpleEncodeRgba(a: std.mem.Allocator, writer: anytype, bitmap: []u8, width: u32, height: u32, bits_pp: u8) !void {
    // header
    try writer.writeAll(&magicNumbers.PngStreamStart);

    // ihdr chunk
    var ihdr_data: [13]u8 = undefined;
    std.mem.writeIntBig(u32, ihdr_data[0..4], width);
    std.mem.writeIntBig(u32, ihdr_data[4..8], height);
    ihdr_data[8] = bits_pp;
    ihdr_data[9] = @enumToInt(magicNumbers.ImgColorType.truecolor_alpha);
    ihdr_data[10] = 0;
    ihdr_data[11] = 0;
    ihdr_data[12] = 0;
    try encodeChunk(writer, magicNumbers.ChunkType.ihdr, &ihdr_data);

    // idat chunk
    var zlib_stream_buff = std.ArrayList(u8).init(a);
    defer zlib_stream_buff.deinit();
    try zlibStreamEnc.encodeZlibStream(a, zlib_stream_buff.writer(), bitmap);
    try encodeChunk(writer, magicNumbers.ChunkType.idat, zlib_stream_buff.items);

    // iend chunk
    try encodeChunk(writer, magicNumbers.ChunkType.iend, &[0]u8{});
}

fn encodeChunk(writer: anytype, chunk_type: magicNumbers.ChunkType, data: []u8) !void {
    // ihdr chunk
    try writer.writeIntBig(u32, @truncate(u32, data.len));
    try writer.writeIntNative(u32, @enumToInt(chunk_type));
    try writer.writeAll(data);
    var crc_hash = std.hash.Crc32.init();
    crc_hash.update(&@bitCast([4]u8, chunk_type));
    crc_hash.update(data);
    try writer.writeIntBig(u32, crc_hash.final());
}
