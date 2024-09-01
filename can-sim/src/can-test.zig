const std = @import("std");
const testing = std.testing;
const main = @import("can-main.zig");

export fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try testing.expect(add(3, 7) == 10);
}

//TODO test basic send remote / receive data frame logic
test "send remote receive data frame" {

}

//TODO test bit stuffing error case
test "bit stuffing error" {}

//TODO test error passive / error active / bus off mode
test "enter error passive mode" {}


test "main test" {
    // main.CanDataFrame.init(sof: u8, arbitration: u16, control: u8, data: []const u16, crc: u16, ack: u8, eof: u8)
}
