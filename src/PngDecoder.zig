const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;
const native_endian = @import("builtin").target.cpu.arch.endian();
const print = std.debug.print;
const magicNumbers = @import("magicNumbers.zig");
const utils = @import("utils.zig");
const test_allocator = std.testing.allocator;

pub fn PngDecoder(comptime ReaderType: type) type {
    return struct {
        const Self = @This();

        const PngDecoderErr = error{ ChunkCrcErr, ChunkHeaderSigErr, ChunkOrderErr };

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
        in_reader: ReaderType,
        parser_chunk: PngChunk,
        img: DecodedImg,

        pub fn init(a: Allocator, source: ReaderType) Self {
            return Self{
                .a = a,
                .in_reader = source,
                .img = undefined,
                .parser_chunk = .{ .len = 0, .chunkType = undefined, .data = null, .crc = 0 },
            };
        }

        pub fn parse(self: *Self) !bool {
            if (!(try self.parseHeaderSig()))
                return false;
            while (true) {
                try self.parseChunk();
                print("chunk type: {}, len: {d}, crc: {d} data:... \n", .{ self.parser_chunk.chunkType, self.parser_chunk.len, self.parser_chunk.crc });
                if (self.parser_chunk.chunkType == magicNumbers.ChunkType.ihdr) {}
                if (self.parser_chunk.chunkType == magicNumbers.ChunkType.idat) {
                    var in_stream = std.io.fixedBufferStream(self.parser_chunk.data.?);
                    var zlib_stream = try std.compress.zlib.zlibStream(self.a, in_stream.reader());
                    defer zlib_stream.deinit();

                    const buf = try zlib_stream.reader().readAllAlloc(self.a, std.math.maxInt(usize));
                    defer self.a.free(buf);
                }
                if (self.parser_chunk.chunkType == magicNumbers.ChunkType.iend) {
                    return true;
                }
            }
            return false;
        }

        fn parseChunk(self: *Self) !void {
            self.parser_chunk.len = try self.in_reader.readIntBig(u32);
            self.parser_chunk.chunkType = try std.meta.intToEnum(magicNumbers.ChunkType, try self.in_reader.readIntLittle(u32));
            self.parser_chunk.data = try self.a.alloc(u8, self.parser_chunk.len);
            try self.in_reader.readNoEof(self.parser_chunk.data.?);
            self.parser_chunk.crc = try self.in_reader.readIntBig(u32);

            var crc_hash = std.hash.Crc32.init();
            crc_hash.update(&@bitCast([4]u8, self.parser_chunk.chunkType));
            crc_hash.update(self.parser_chunk.data.?);

            if (crc_hash.final() != self.parser_chunk.crc) {
                return PngDecoderErr.ChunkCrcErr;
            }
        }

        fn parseHeaderSig(self: *Self) !bool {
            if (mem.eql(u8, &(try self.in_reader.readBytesNoEof(8)), &magicNumbers.pngStreamStart)) {
                return true;
            }
            return false;
        }
    };
}

// todo => write tests
test "chunk decoder test" {}
