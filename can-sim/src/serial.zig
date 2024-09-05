const std = @import("std");
const can = @import("can-main.zig");
const log= std.log;
const t = std.testing;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

const ProcessingError = error {
    UnexpectedBit,
    ByteOverflow,
};

test "serialize remote frame" {
    const rf = can.CanRemoteFrame {
        .sof = 0b0,
        .ack = 0x00,
        .arbitration = 0x01,
        .control = 0x01,
        .crc = 0x1A,
        .eof = 0xFF,
    };

    const bytes = try serializeRemoteFrame(rf);

    std.debug.print("{any}", .{bytes.items});
    // try t.expectEqual(45, bytes.len);
}

test "deserialize remote frame" {
    const exp = can.CanRemoteFrame {
        .sof = 0b0,
        .ack = 0x00,
        .arbitration = 0x01,
        .control = 0x01,
        .crc = 0x1A,
        .eof = 0xFF,
    };

    const rf = try serializeRemoteFrame(exp);

    var result: can.CanRemoteFrame = undefined;

    for (rf.items) |bit| {
        result = deserializeRemoteFrame(bit);
    }

    t.expectEqual(exp, result);
}

pub fn deserializeRemoteFrame(bit: bool) !can.CanRemoteFrame {
    var buff = std.ArrayList(bool).init(allocator);
    var count: u32 = 0;
    var frame = can.CanRemoteFrame{
        .sof = 0,
        .arbitration = 0,
        .control = 0,
        .crc = 0,
        .ack = 0,
        .eof = 0,
    };

    //TODO fix type casting
    const i: u8 = @intFromBool(bit);
    switch (count) {
        0 => {
            frame.sof = 0;
            count += 1;
        },
        1...13 => {
            if (count == 12 and bit != true) {
                return error.UnexpectedBit;
            }

            frame.arbitration |= i << (11 - count);
            count += 1;
        },
        14...19 => {
            frame.control |= i << (5 - count);
            count += 1;
        },
        20...35 => {
            frame.crc |= i << (15 - count);
            count += 1;
        },
        36...37 => {
            frame.ack |= i << (1 - count);
            count += 1;
        },
        38...44 => {
            frame.eof |= bit << (6 - count);
            count += 1;
        },
        else => {
            return error.ByteOverflow;
        },
    }

    buff.append(bit);

    return frame;
}

pub fn serializeRemoteFrame(frame: can.CanRemoteFrame) !std.ArrayList(bool) {
    var boolBuff = std.ArrayList(bool).init(allocator);
    // sof is always 1 dominant bit
    try boolBuff.append(false);

    var count: u4 = 0;
    for (0..count) |_| {
        const bit: u16 = frame.arbitration >> (11 - count) & 1;
        try append(bit, &boolBuff);
        count += 1;
    }

    var count2: u3 = 0;
    for (0..6) |_| {
        const bit: u8 = frame.control >> (5 - count2) & 1;
        try append(bit, &boolBuff);
        count2 += 1;
    }

    var count3: u8 = 0;
    for (0..16) |_| {
        const a: u8 = (15 - count3) & 1;
        const b: u4 = @intCast(a);
        const bit: u16 = frame.crc >> b;
        try append(bit, &boolBuff);
        count3 += 1;
    }

    count2 = 0;
    for (0..2) |_| {
        const bit: u8 = frame.ack >> (1 - count2) & 1;
        try append(bit, &boolBuff);
        count2 += 1;
    }

    count2 = 0;
    for (0..7) |_| {
        const bit: u8 = frame.eof >> (6 - count2) & 1;
        try append(bit, &boolBuff);
        count2 += 1;
    }

    return boolBuff;
}

fn append(bit: u16, boolBuff: *std.ArrayList(bool)) !void {
    if (bit == 0) {
        try boolBuff.append(false);
    } else {
        try boolBuff.append(true);
    }
}