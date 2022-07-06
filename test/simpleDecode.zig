const std = @import("std");
const print = std.debug.print;
const PngDecoder = @import("src").PngDecoder;

const test_allocator = std.testing.allocator;

pub fn main() !void {
    var file = try std.fs.cwd().openFile("test/test.png", .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var decoder = PngDecoder.init(test_allocator);

    var buff: [4]u8 = undefined;
    while ((try in_stream.read(&buff)) != 0)
        try decoder.parse(buff);
}
