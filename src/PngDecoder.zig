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

        const DecodedImg = struct {
            width: u32,
            height: u32,
            bit_depth: u8,
            img_size: usize,
            bitmap_reader: std.io.FixedBufferStream([]u8).Reader,

            color_type: magicNumbers.ImgColorType,
            compression_method: u8,
            filter_method: u8,
            interlace_method: u8,
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
        zlib_stream_buff: std.ArrayList(u8),
        zlib_decoded: ?[]u8,

        pub fn init(a: Allocator, source: ReaderType) Self {
            return Self{
                .a = a,
                .in_reader = source,
                .parser_chunk = .{ .len = 0, .chunk_type = undefined, .data = null, .crc = 0 },
                .zlib_decoded = null,
                .zlib_stream_buff = std.ArrayList(u8).init(a),
            };
        }

        pub fn parse(self: *Self) !DecodedImg {
            var final_img: DecodedImg = undefined;
            try self.parseHeaderSig();
            while (true) {
                // if the chunktype is not found -> ignore
                // todo => check if it's a critical chunk
                try self.parseChunk();
                // print("chunk type: {}, len: {d}, crc: {d} data:... \n", .{ self.parser_chunk.chunk_type, self.parser_chunk.len, self.parser_chunk.crc });
                switch (self.parser_chunk.chunk_type) {
                    magicNumbers.ChunkType.ihdr => {
                        // parses ihdr data and writes it to final_img
                        try parseIHDRData(self.parser_chunk.data.?, &final_img);
                        // performing checks on png validity and compatibility with this parser
                        try final_img.color_type.checkAllowedBitDepths(final_img.bit_depth);
                        switch (final_img.color_type) {
                            magicNumbers.ImgColorType.truecolor => {
                                final_img.img_size = final_img.width * final_img.height * (final_img.bit_depth / 8) * 3;
                            },
                            magicNumbers.ImgColorType.truecolor_alpha => {
                                final_img.img_size = final_img.width * final_img.height * (final_img.bit_depth / 8) * 4;
                            },
                            else => {
                                return PngDecoderErr.ColorTypeNotSupported;
                            },
                        }
                        if (final_img.compression_method != 0)
                            return PngDecoderErr.CompressionNotSupported;
                        if (final_img.filter_method != 0)
                            return PngDecoderErr.FilterNotSupported;
                        if (final_img.interlace_method != 0)
                            return PngDecoderErr.InterlaceNotSupproted;
                        self.a.free(self.parser_chunk.data.?);
                    },
                    magicNumbers.ChunkType.srgb => {
                        self.a.free(self.parser_chunk.data.?);
                    },
                    magicNumbers.ChunkType.eXIf => {
                        self.a.free(self.parser_chunk.data.?);
                    },
                    magicNumbers.ChunkType.idat => {
                        try self.zlib_stream_buff.appendSlice(self.parser_chunk.data.?);
                        self.a.free(self.parser_chunk.data.?);
                    },
                    magicNumbers.ChunkType.iend => {
                        // todo => optimize; really inefficient...
                        var zlib_reader = std.io.fixedBufferStream(self.zlib_stream_buff.items).reader();
                        // not filters or interlacing required...
                        var zlib_stream = try std.compress.zlib.zlibStream(self.a, zlib_reader);
                        defer zlib_stream.deinit();

                        self.zlib_decoded = try zlib_stream.reader().readAllAlloc(self.a, std.math.maxInt(usize));
                        final_img.bitmap_reader = std.io.fixedBufferStream(self.zlib_decoded.?).reader();

                        return final_img;
                    },
                }
            }
        }
        pub fn deinit(self: *Self) void {
            if (self.zlib_decoded) |*zlib_dec|
                self.a.free(zlib_dec.*);
            self.zlib_stream_buff.deinit();
        }

        fn parseChunk(self: *Self) !void {
            self.parser_chunk.len = try self.in_reader.readIntBig(u32);
            var s = try self.in_reader.readIntNative(u32);
            self.parser_chunk.chunk_type = std.meta.intToEnum(magicNumbers.ChunkType, s) catch {
                // print("{d} \n", .{s});
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
        }
        fn parseIHDRData(data: []u8, final_img: *DecodedImg) !void {
            final_img.width = 100;
            final_img.width = mem.readIntBig(u32, data[0..4]);
            final_img.height = mem.readIntBig(u32, data[4..8]);
            final_img.bit_depth = mem.readIntBig(u8, data[8..9]);
            final_img.color_type = try std.meta.intToEnum(magicNumbers.ImgColorType, mem.readIntBig(u8, data[9..10]));
            final_img.compression_method = mem.readIntBig(u8, data[10..11]);
            final_img.filter_method = mem.readIntBig(u8, data[11..12]);
            final_img.interlace_method = mem.readIntBig(u8, data[12..13]);
        }

        fn parseHeaderSig(self: *Self) !void {
            if (!mem.eql(u8, &(try self.in_reader.readBytesNoEof(8)), &magicNumbers.PngStreamStart))
                return PngDecoderErr.MissingPngSig;
        }
    };
}

// todo => write tests
test "chunk decoder test" {}
