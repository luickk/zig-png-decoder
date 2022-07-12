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

        const PngDecoderErr = error{ ChunkCrcErr, ChunkHeaderSigErr, ChunkOrderErr, MissingPngSig, ColorTypeNotSupported, CompressionNotSupported, FilterNotSupported, InterlaceNotSupproted, ChunkTypeNotSupported };
        const zls_stream_buff_size = 1000;
        const DecodedImg = struct {
            width: u32,
            height: u32,
            bit_depth: u8,
            img_size: usize,

            color_type: magicNumbers.ImgColorType,
            compression_method: u8,
            filter_method: u8,
            interlace_method: u8,

            bitmap_buff: ?[]u8,
        };

        pub const PngChunk = struct {
            len: u32, // only defines the len of the data field!
            chunk_type: magicNumbers.ChunkType,
            data: ?[]u8,
            crc: u32,
        };

        a: Allocator,
        in_reader: ReaderType,
        parser_chunk: PngChunk,
        img: DecodedImg,
        zls_stream_buff: std.ArrayList(u8),

        pub fn init(a: Allocator, source: ReaderType) Self {
            return Self{
                .a = a,
                .in_reader = source,
                .img = undefined,
                .parser_chunk = .{ .len = 0, .chunk_type = undefined, .data = null, .crc = 0 },
                .zls_stream_buff = std.ArrayList(u8).init(a),
            };
        }

        pub fn parse(self: *Self) !void {
            try self.parseHeaderSig();
            while (true) {
                // if the chunktype is not found -> ignore
                // todo => check if it's a critical chunk
                self.parseChunk() catch |e| if (e == PngDecoderErr.ChunkTypeNotSupported) continue;
                // print("chunk type: {}, len: {d}, crc: {d} data:... \n", .{ self.parser_chunk.chunk_type, self.parser_chunk.len, self.parser_chunk.crc });
                switch (self.parser_chunk.chunk_type) {
                    magicNumbers.ChunkType.ihdr => {
                        // parses ihdr data and writes it to self.img
                        try self.parseIHDRData(self.parser_chunk.data.?);
                        // performing checks on png validity and compatibility with this parser
                        try self.img.color_type.checkAllowedBitDepths(self.img.bit_depth);
                        switch (self.img.color_type) {
                            magicNumbers.ImgColorType.truecolor => {
                                self.img.img_size = self.img.width * self.img.height * (self.img.bit_depth / 8) * 3;
                            },
                            magicNumbers.ImgColorType.truecolor_alpha => {
                                self.img.img_size = self.img.width * self.img.height * (self.img.bit_depth / 8) * 4;
                            },
                            else => {
                                return PngDecoderErr.ColorTypeNotSupported;
                            },
                        }
                        if (self.img.compression_method != 0)
                            return PngDecoderErr.CompressionNotSupported;
                        if (self.img.filter_method != 0)
                            return PngDecoderErr.FilterNotSupported;
                        if (self.img.interlace_method != 0)
                            return PngDecoderErr.InterlaceNotSupproted;
                        self.a.free(self.parser_chunk.data.?);
                    },
                    magicNumbers.ChunkType.srgb => {
                        self.a.free(self.parser_chunk.data.?);
                    },
                    magicNumbers.ChunkType.idat => {
                        try self.zls_stream_buff.appendSlice(self.parser_chunk.data.?);
                        self.a.free(self.parser_chunk.data.?);
                    },
                    magicNumbers.ChunkType.iend => {
                        var in_stream = std.io.fixedBufferStream(self.zls_stream_buff.items);
                        var zlib_stream = try std.compress.zlib.zlibStream(self.a, in_stream.reader());
                        defer zlib_stream.deinit();

                        self.img.bitmap_buff = try zlib_stream.reader().readAllAlloc(self.a, std.math.maxInt(usize));
                        break;
                    },
                }
            }
        }
        pub fn deinit(self: *Self) void {
            if (self.img.bitmap_buff) |*bitmap_buff| {
                self.a.free(bitmap_buff.*);
            }
            self.zls_stream_buff.deinit();
        }

        fn parseChunk(self: *Self) !void {
            self.parser_chunk.len = try self.in_reader.readIntBig(u32);
            self.parser_chunk.chunk_type = std.meta.intToEnum(magicNumbers.ChunkType, try self.in_reader.readIntNative(u32)) catch {
                return PngDecoderErr.ChunkTypeNotSupported;
            };
            self.parser_chunk.data = try self.a.alloc(u8, self.parser_chunk.len);
            try self.in_reader.readNoEof(self.parser_chunk.data.?);
            self.parser_chunk.crc = try self.in_reader.readIntBig(u32);

            var crc_hash = std.hash.Crc32.init();
            crc_hash.update(&@bitCast([4]u8, self.parser_chunk.chunk_type));
            crc_hash.update(self.parser_chunk.data.?);

            if (crc_hash.final() != self.parser_chunk.crc) {
                return PngDecoderErr.ChunkCrcErr;
            }
            print("{} (d)crc: {d} \n", .{ self.parser_chunk.chunk_type, self.parser_chunk.crc });
        }
        fn parseIHDRData(self: *Self, data: []u8) !void {
            self.img.width = mem.readIntBig(u32, data[0..4]);
            self.img.height = mem.readIntBig(u32, data[4..8]);
            self.img.bit_depth = mem.readIntBig(u8, data[8..9]);
            self.img.color_type = try std.meta.intToEnum(magicNumbers.ImgColorType, mem.readIntBig(u8, data[9..10]));
            self.img.compression_method = mem.readIntBig(u8, data[10..11]);
            self.img.filter_method = mem.readIntBig(u8, data[11..12]);
            self.img.interlace_method = mem.readIntBig(u8, data[12..13]);
        }

        fn parseHeaderSig(self: *Self) !void {
            if (!mem.eql(u8, &(try self.in_reader.readBytesNoEof(8)), &magicNumbers.PngStreamStart))
                return PngDecoderErr.MissingPngSig;
        }
    };
}

// todo => write tests
test "chunk decoder test" {}
