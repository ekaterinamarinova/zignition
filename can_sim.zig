const std = @import("std");

pub const CanNode = struct {
    isErrorActive: bool,
    isErrorPassive: bool,
    isBusOff: bool,
    transmitErrorCount: u8,
    receiveErrorCount: u8,

    pub fn init(isErrorActive: bool, isErrorPassive: bool, isBusOff: bool, transmitErrorCount: u8, receiveErrorCount: u8) CanNode {
        const node = CanNode{
            .isErrorActive = isErrorActive,
            .isErrorPassive = isErrorPassive,
            .isBusOff = isBusOff,
            .transmitErrorCount = transmitErrorCount,
            .receiveErrorCount = receiveErrorCount,
        };
        return node;
    }
};

pub const CanDataFrame = struct {
    sof: u8,
    arbitration: u16,
    control: u8,
    data: []const u8,
    crc: u16,
    ack: u8,
    eof: u8,

    pub fn init(sof: u8, arbitration: u16, control: u8, data: []const u8, crc: u16, ack: u8, eof: u8) CanDataFrame {
        const frame = CanDataFrame{
            .sof = sof,
            .arbitration = arbitration,
            .control = control,
            .data = data,
            .crc = crc,
            .ack = ack,
            .eof = eof,
        };

        return frame;
    }

    pub fn calculateCRC() u16 {
        // Calculate the CRC of the data
    }
};

pub const CanRemoteFrame = struct {
    sof: u8,
    arbitration: u16,
    control: u8,
    crc: u16,
    ack: u8,
    eof: u8,

    pub fn init(sof: u8, arbitration: u16, control: u8, crc: u16, ack: u8, eof: u8) CanRemoteFrame {
        const frame = CanRemoteFrame{
            .sof = sof,
            .arbitration = arbitration,
            .control = control,
            .crc = crc,
            .ack = ack,
            .eof = eof,
        };

        return frame;
    }

    pub fn calculateCRC() u16 {
        // Calculate the CRC of the data
    }
};

pub const CanErrorFrame = struct {
    errorFlag: u8,
    errorDelimiter: u8,

    pub fn init(errorFlag: u8, errorDelimiter: u8) CanErrorFrame {
        const frame = CanErrorFrame{
            .errorFlag = errorFlag,
            .errorDelimiter = errorDelimiter,
        };

        return frame;
    }
};

pub const CanInterframeSpacing = struct {
    intermission: u8,
    suspendTransmission: u8,
    busIdle: u8,

    pub fn init(intermission: u8, suspendTransmission: u8, busIdle: u8) CanInterframeSpacing {
        const spacing = CanInterframeSpacing{
            .intermission = intermission,
            .suspendTransmission = suspendTransmission,
            .busIdle = busIdle,
        };

        return spacing;
    }
};

pub fn main() !void {
    // Initialize an instance of CanNode
    const node = CanNode.init(
        false, // isErrorActive
        false, // isErrorPassive
        false, // isBusOff
        0x01, // transmitErrorCount
        0x00, // receiveErrorCount
    );

    // Initialize an instance of CanDataFrame
    const frame = CanDataFrame.init(
        0x01, // sof
        0x123, // arbitration
        0x01, // control
        &[_]u8{ 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08 }, // data
        0xABCD, // crc
        0x01, // ack
        0x02, // eof
    );

    // Initialize an instance of CanRemoteFrame
    const remoteFrame = CanRemoteFrame.init(
        0x01, // sof
        0x123, // arbitration
        0x01, // control
        0xABCD, // crc
        0x01, // ack
        0x02, // eof
    );

    // Initialize an instance of CanErrorFrame
    const errorFrame = CanErrorFrame.init(
        0x01, // errorFlag
        0x02, // errorDelimiter
    );

    // Initialize an instance of CanInterframeSpacing
    const spacing = CanInterframeSpacing.init(
        0x01, // intermission
        0x02, // suspendTransmission
        0x03, // busIdle
    );

    std.debug.print("CanNode: \n", .{});
    std.debug.print("isErrorActive: {} \n", .{node.isErrorActive});
    std.debug.print("isErrorPassive: {} \n", .{node.isErrorPassive});
    std.debug.print("isBusOff: {} \n", .{node.isBusOff});
    std.debug.print("\n", .{});
    std.debug.print("CanDataFrame: \n", .{});
    std.debug.print("sof: {} \n", .{frame.sof});
    std.debug.print("arbitration: {} \n", .{frame.arbitration});
    std.debug.print("control: {} \n", .{frame.control});
    std.debug.print("data: \n", .{});
    for (frame.data) |byte| {
        std.debug.print("byte: {} \n", .{byte});
    }
    std.debug.print("crc: {} \n", .{frame.crc});
    std.debug.print("ack: {} \n", .{frame.ack});
    std.debug.print("eof: {} \n", .{frame.eof});
    std.debug.print("\n", .{});
    std.debug.print("CanRemoteFrame: \n", .{});
    std.debug.print("sof: {} \n", .{remoteFrame.sof});
    std.debug.print("arbitration: {} \n", .{remoteFrame.arbitration});
    std.debug.print("control: {} \n", .{remoteFrame.control});
    std.debug.print("crc: {} \n", .{remoteFrame.crc});
    std.debug.print("ack: {} \n", .{remoteFrame.ack});
    std.debug.print("eof: {} \n", .{remoteFrame.eof});
    std.debug.print("\n", .{});
    std.debug.print("CanErrorFrame: \n", .{});
    std.debug.print("errorFlag: {} \n", .{errorFrame.errorFlag});
    std.debug.print("errorDelimiter: {} \n", .{errorFrame.errorDelimiter});
    std.debug.print("\n", .{});
    std.debug.print("CanInterframeSpacing: \n", .{});
    std.debug.print("intermission: {} \n", .{spacing.intermission});
    std.debug.print("suspendTransmission: {} \n", .{spacing.suspendTransmission});
    std.debug.print("busIdle: {} \n", .{spacing.busIdle});
}
