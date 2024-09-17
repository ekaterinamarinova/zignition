const std = @import("std");
const t = std.testing;
const can = @import("bus.zig");
const node = @import("node.zig");
const serial = @import("serial.zig");
const bits = @import("/const/bits.zig").Bits;
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

test "serialize remote frame" {
    const rf  = can.CanRemoteFrame {
        .sof = 0b0,
        .arbitration = 0x01,
        .control = 0x02,
        .crc = 0x7FF3,
        .ack = 0x1,
        .eof = 0x7F,
    };

    const bytes = try serial.serializeRemoteFrame(rf);
    try t.expectEqual(44, bytes.items.len);
}

test "deserialize data frame" {
    const data = serial.createDataFrame();
    const serialized = try serial.serializeDataFrame(data);
    var result: can.CanUnion = undefined;
    var testCount: u32 = 0;
    for (serialized.items) |bit| {
        result = try serial.mapBitsToFrames(bit, testCount);
        testCount += 1;
    }

    var dataFrame: *can.CanDataFrame = undefined;

    switch (result) {
        can.CanUnion.CanDataFrame => {
            dataFrame = result.CanDataFrame;
            try std.testing.expectEqual(data.control, dataFrame.control);
            try std.testing.expectEqual(data.arbitration, dataFrame.arbitration);
            try std.testing.expectEqual(data.ack, dataFrame.ack);
            try std.testing.expectEqual(data.crc, dataFrame.crc);
            try std.testing.expectEqual(data.eof, dataFrame.eof);
        },
        else => {
            std.debug.print("Error deserializing data frame.\n", .{});
        }
    }

}

test "deserialize remote frame" {
    const rfp: *can.CanRemoteFrame = try allocator.create(can.CanRemoteFrame);
    rfp.* = can.CanRemoteFrame {
        .sof = 0b0,
        .arbitration = 0x01,
        .control = 0x04,
        .crc = 0x7FF3,
        .ack = 0x1,
        .eof = 0x7F,
    };
    const rfs = try serial.serializeRemoteFrame(rfp.*);
    try t.expectEqual(44, rfs.items.len);
    std.debug.print("{any}", .{rfs.items});

    var count: u32 = 0;
    var result: can.CanUnion = undefined;
    for (rfs.items) |bit| {
        result = try serial.mapBitsToFrames(bit, count);
        count += 1;
    }

    std.debug.print("\nExpected: {any}\n", .{rfp.*});
    std.debug.print("result code: {any}\n", .{result});

    switch (result) {
        can.CanUnion.CanRemoteFrame => {
            try t.expectEqual(0x01, result.CanRemoteFrame.*.arbitration);
            try t.expectEqual(0x04, result.CanRemoteFrame.*.control);
            try t.expectEqual(0x7FF3, result.CanRemoteFrame.*.crc);
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

    const bytes = try serial.serializeDataFrame(frame);

    //data lenght is 1 bit so rf bit size (44) + 1 = 45
    try t.expectEqual(52, bytes.items.len);
}