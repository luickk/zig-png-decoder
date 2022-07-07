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
    // var lastPS = decoder.parser_state;
    // var lastPCS = decoder.parser_chunk_state;
    // print("init parser state: {}; init in chunk state: {} \n", .{ decoder.parser_state, decoder.parser_chunk_state });

    var buff: [1]u8 = undefined;
    while ((try in_stream.read(&buff)) != -1) {
        if (try decoder.parse(buff)) {
            print("img parsed! \n", .{});
            return;
        }

        // if (decoder.parser_state != lastPS or decoder.parser_chunk_state != lastPCS)
        //     print("parser state: {}; in chunk state: {} \n", .{ decoder.parser_state, decoder.parser_chunk_state });
        // lastPS = decoder.parser_state;
        // lastPCS = decoder.parser_chunk_state;
    }
}
