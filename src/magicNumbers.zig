const std = @import("std");

const MagicNumberErr = error{BitDepthColorTypeMissmatch};

pub const PngStreamStart = [_]u8{ 137, 80, 78, 71, 13, 10, 26, 10 };

pub const ChunkType = enum(u32) {
    idat = @bitCast(u32, [_]u8{ 73, 68, 65, 84 }),
    iend = @bitCast(u32, [_]u8{ 73, 69, 78, 68 }),
    ihdr = @bitCast(u32, [_]u8{ 73, 72, 68, 82 }),
    srgb = @bitCast(u32, [_]u8{ 115, 82, 71, 66 }),
};

pub const ImgColorType = enum(u8) {
    greyscale = 0,
    truecolor = 2,
    index_colored = 3,
    greyscale_alpha = 4,
    truecolor_alpha = 6,

    pub fn checkAllowedBitDepths(self: ImgColorType, bit_depth: u8) !void {
        switch (self) {
            ImgColorType.greyscale => if (bit_depth == 1 or bit_depth == 2 or bit_depth == 4 or bit_depth == 6 or bit_depth == 16) return,
            ImgColorType.truecolor => if (bit_depth == 8 or bit_depth == 16) return,
            ImgColorType.index_colored => if (bit_depth == 1 or bit_depth == 2 or bit_depth == 4 or bit_depth == 8) return,
            ImgColorType.greyscale_alpha => if (bit_depth == 8 or bit_depth == 16) return,
            ImgColorType.truecolor_alpha => if (bit_depth == 8 or bit_depth == 16) return,
        }
        return MagicNumberErr.BitDepthColorTypeMissmatch;
    }
};
