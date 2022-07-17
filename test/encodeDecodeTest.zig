const std = @import("std");
const print = std.debug.print;

const PngDecoder = @import("src").PngDecoder;
const pngEncoder = @import("src").pngEncoder;

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(!general_purpose_allocator.deinit());
    const gpa = general_purpose_allocator.allocator();

    // decode test png
    var file = try std.fs.cwd().openFile("test/test_imgs/test.png", .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var decoder = PngDecoder.PngDecoder(@TypeOf(in_stream)).init(gpa, in_stream);
    defer decoder.deinit();

    var img = try decoder.parse();
    var bm_buff = try img.bitmap_reader.readAllAlloc(gpa, std.math.maxInt(usize));
    defer gpa.free(bm_buff);

    // encode decoded bitmap
    var test_replic = try std.fs.cwd().createFile("test/test_imgs/res/enc_dec_test_res.png", .{});
    defer test_replic.close();

    try pngEncoder.simpleEncodeRgba(gpa, test_replic.writer(), bm_buff, img.width, img.height, img.bit_depth);
}
