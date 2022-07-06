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

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&png_dec_tests.step);

    const test_decode = b.addExecutable("test_decode", "test/simpleDecode.zig");
    test_decode.addPackagePath("src", "src/main.zig");
    test_decode.setBuildMode(mode);
    test_decode.install();

    const itest_step = b.step("itest", "Run library integration tests");
    itest_step.dependOn(&test_decode.run().step);
}
