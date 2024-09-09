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
const Tag = enum {
    CanDataFrame,
    CanErrorFrame,
    CanRemoteFrame,
    CanInterframeSpacing,
};

const CanUnion = union(enum) {
    data: can.CanDataFrame,
    err: can.CanErrorFrame,
    remote: can.CanRemoteFrame,
    ifs: can.CanInterframeSpacing,
};

const Frames = struct {
    tag: Tag,
    value: CanUnion
};

test "serialize remote frame" {
    const rf  = can.CanRemoteFrame {
        .sof = 0b0,
        .arbitration = 0x01,
        .control = 0x02,
        .crc = 0x7FF3,
        .ack = 0x1,
        .eof = 0x7F,
    };

    const bytes = try serializeRemoteFrame(rf);
    try t.expectEqual(44, bytes.items.len);
}

test "deserialize remote frame" {
    const rfr = try allocator.create(can.CanRemoteFrame);
    rfr.* = can.CanRemoteFrame {
        .sof = 0b0,
        .arbitration = 0x01,
        .control = 0x04,
        .crc = 0x7FF3,
        .ack = 0x1,
        .eof = 0x7F,
    };
    const rfs = try serializeRemoteFrame(rfr.*);

    std.debug.print("{any}", .{rfs.items});

    var count: u32 = 0;
    var result: i8 = 0;
    for (rfs.items) |bit| {
        // std.debug.print("Mapping bit {d} {}\n", .{count, bit});
        result = try mapBitsToFrames(bit, count, rfr);
        count += 1;
    }

    std.debug.print("\nExpected: {any}\n", .{rfr.*});
    std.debug.print("result code: {d}\n", .{result});

    try t.expectEqual(0x01, rfr.arbitration);
    try t.expectEqual(0x04, rfr.control);
    try t.expectEqual(0x7FF3, rfr.crc);
}

var isRemoteFrame = false;
var identifier = std.ArrayList(bool).init(allocator);

pub fn mapBitsToFrames(bit: bool, order: u32, rf: *can.CanRemoteFrame) !i8 {
    // if sof detected from caller
    const resultErr: i8 = -1;
    const resultWait: i8 = 0;
    const resultRfOk: i8 = 1;

    switch (order) {
        0 => {
            // sof is always dominant
            if (bit != false) {
                // return createRemoteFrameEmpty();
                return resultErr;
            }
            return resultWait;
        },
        1...12 => {
            // arbitration field
            //1..12 -> identifier, store and pass it to a data frame
            try identifier.append(bit);
            if (order == 12 and bit == true) {
                // rtr bit recessive -> create remote frame
                // set isremoteframe to true
                isRemoteFrame = true;
                return resultWait;
            } else {
                // create data frame
                // return createRemoteFrameEmpty();
                return resultWait;
            }
        },
        13...44 => {
            if (isRemoteFrame) {
                try deserializeRemoteFrame(bit, order, rf);
                if (43 == order) {
                    return resultRfOk;
                }
                return resultWait;
            } else {
                // create data frame
                return error.UnexpectedBit;
            }
        },
        else => {
            return error.UnexpectedBit;
        }
    }
}

pub fn deserializeRemoteFrame(bit: bool, bitPosition: u32, rf: *can.CanRemoteFrame) !void {
    log.debug("Bit position: {d}\n", .{bitPosition});
    var f = rf.*;
    f.sof = 0;
    f.arbitration = 0x01;

    //TODO erroor handling
    switch (bitPosition) {
        13...18 => {
            // last two bits are reserved, must be dominant
            if ((bitPosition == 18 or bitPosition == 19) and bit != false) {
                return error.UnexpectedBit;
            }

            f.control <<= 1;
            if (bit) {
                f.control |= 1;
            }

        },
        19...34 => {
            f.crc <<= 1;

            if (bit) {
                f.crc |= 1;
            }

        },
        35...36 => {
            //TODO time to check crc and return ack?
            f.ack <<= 1;

            if (bit) {
                f.ack |= 1;
            }
        },
        37...43 => {
            if (bit != true) {
                return error.UnexpectedBit;
            }

            f.eof <<= 1;

            if (bit) {
                f.eof |= 1;
            }
        },
        else => {
            return error.ByteOverflow;
        },
    }

   rf.* = f;
}

pub fn serializeRemoteFrame(frame: can.CanRemoteFrame) !std.ArrayList(bool) {
    var boolBuff = std.ArrayList(bool).init(allocator);
    // sof is always 1 dominant bit
    try boolBuff.append(false);

    var count: u4 = 0;
    for (0..12) |_| {
        const bit: u12 = frame.arbitration >> (11 - count) & 1;
        try append(bit, &boolBuff);
        count += 1;
    }
    var count2: u3 = 0;
    for (0..6) |_| {
        const bit: u6 = frame.control >> (5 - count2) & 1;
        try append(bit, &boolBuff);
        count2 += 1;
    }

    var count3: u4 = 0;
    for (0..16) |_| {
        const a: u4 = (15 - count3);
        const bit: u16 = (frame.crc >> a) & 1;
        try append(bit, &boolBuff);
        if (count3 != 15) {
            count3 += 1;
        }
    }

    count2 = 0;
    for (0..2) |_| {
        const a: u1 = @intCast(count2);
        const bit: u2 = frame.ack >> (1 - a) & 1;
        try append(bit, &boolBuff);
        count2 += 1;
    }

    count2 = 0;
    for (0..7) |_| {
        const bit: u7 = frame.eof >> (6 - count2) & 1;
        try append(bit, &boolBuff);
        count2 += 1;
    }

    return boolBuff;
}

fn append(bit: u16, boolBuff: *std.ArrayList(bool)) !void {
    if (bit == 0) {
        try boolBuff.append(false);
    } else if (bit == 1) {
        try boolBuff.append(true);
    }
}

pub fn createRemoteFrameEmpty() can.CanRemoteFrame {
    return can.CanRemoteFrame{
        .sof = 0,
        .arbitration = 0x01,
        .control = 0,
        .crc = 0,
        .ack = 0,
        .eof = 0,
    };
}