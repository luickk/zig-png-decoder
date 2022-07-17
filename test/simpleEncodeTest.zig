const std = @import("std");
const print = std.debug.print;

const pngEncoder = @import("src").pngEncoder;

const test_bm = @import("test_imgs/test2_bm.zig");
const test_allocator = std.testing.allocator;

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(!general_purpose_allocator.deinit());
    const gpa = general_purpose_allocator.allocator();

    var test_img_bm = @bitCast([]u8, std.mem.sliceAsBytes(&test_bm.img_bm));

    var test_replic = try std.fs.cwd().createFile("test/test_imgs/res/enc_test_res.png", .{});
    defer test_replic.close();

    try pngEncoder.simpleEncodeRgba(gpa, test_replic.writer(), test_img_bm, 50, 50, 8);
}
