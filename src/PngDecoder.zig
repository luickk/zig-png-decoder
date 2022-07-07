const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;
const native_endian = @import("builtin").target.cpu.arch.endian();
const print = std.debug.print;
const magicNumbers = @import("magicNumbers.zig");
const utils = @import("utils.zig");
const test_allocator = std.testing.allocator;

const PngDecoder = @This();
const PngDecoderErr = error{ ChunkCrcErr, ChunkHeaderSigErr, ChunkOrderErr };
pub const ParserChunkState = enum {
    ParsingPngSig,
    ParsingHeaderChunk,
    ParsingBodyChunks,
    ParsingEndingChunk,
};

pub const ParserInChunkState = enum { ParsingLen, ParsingType, ParsingData, ParsingCrc };

const DecodedImg = struct {
    width: u32,
    height: u32,
};

pub const PngChunk = struct {
    len: u32, // only defines the len of the data field!
    chunkType: magicNumbers.ChunkType,
    data: ?[]u8,
    crc: u32,
};

a: Allocator,
buff: [1]u8,
parser_state: ParserChunkState,
parser_chunk_state: ParserInChunkState,
parser_chunk: PngChunk,
parser_gp_buff: [4]u8,
parser_png_sig: [8]u8,
parser_parsed_bytes: u32,

img: DecodedImg,

pub fn init(a: Allocator) PngDecoder {
    return PngDecoder{
        .a = a,
        .buff = undefined,
        .parser_chunk_state = ParserInChunkState.ParsingLen,
        .parser_state = ParserChunkState.ParsingPngSig,
        .img = undefined,
        .parser_png_sig = undefined,
        .parser_gp_buff = undefined,
        .parser_parsed_bytes = 0,
        .parser_chunk = .{ .len = 0, .chunkType = undefined, .data = null, .crc = 0 },
    };
}

pub fn parse(self: *PngDecoder, buff: [1]u8) !bool {
    self.buff = buff;
    switch (self.parser_state) {
        .ParsingPngSig => {
            if (try self.parseHeaderSig())
                self.parser_state = ParserChunkState.ParsingHeaderChunk;
        },
        .ParsingHeaderChunk => {
            if (try self.parseChunk()) {
                if (self.parser_chunk.chunkType != magicNumbers.ChunkType.ihdr) {
                    return PngDecoderErr.ChunkOrderErr;
                }
                print("chunk type: {}, len: {d}, crc: {d} data:{d} \n", .{ self.parser_chunk.chunkType, self.parser_chunk.len, self.parser_chunk.crc, self.parser_chunk.data.? });
                // self.img.width = self.parser_chunk.data = [];

                self.a.free(self.parser_chunk.data.?);
                self.parser_chunk.data = null;
                self.parser_state = ParserChunkState.ParsingBodyChunks;
            }
        },
        .ParsingBodyChunks => {
            if (try self.parseChunk()) {
                print("chunk type: {}, len: {d}, crc: {d} data:... \n", .{ self.parser_chunk.chunkType, self.parser_chunk.len, self.parser_chunk.crc });

                self.a.free(self.parser_chunk.data.?);
                self.parser_chunk.data = null;
                self.parser_state = ParserChunkState.ParsingBodyChunks;
            }
        },
        .ParsingEndingChunk => {
            if (try self.parseChunk()) {
                print("chunk type: {}, len: {d}, crc: {d} \n", .{ self.parser_chunk.chunkType, self.parser_chunk.len, self.parser_chunk.crc });
                return true;
            }
        },
    }
    return false;
}

fn parseChunk(self: *PngDecoder) !bool {
    switch (self.parser_chunk_state) {
        ParserInChunkState.ParsingLen => {
            // todo => change to bitwise concat!!
            self.parser_gp_buff[self.parser_parsed_bytes] = self.buff[0];
            self.parser_parsed_bytes += 1;
            if (self.parser_parsed_bytes == 4) {
                self.parser_chunk.len = @bitCast(u32, self.parser_gp_buff);
                if (native_endian == .Little) {
                    self.parser_chunk.len = @byteSwap(u32, self.parser_chunk.len);
                }
                self.parser_parsed_bytes = 0;
                self.parser_chunk_state = ParserInChunkState.ParsingType;
            }
        },
        ParserInChunkState.ParsingType => {
            self.parser_gp_buff[self.parser_parsed_bytes] = self.buff[0];
            self.parser_parsed_bytes += 1;

            if (self.parser_parsed_bytes == 4) {
                self.parser_chunk.chunkType = try std.meta.intToEnum(magicNumbers.ChunkType, @bitCast(u32, self.parser_gp_buff));
                if (self.parser_chunk.len != 0) {
                    self.parser_chunk_state = ParserInChunkState.ParsingData;
                } else {
                    self.parser_chunk_state = ParserInChunkState.ParsingCrc;
                }
                if (self.parser_chunk.chunkType == magicNumbers.ChunkType.iend)
                    self.parser_state = ParserChunkState.ParsingEndingChunk;
                self.parser_parsed_bytes = 0;
            }
        },
        ParserInChunkState.ParsingData => {
            if (self.parser_parsed_bytes == 0)
                self.parser_chunk.data = try self.a.alloc(u8, self.parser_chunk.len);

            self.parser_chunk.data.?[self.parser_parsed_bytes] = self.buff[0];
            self.parser_parsed_bytes += 1;
            if (self.parser_parsed_bytes == self.parser_chunk.len) {
                // if (native_endian == .Little) {
                //     mem.reverse(u8, self.parser_chunk.data.?);
                // }
                self.parser_chunk_state = ParserInChunkState.ParsingCrc;
                self.parser_parsed_bytes = 0;
            }
        },
        ParserInChunkState.ParsingCrc => {
            self.parser_gp_buff[self.parser_parsed_bytes] = self.buff[0];
            self.parser_parsed_bytes += 1;
            if (self.parser_parsed_bytes == 4) {
                self.parser_chunk.crc = @bitCast(u32, self.parser_gp_buff);
                if (native_endian == .Little) {
                    self.parser_chunk.crc = @byteSwap(u32, self.parser_chunk.crc);
                }
                if (self.parser_chunk.data != null) {
                    var crc_hash = std.hash.Crc32.init();
                    crc_hash.update(&@bitCast([4]u8, self.parser_chunk.chunkType));
                    crc_hash.update(self.parser_chunk.data.?);
                    var final_crc = crc_hash.final();
                    if (final_crc != self.parser_chunk.crc) {
                        return PngDecoderErr.ChunkCrcErr;
                    }
                }
                self.parser_chunk_state = ParserInChunkState.ParsingLen;
                self.parser_parsed_bytes = 0;
                return true;
            }
        },
    }
    return false;
}

fn parseHeaderSig(self: *PngDecoder) !bool {
    mem.copy(u8, self.parser_png_sig[self.parser_parsed_bytes..], &self.buff);
    if (mem.eql(u8, &self.parser_png_sig, &magicNumbers.pngStreamStart)) {
        self.parser_parsed_bytes = 0;
        return true;
    } else if (self.parser_parsed_bytes > 8) {
        return PngDecoderErr.ChunkCrcErr;
    } else {
        self.parser_parsed_bytes += @truncate(u32, self.buff.len);
        return false;
    }
}

// todo => write tests
test "chunk decoder test" {}
