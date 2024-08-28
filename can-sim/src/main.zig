const std = @import("std");

pub const VirtualBus = struct {
    nodes: []const CanNode,
    frames: []const CanDataFrame,
    remoteFrames: []const CanRemoteFrame,
    errorFrames: []const CanErrorFrame,
    spacing: CanInterframeSpacing,

    pub fn init(nodes: []const CanNode, frames: []const CanDataFrame, remoteFrames: []const CanRemoteFrame, errorFrames: []const CanErrorFrame, spacing: CanInterframeSpacing) VirtualBus {
        const bus = VirtualBus{
            .nodes = nodes,
            .frames = frames,
            .remoteFrames = remoteFrames,
            .errorFrames = errorFrames,
            .spacing = spacing,
        };

        return bus;
    }
};

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
    // 1 dominant bit (0)
    sof: u8,
    // id - 11b; rtr - 1b dominant (0)
    arbitration: u16,
    // 2b dominant, 4b data len
    control: u8,
    // 8B, transmittet MSB first
    data: []const u16,
    // 15 bit register; 1b recessive delimiter
    crc: u16,

    // 1b ack slot 1b ack delimiter;
    // transmitting station sends [11]
    // receiver sends to transmitter [10] if received correctly
    ack: u8,
    // 7 recessive bits (1)
    eof: u8,

    pub fn init(sof: u8, arbitration: u16, control: u8, data: []const u16, crc: u16, ack: u8, eof: u8) CanDataFrame {
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

    pub fn calculateCRC(self: @This()) u16 {
        const generatorPolynomial: u16 = 0x4599;
        var crcRegister: u16 = 0;

        for (self.data) |byte| {
            std.debug.print("byte: {x}\n", .{byte});
            var count: u4 = 0;
            for (0..8) |_| {
                std.debug.print("Inner loop: {}\n", .{count});
                const next = (byte >> (7 - count)) & 1;
                std.debug.print("next: {}\n", .{next});
                count = count + 1;

                crcRegister = (crcRegister << 1) & 0x7FFF;
                std.debug.print("crcRegister after left shift and mask: {}\n", .{crcRegister});
                if (next != 0) {
                    crcRegister ^= generatorPolynomial;
                }
            }
        }

        //add recessive bit delimiter at the end
        crcRegister = (crcRegister << 1) | 1;
        std.debug.print("=crcRegister after loop: {}=\n", .{crcRegister});
        return crcRegister;
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
    // Initialize an instance of CanDataFrame
    const dataFrame =
        CanDataFrame.init(0x00, 0x7FF, 0b0000_0100, &[_]u16{ 0b01010101, 0x55, 0x03, 0x04 }, 0x07, 0x00, 0b01111111);
    const crc: u16 = dataFrame.calculateCRC();

    std.debug.print("CRC: {x}\n", .{crc});
}
