const std = @import("std");
const can = @import("can-main.zig");
const bits = @import("const/bits.zig").Bits;
const log= std.log;
const t = std.testing;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();
var rfp: *can.CanRemoteFrame = undefined;
var dfp: *can.CanDataFrame = undefined;

var isRemoteFrame = false;
var isDataFrame = false;
var identifier = std.ArrayList(bool).init(allocator);

const ProcessingError = error {
    UnexpectedBit,
    ByteOverflow,
};

const Tag = enum {
    CanDataFrame,
    CanErrorFrame,
    CanRemoteFrame,
    CanInterframeSpacing
};

const CanUnion = union(Tag) {
    CanDataFrame: can.CanDataFrame,
    CanErrorFrame: can.CanErrorFrame,
    CanRemoteFrame: can.CanRemoteFrame,
    CanInterframeSpacing: can.CanInterframeSpacing
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
    rfp = try allocator.create(can.CanRemoteFrame);
    rfp.* = can.CanRemoteFrame {
        .sof = 0b0,
        .arbitration = 0x01,
        .control = 0x04,
        .crc = 0x7FF3,
        .ack = 0x1,
        .eof = 0x7F,
    };
    const rfs = try serializeRemoteFrame(rfp.*);
    try t.expectEqual(44, rfs.items.len);
    std.debug.print("{any}", .{rfs.items});

    var count: u32 = 0;
    var result: CanUnion = undefined;
    for (rfs.items) |bit| {
        result = try mapBitsToFrames(bit, count);
        count += 1;
    }

    std.debug.print("\nExpected: {any}\n", .{rfp.*});
    std.debug.print("result code: {any}\n", .{result});

    switch (result) {
        CanUnion.CanRemoteFrame => {
            try t.expectEqual(0x01, rfp.arbitration);
            try t.expectEqual(0x04, rfp.control);
            try t.expectEqual(0x7FF3, rfp.crc);
        },
        else => {
            std.debug.print("Unexpected result: {any}\n", .{result});
        }
    }

}

test "serialize data frame" {
    var data = [_]u8{0b111};

    const frame = can.CanDataFrame{
        .sof = 0b0,
        .arbitration = 0b000000000100,
        .control = 0b000100,
        .data = data[0..],
        .crc = can.calculateCRC(&data),
        .ack = 0b1,
        .eof = 0x7F,
    };

    const bytes = try serializeDataFrame(frame);

    //data lenght is 1 bit so rf bit size (44) + 1 = 45
    try t.expectEqual(52, bytes.items.len);
}

var dFieldLastBit: u8 = undefined;
test "deserialize data frame" {
    dFieldLastBit = bits.DataFieldFirstBit.value();

    var data = [_]u8{0b11111000, 0b10};
    const frame = can.CanDataFrame{
        .sof = 0b0,
        .arbitration = 0b000000000100,
        .control = 0b001000,
        .data = &data,
        .crc = can.calculateCRC(&data),
        .ack = 0b1,
        .eof = 0x7F,
    };

    var inData = [_]u8{0, 0};
    dfp = try allocator.create(can.CanDataFrame);
    dfp.* = can.CanDataFrame {
        .sof = 0b0,
        .arbitration = 0b0,
        .control = 0b0,
        .data = &inData,
        .crc = 0,
        .ack = 0,
        .eof = 0,
    };

    std.debug.print("Frame vals: {any} \n", .{frame});
    const bytes = try serializeDataFrame(frame);

    try t.expectEqual(60, bytes.items.len);
    std.debug.print("Serialized frame: {any}\n", .{bytes.items});


    var count: u32 = 0;
    for (bytes.items) |bit| {
        // std.debug.print("Bit: {}, count: {d} \n", .{bit, count});
        _ = try mapBitsToFrames(bit, count);
        count += 1;
    }

    std.debug.print("Expected data frame: {any}\n", .{frame});
    std.debug.print("Actual data frame: {any}\n", .{dfp.*});
    try t.expectEqual(0b000000000100, dfp.arbitration);
}

pub fn allocateRemoteFrame() *can.CanRemoteFrame {
    return try allocator.create(can.CanRemoteFrame);
}

pub fn mapBitsToFrames(bit: bool, order: u32) !CanUnion {
    // if sof detected from caller
    switch (order) {
        0 => {
            // sof is always dominant
            if (bit != false) {
                return error.UnexpectedBit;
            }
        },
        1...12 => {
            // arbitration field
            try identifier.append(bit);
            if (order == 12 and bit == true) {
                // rtr bit recessive -> create remote frame
                std.debug.print("is remote frame..\n", .{});
                isRemoteFrame = true;
            } else {
                isDataFrame = true;
            }
        },
        13...108 => {
            if (isRemoteFrame) {
                try deserializeRemoteFrame(bit, order, rfp);
                // last rf bit
                if (43 == order) {
                    std.debug.print("Setting is remote frame to false\n", .{});
                    isRemoteFrame = false;
                    return CanUnion{ .CanRemoteFrame = rfp.* };
                }
            } else {
                try deserializeDataFrame(bit, order, dfp, identifier);
                return CanUnion{ .CanDataFrame = dfp.* };
            }
        },
        else => {
            return error.UnexpectedBit;
        }

    }

    return CanUnion{.CanErrorFrame = undefined};
}

