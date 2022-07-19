# Zig Png Decoder

This lib provides a minimal parser that supports truecolor and truecolor_alpha color types en/decode and all critical chunks. For compression,filtering or pass extraction only  basic methods are supported.

The lib also contains a deflate compressor (`src/compressor`) which has not been implemented by me, but has been taken from the current master of the zig std lib, since the current version of the zig std did not work correctly(caused memory leaks which could not be fixed).
The master branches zlib also only supported zlib stream decoding, but no encoding. My own implementation can be found in `src/zlibStreamEnc.zig` and only supports basic deflate, which conforms with RFC 1950 wihtout dict.

## Tests

There are unit tests for all modules which can be run with `zig test`, as well as integration tests (with samples) `zig itest`. The results of the 3 integration tests (simple encode, simple decode, encode decode) can be checked out in `test/test_imgs/res`.

## Examples

Decoding:

```zig
var file = try std.fs.cwd().openFile("test/test_imgs/test.png", .{});
defer file.close();

var buf_reader = std.io.bufferedReader(file.reader());
var in_stream = buf_reader.reader();

var decoder = PngDecoder.PngDecoder(@TypeOf(in_stream)).init(std.testing.allocator, in_stream);
defer decoder.deinit();

var img = try decoder.parse();

var bm_buff = try img.bitmap_reader.readAllAlloc(std.testing.allocator, std.math.maxInt(usize));
```

Encoding:

```zig
// contains the raw bitmap of test_imgs/test2.png
const test_bm = @import("test/test_imgs/test2_bm.zig");

var test_img_bm = @bitCast([]u8, std.mem.sliceAsBytes(&test_bm.img_bm));
var test_replic = try std.fs.cwd().createFile("res.png", .{});
defer test_replic.close();

try pngEncoder.encodePng(std.testing.allocator, test_replic.writer(), test_img_bm, magicNumbers.ColorType.truecolor_alpha, 50, 50, 8);
```


