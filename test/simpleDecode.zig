const std = @import("std");
const print = std.debug.print;
const utils = @import("utils.zig");

const PngDecoder = @import("src").PngDecoder;
const pngEncoder = @import("src").pngEncoder;

pub fn main() !void {
    var file = try std.fs.cwd().openFile("test/test2.png", .{});
    defer file.close();

    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(!general_purpose_allocator.deinit());

    const gpa = general_purpose_allocator.allocator();

    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var decoder = PngDecoder.PngDecoder(@TypeOf(in_stream)).init(gpa, in_stream);
    defer decoder.deinit();

    try decoder.parse();

    var test_replic = try std.fs.cwd().createFile("test/test2_replica.png", .{});
    defer test_replic.close();

    var file_content = try pngEncoder.simpleEncodeRgba(gpa, decoder.img.bitmap_buff.?, decoder.img.width, decoder.img.height, decoder.img.bit_depth);
    defer (file_content.deinit());

    try test_replic.writeAll(file_content.items);
}
