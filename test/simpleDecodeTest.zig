const std = @import("std");
const print = std.debug.print;

const PngDecoder = @import("src").PngDecoder;
const pngEncoder = @import("src").pngEncoder;

pub fn main() !void {
    var file = try std.fs.cwd().openFile("test/test_imgs/test2.png", .{});
    defer file.close();

    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(!general_purpose_allocator.deinit());

    const gpa = general_purpose_allocator.allocator();

    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var decoder = PngDecoder.PngDecoder(@TypeOf(in_stream)).init(gpa, in_stream);
    defer decoder.deinit();

    try decoder.parse();
}
