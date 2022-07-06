pub const pngStreamStart = [_]u8{ 137, 80, 78, 71, 13, 10, 26, 10 };

pub const ChunkType = enum(u32) {
    idat = @bitCast(u32, [_]u8{ 73, 68, 65, 84 }),
    iend = @bitCast(u32, [_]u8{ 73, 69, 78, 68 }),
    ihdr = @bitCast(u32, [_]u8{ 73, 72, 68, 82 }),
};
