const std = @import("std");
const testing = std.testing;
const main = @import("main.zig");

export fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try testing.expect(add(3, 7) == 10);
}

test "main test" {
    // main.CanDataFrame.init(sof: u8, arbitration: u16, control: u8, data: []const u16, crc: u16, ack: u8, eof: u8)
}
