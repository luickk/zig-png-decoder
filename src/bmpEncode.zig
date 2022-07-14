const std = @import("std");

const FileHeader = packed struct {
    signature: [2]u8,
    file_size: u32,
    reserved: u32,
    fileoffset_to_pixelarray: u32,
};

const BitMapInfoHeader = packed struct {
    dib_header_size: u32,
    width: u32,
    height: u32,
    planes: u16,
    bits_perpixel: u16,
    compression: u32,
    image_size: u32,
    y_pixel_permeter: u32,
    x_pixel_permeter: u32,
    num_colors_pallette: u32,
    mostimpcolor: u32,
    // red_ch_bm: u32,
    // green_ch_bm: u32,
    // blue_ch_bm: u32,
    // alpha_ch_bm: u32,
};

pub fn writeBitMapToBmp(bitmap: []u8, width: u32, height: u32, bits_pp: u16) !void {
    const bitmap_size = width * height * 3;
    const file_bmp_final = try std.fs.cwd().createFile("test/test_op.bmp", .{ .read = true });
    defer file_bmp_final.close();

    var file_header = FileHeader{
        .signature = "BM".*,
        .file_size = @truncate(u32, bitmap_size + @sizeOf(FileHeader) + @sizeOf(BitMapInfoHeader)),
        .reserved = 0,
        .fileoffset_to_pixelarray = @truncate(u32, @sizeOf(FileHeader) + @sizeOf(BitMapInfoHeader)),
    };
    var bitmap_info_header = BitMapInfoHeader{
        .dib_header_size = @truncate(u32, @sizeOf(BitMapInfoHeader)),
        .width = width,
        .height = height,
        .planes = 1,
        .bits_perpixel = bits_pp * 3,
        .compression = 0,
        .image_size = bitmap_size,
        .x_pixel_permeter = 0x130B,
        .y_pixel_permeter = 0x130B, // 72 dpi
        .num_colors_pallette = 0,
        .mostimpcolor = 0,
        // .red_ch_bm = @bitCast(u32, [4]u8{ 255, 0, 0, 0 }),
        // .green_ch_bm = @bitCast(u32, [4]u8{ 0, 255, 0, 0 }),
        // .blue_ch_bm = @bitCast(u32, [4]u8{ 0, 0, 255, 0 }),
        // .alpha_ch_bm = @bitCast(u32, [4]u8{ 0, 0, 0, 255 }),
    };

    _ = try file_bmp_final.writeAll(std.mem.asBytes(&file_header));
    _ = try file_bmp_final.writeAll(std.mem.asBytes(&bitmap_info_header));
    _ = try file_bmp_final.writeAll(bitmap);
}