pub fn serializeDataFrame(frame: can.CanDataFrame) !std.ArrayList(bool) {
    var boolBuff = std.ArrayList(bool).init(allocator);
    // sof is always 1 dominant bit
    try boolBuff.append(false);

    var count: u4 = 0;
    for (0..12) |_| {
        const bit: u12 = frame.arbitration >> (11 - count) & 1;
        try append(bit, &boolBuff);
        count += 1;
    }

    const dLength: u6 = (frame.control >> 2) & 0xF;
    // std.debug.print("Data lenght is: {d}\n", .{dLength});

    var count2: u3 = 0;
    for (0..6) |_| {
        const bit: u6 = frame.control >> (5 - count2) & 1;
        try append(bit, &boolBuff);
        count2 += 1;
    }

    count2 = 0;
    // std.debug.print("Full data is: {any} \n", .{frame.data});

    var byteC: u8 = 0;
    for (frame.data) |byte| {
        // std.debug.print("Enter loop data item {b}\n", .{byte});
        if (dLength == byteC) {
            break;
        }
        // std.debug.print("Byte: {b}\n", .{byte});
        for (0..8) |_| {
            const bit: u8 = byte >> (7 - count2) & 1;
            // std.debug.print(" Bit: {b} \n", .{bit});
            try append(bit, &boolBuff);

            if (count2 != 7) {
                count2 += 1;
            }
        }

        count2 = 0;
        byteC += 1;
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

var dLen: u8 = 0;
var bitBuff: u8 = 0;
var bitCount: u8 = 0;
var byteCount: u8 = 0;
var dataPos: u8 = 0;
pub fn deserializeDataFrame(bit: bool, bitPosition: u32, df: *can.CanDataFrame, id: std.ArrayList(bool)) !void {
    var f = df.*;

    for (id.items) |b| {
        f.arbitration <<= 1;
        if (b) {
            f.arbitration |= 1;
        }
    }

    if (bitPosition <= bits.ControlFieldLastBit.value()) {
        //TODO actually first two bits are reserved, fix that
        // last two bits are reserved, must be dominant
        // if ((bitPosition == bits.ControlFieldLastBit.value()) and bit == false) {
        //     return error.UnexpectedBit;
        // }

        f.control <<= 1;
        if (bit) {
            f.control |= 1;
        }

        if (bitPosition == 18) {
            dLen = ((f.control >> 2) & 0xF) * 8;
            dFieldLastBit = bits.DataFieldFirstBit.value() + dLen;
            dataPos = 19 + dLen;
        }
    }


    if (bitPosition > bits.ControlFieldLastBit.value() and
        bitPosition <= dFieldLastBit) {

        bitBuff = (bitBuff << 1) | @intFromBool(bit);
        bitCount += 1;

        std.debug.print(" Bit val: {} Bit buff: {b} bit count: {d}\n", .{bit, bitBuff, bitCount});

        if(bitCount == 8) {
            std.debug.print("byte count: {d}, data: {any}, bitBuff {b}\n", .{byteCount, f.data, bitBuff});
            // std.debug.print("bit count: {d} bit val {} bit position {d} dlen {d}\n", .{bitCount, bit, bitPosition, dLen});
            bitCount = 0;

            f.data[byteCount] = bitBuff;
            byteCount += 1;
            bitBuff = 0;

            if (byteCount == ((dLen/8) - 1)) {
                return;
            }
        }
    }

    if (bitPosition > dFieldLastBit and
        bitPosition <= (bits.CrcFieldLastBit.value() + dLen)) {
        f.crc <<= 1;

        if (bit) {
            f.crc |= 1;
        }

    }

    if (bitPosition > (bits.CrcFieldLastBit.value() + dLen) and
        bitPosition <= (bits.AckFieldLastBit.value() + dLen)) {
        f.ack <<= 1;

        if (bit) {
            f.ack |= 1;
        }
    }

    if (bitPosition > (bits.AckFieldLastBit.value() + dLen) and
        bitPosition <= bits.EOFLastBit.value() + dLen) {
        if (bit != true) {
            return error.UnexpectedBit;
        }

        f.eof <<= 1;

        if (bit) {
            f.eof |= 1;
        }
    }

    df.* = f;
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
            if ((bitPosition == 18) and bit != false) {
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
            //TODO time to check crc and return ack? some callback function?
            f.ack <<= 1;

            if (bit) {
                f.ack |= 1;
                // an ack notifies the node that it has to send one dominant bit
                // and the transmitter node has to wait for the dominant ack bit
                // and continue with the eof + ifs?
            }
        },
        37...44 => {
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