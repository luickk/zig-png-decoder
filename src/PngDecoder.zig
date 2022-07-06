const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;
const native_endian = @import("builtin").target.cpu.arch.endian();
const print = std.debug.print;
const magicNumbers = @import("magicNumbers.zig");
const test_allocator = std.testing.allocator;

const PngDecoder = @This();
const PngDecoderErr = error{ ChunkCrcErr, ChunkHeaderSigErr, ChunkOrderErr };
const ParserChunkState = enum {
    ParsingPngSig,
    ParsingHeaderChunk,
    ParsingZlsStreamChunk,
    ParsingEndingChunk,
};

const ParserInChunkState = enum { ParsingLen, ParsingType, ParsingData, ParsingCrc };

const DecodedImg = struct {
    width: u32,
    height: u32,
};

pub const PngChunk = struct {
    len: u32, // only defines the len of the data field!
    chunkType: magicNumbers.ChunkType,
    data: []u8,
    data_appended_size: usize,
    crc: u32,
};

a: Allocator,
buff: [4]u8,
parser_state: ParserChunkState,
parser_chunk_state: ParserInChunkState,
parser_chunk: PngChunk,

parser_png_sig: [8]u8,
parser_png_sig_appended_size: usize,

img: DecodedImg,

pub fn init(a: Allocator) PngDecoder {
    return PngDecoder{
        .a = a,
        .buff = undefined,
        .parser_chunk_state = ParserInChunkState.ParsingLen,
        .parser_state = ParserChunkState.ParsingHeaderChunk,
        .img = undefined,
        .parser_png_sig = undefined,
        .parser_png_sig_appended_size = 0,
        .parser_chunk = undefined,
    };
}

pub fn parse(self: *PngDecoder, buff: [4]u8) !void {
    self.buff = buff;
    switch (self.parser_state) {
        .ParsingPngSig => {
            if (try self.parseHeaderSig())
                self.parser_state = ParserChunkState.ParsingHeaderChunk;
        },
        .ParsingHeaderChunk => {
            if (try self.parseChunk()) {
                if (self.parser_chunk.chunkType == magicNumbers.ChunkType.ihdr) {
                    return PngDecoderErr.ChunkOrderErr;
                }
                // self.img.width = self.parser_chunk.data = [];

                self.a.free(self.parser_chunk.data);
                self.parser_state = ParserChunkState.ParsingZlsStreamChunk;
            }
        },
        .ParsingZlsStreamChunk => {
            if (try self.parseChunk())
                self.parser_state = ParserChunkState.ParsingZlsStreamChunk;
        },
        .ParsingEndingChunk => undefined,
    }
}

fn parseChunk(self: *PngDecoder) !bool {
    switch (self.parser_chunk_state) {
        ParserInChunkState.ParsingLen => {
            self.parser_chunk.len = @bitCast(u32, self.buff);
            if (native_endian == .Little) {
                self.parser_chunk.len = @byteSwap(u32, self.parser_chunk.len);
                return false;
            }
        },
        ParserInChunkState.ParsingType => {
            self.parser_chunk.chunkType = try std.meta.intToEnum(magicNumbers.ChunkType, @bitCast(u32, self.buff));
            return false;
        },
        ParserInChunkState.ParsingData => {
            if (self.parser_chunk.data_appended_size == 0)
                self.parser_chunk.data = try self.a.alloc(u8, self.parser_chunk.len);

            if (self.parser_chunk.data_appended_size <= self.parser_chunk.len) {
                mem.copy(u8, self.parser_chunk.data[self.parser_chunk.data_appended_size..], &self.buff);
                self.parser_chunk.data_appended_size += self.buff.len;
            } else {
                if (native_endian == .Little) {
                    mem.reverse(u8, self.parser_chunk.data);
                }
                return true;
            }

            return false;
        },
        ParserInChunkState.ParsingCrc => {
            self.parser_chunk.crc = @bitCast(u32, self.buff);
            if (native_endian == .Little) {
                self.parser_chunk.crc = @byteSwap(u32, self.parser_chunk.crc);
            }

            // todo => fix crc
            if (std.hash.Crc32.hash(self.parser_chunk.data) != self.parser_chunk.crc) {
                print("crc does not align!!! \n", .{});
                // return PngDecoderErr.ChunkCrcErr;
            }
            return true;
        },
    }
}

fn parseHeaderSig(self: *PngDecoder) !bool {
    mem.copy(u8, self.parser_png_sig[self.parser_png_sig_appended_size..], &self.buff);
    if (!mem.eql(u8, &self.parser_png_sig, &magicNumbers.pngStreamStart)) {
        self.parser_png_sig_appended_size = 0;
        return true;
    } else if (self.parser_png_sig_appended_size > 8) {
        return PngDecoderErr.ChunkCrcErr;
    } else {
        self.parser_png_sig_appended_size += 4;
        return false;
    }
}

// todo => write tests
test "chunk decoder test" {}
