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
            bitmap_reader: std.compress.zlib.ZlibStream(std.io.FixedBufferStream([]u8).Reader).Reader,

            color_type: magicNumbers.ImgColorType,
            compression_method: u8,
            filter_method: u8,
            interlace_method: u8,
        };

        pub const PngChunk = struct {
            pub const Error = ReaderType.Error || PngDecoderErr || std.compress.deflate.InflateStream(ReaderType).Error || error{ WrongChecksum, OverreadBuffer };
            pub const Reader = std.io.Reader(*PngChunk, Error, read);

            img_reader: ReaderType,
            len_read: usize,
            len: u32, // only defines len of the data field!
            chunk_type: magicNumbers.ChunkType,
            crc_hasher: std.hash.Crc32,

            pub fn init(img_reader: ReaderType) !PngChunk {
                var chunk = PngChunk{
                    .img_reader = img_reader,
                    .len = 0,
                    .len_read = 0,
                    .chunk_type = undefined,
                    .crc_hasher = std.hash.Crc32.init(),
                };
                try chunk.parseChunkHeader();
                return chunk;
            }

            fn parseChunkHeader(self: *PngChunk) !void {
                self.len = try self.img_reader.readIntBig(u32);
                self.chunk_type = std.meta.intToEnum(magicNumbers.ChunkType, try self.img_reader.readIntNative(u32)) catch {
                    return PngDecoderErr.ChunkTypeNotSupported;
                };
                self.crc_hasher.update(&@bitCast([4]u8, self.chunk_type));
            }

            // Implements the io.Reader interface
            pub fn read(self: *PngChunk, buffer: []u8) Error!usize {
                if (buffer.len == 0)
                    return 0;

                const r = try self.img_reader.read(buffer);
                self.len_read += r;
                self.crc_hasher.update(buffer[0..r]);
                if (self.len_read == self.len) {
                    const hash = try self.img_reader.readIntBig(u32);
                    if (hash != self.crc_hasher.final())
                        return error.WrongChecksum;
                } else if (self.len_read > self.len) {
                    print("{d} - {d} \n", .{ self.len_read, self.len });
                    return error.OverreadBuffer;
                }
                return r;
            }
            pub fn reader(self: *PngChunk) Reader {
                return .{ .context = self };
            }
        };

        a: Allocator,
        in_reader: ReaderType,
        zls_stream_buff_data_appended: usize,
        zlib_stream: ?std.compress.zlib.ZlibStream(std.io.FixedBufferStream([]u8).Reader),
        zlib_stream_buff: std.ArrayList(u8),

        pub fn init(a: Allocator, source: ReaderType) Self {
            return Self{
                .a = a,
                .in_reader = source,
                .zls_stream_buff_data_appended = 0,
                .zlib_stream = null,
                .zlib_stream_buff = std.ArrayList(u8).init(a),
            };
        }

        pub fn parse(self: *Self) !DecodedImg {
            var final_img: DecodedImg = undefined;
            try self.parsePngStreamHeaderSig();
            while (true) {
                // todo => check if it's a critical chunk
                var current_chunk = try PngChunk.init(self.in_reader);
                print("chunk type: {}, len: {d}, crc: .. data:... \n", .{ current_chunk.chunk_type, current_chunk.len });
                switch (current_chunk.chunk_type) {
                    magicNumbers.ChunkType.ihdr => {
                        final_img.width = try current_chunk.reader().readIntBig(u32);
                        final_img.height = try current_chunk.reader().readIntBig(u32);
                        final_img.bit_depth = try current_chunk.reader().readIntBig(u8);
                        final_img.color_type = try std.meta.intToEnum(magicNumbers.ImgColorType, try current_chunk.reader().readIntBig(u8));
                        final_img.compression_method = try current_chunk.reader().readIntBig(u8);
                        final_img.filter_method = try current_chunk.reader().readIntBig(u8);
                        final_img.interlace_method = try current_chunk.reader().readIntBig(u8);

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
                    },
                    magicNumbers.ChunkType.srgb => {
                        // todo => properly parse data
                        try current_chunk.reader().skipBytes(current_chunk.len, .{});
                    },
                    magicNumbers.ChunkType.eXIf => {
                        try current_chunk.reader().skipBytes(current_chunk.len, .{});
                    },
                    magicNumbers.ChunkType.idat => {
                        try self.zlsStreamReadNoEofToBuff(&current_chunk);
                    },
                    magicNumbers.ChunkType.iend => {
                        self.zlib_stream = try std.compress.zlib.zlibStream(self.a, std.io.fixedBufferStream(self.zlib_stream_buff.items).reader());
                        final_img.bitmap_reader = self.zlib_stream.?.reader();
                        return final_img;
                    },
                }
            }
        }
        pub fn deinit(self: *Self) void {
            if (self.zlib_stream) |*zlib_stream|
                zlib_stream.*.deinit();
            self.zlib_stream_buff.deinit();
        }

        // more of a utility func
        fn zlsStreamReadNoEofToBuff(self: *Self, current_chunk: *PngChunk) !void {
            self.zls_stream_buff_data_appended += current_chunk.len;
            try self.zlib_stream_buff.ensureTotalCapacity(self.zls_stream_buff_data_appended);

            self.zlib_stream_buff.expandToCapacity();
            try current_chunk.reader().readNoEof(self.zlib_stream_buff.items[self.zls_stream_buff_data_appended - current_chunk.len .. self.zls_stream_buff_data_appended]);
        }

        fn parsePngStreamHeaderSig(self: *Self) !void {
            if (!mem.eql(u8, &(try self.in_reader.readBytesNoEof(8)), &magicNumbers.PngStreamStart))
                return PngDecoderErr.MissingPngSig;
        }
    };
}

// todo => write tests
test "chunk decoder test" {}
