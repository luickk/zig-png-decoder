# Zig Png Decoder

This lib provides a minimal parser that supports only the very basic color types, compression filtering or pass extraction.
The decoder takes a reader and returns the bitmap and decoded meta information.

Example:

```zig
	var file = try std.fs.cwd().openFile("test/test.png", .{});
    defer file.close();

    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(!general_purpose_allocator.deinit());

    const gpa = general_purpose_allocator.allocator();

    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var decoder = PngDecoder.PngDecoder(@TypeOf(in_stream)).init(gpa, in_stream);
    defer decoder.deinit();

    try decoder.parse();
```
