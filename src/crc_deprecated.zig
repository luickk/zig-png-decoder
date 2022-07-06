const print = @import("std").debug.print;

// Make the table for a fast CRC
fn make_crc_table() [256]u32 {
    // /* Table of CRCs of all 8-bit messages. */
    var crc_table: [256]u32 = undefined;
    var c: u32 = undefined;
    var n: u32 = 0;
    var k: u32 = 0;

    while (n < 256) : (n += 1) {
        c = n;
        while (k < 8) : (k += 1) {
            if ((c & 1) != 0) {
                c = 0xedb88320 ^ (c >> 1);
            } else {
                c = c >> 1;
            }
        }
        crc_table[n] = c;
    }
    return crc_table;
}

fn update_crc(crc: u32, buff: []u8, crc_table: *[256]u32) u32 {
    var c = crc;
    var n: usize = 0;

    while (n < buff.len) : (n += 1) {
        print("{d} \n", .{buff[n]});
        c = crc_table[(c ^ buff[n]) & 0xff] ^ (c >> 8);
    }
    return c;
}

pub fn calcCRC(buff: []u8) u32 {
    // Update a running CRC with the bytes buf[0..len-1]--the CRC should be initialized to all 1's, and the transmitted value is
    // the 1's complement of the final running CRC (see the crc() routine below).
    var crc_table = make_crc_table();
    return update_crc(0xffffffff, buff, &crc_table) ^ 0xffffffff;
}
