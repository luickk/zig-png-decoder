const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const lib = b.addStaticLibrary("zig-png-decoder", "src/main.zig");
    lib.setBuildMode(mode);
    lib.install();

    const png_dec_tests = b.addTest("src/PngDecoder.zig");
    png_dec_tests.setBuildMode(mode);

    const png_enc_tests = b.addTest("src/pngEncoder.zig");
    png_enc_tests.setBuildMode(mode);

    const zlib_enc_tests = b.addTest("src/zlibStreamEnc.zig");
    zlib_enc_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&png_dec_tests.step);
    test_step.dependOn(&png_enc_tests.step);
    test_step.dependOn(&zlib_enc_tests.step);

    const test_decode = b.addExecutable("test_decode", "test/simpleDecodeTest.zig");
    test_decode.addPackagePath("src", "src/main.zig");
    test_decode.setBuildMode(mode);
    test_decode.install();

    const test_encode = b.addExecutable("test_encode", "test/simpleEncodeTest.zig");
    test_encode.addPackagePath("src", "src/main.zig");
    test_encode.setBuildMode(mode);
    test_encode.install();

    const test_encode_decode = b.addExecutable("test_encode_decode", "test/encodeDecodeTest.zig");
    test_encode_decode.addPackagePath("src", "src/main.zig");
    test_encode_decode.setBuildMode(mode);
    test_encode_decode.install();

    const itest_step = b.step("itest", "Run library integration tests");
    itest_step.dependOn(&test_encode.run().step);
    itest_step.dependOn(&test_decode.run().step);
    itest_step.dependOn(&test_encode_decode.run().step);
}
