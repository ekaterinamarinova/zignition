const std = @import("std");
const net = std.net;
const server = @import("tcp/server.zig");
const debug = std.debug;

var Mutex = std.Thread.Mutex{};
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

var activeConnections = std.ArrayList(net.Server.Connection).init(allocator);

pub fn main() !void {
    // Initialize an instance of CanDataFrame
    const dataFrame =
    CanDataFrame.init(0x00, 0x7FF, 0b0000_0100, &[_]u16{ 0b01010101, 0x55, 0x03, 0x04 }, 0x07, 0x00, 0b01111111);
    const crc: u16 = dataFrame.calculateCRC();
    std.debug.print("CRC: {x}\n", .{crc});

    // const bus = try allocator.create(VirtualBus);
    // defer allocator.destroy(bus);

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    try start(8080, "127.0.0.1", &buffer);
}

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

    pub fn sendFrame() void {
        // Send a data frame
        // server.write(, bytes: []const u8)
    }
};

pub fn start(port: u16, address: []const u8, buff: *std.ArrayList(u8)) !void {
    // Start the virtual bus server
    var addr = try net.Address.parseIp4(address, port);
    debug.print("[main] Using address with ip: {s}, port: {d}\n", .{address, port});
    var options = net.Address.ListenOptions {
        .kernel_backlog = 128,
        .reuse_address = true,
        .reuse_port = true,
        .force_nonblocking = true,
    };

    var s: net.Server = try server.create(&addr, &options);
    defer s.deinit();
    var threadId: isize = 0;

    while (true) {
        debug.print("[main] Listening for connections...\n", .{});
        var client: net.Server.Connection = retry(&s);
        _ = &client;

        debug.print("[main] Client with address {any} connected, adding active connection..\n", .{client.address});
        try activeConnections.append(client);
        debug.print("[main] Active connections: {any}\n", .{activeConnections.items});
        threadId += 1;

        const thread = try std.Thread.spawn(
            .{},
            handleClient,
            .{buff, client, threadId}
        );

        thread.detach();
    }
}


fn retry(s: *net.Server) net.Server.Connection {
    var conn: ?net.Server.Connection = null;
    while (true) {
        if (conn != null) {
            return conn.?;
        }

        conn = s.accept() catch |err| {
            if (err == error.WouldBlock) {
                std.time.sleep(1 * std.time.ns_per_ms);
                continue;
            } else {
                return conn.?;
            }
        };
    }
}

pub fn handleClient(
    buff: *std.ArrayList(u8),
    client: net.Server.Connection,
    threadId: isize
) !void {
    debug.print("[Thread-{d}] Accepted connection from client..\n", .{threadId});
    debug.print("[Thread-{d}] Writing to the open stream...\n", .{threadId});
    const w_size = try client.stream.write("Hello, World!\n");

    if (w_size == 0) {
        debug.print("Nothing to write.\n", .{});
    }

    Mutex.lock();
    defer Mutex.unlock();

    const r_bytes = try server.read(client.stream, buff);

    if (r_bytes == buff.capacity) {
        debug.print("[Thread-{d}] Buffer is full!\n", .{threadId});
    }

    if (r_bytes > 0) {
        debug.print("[Thread-{d}] Read bytes from client: {s}\n", .{threadId, buff.items});
    }

    if (r_bytes < buff.capacity) {
        debug.print("[Thread-{d}] Reached end of stream.\n", .{threadId});
    }

    // Handle buffer after reading
    // Build frame
}


pub const CanNode = struct {
    isErrorActive: bool,
    isErrorPassive: bool,
    isBusOff: bool,
    transmitErrorCount: u8,
    receiveErrorCount: u8,

    pub fn init(isErrorActive: bool, isErrorPassive: bool, isBusOff: bool, transmitErrorCount: u8, receiveErrorCount: u8) CanNode {
        const node = CanNode {
            .isErrorActive = isErrorActive,
            .isErrorPassive = isErrorPassive,
            .isBusOff = isBusOff,
            .transmitErrorCount = transmitErrorCount,
            .receiveErrorCount = receiveErrorCount,
        };
        return node;
    }

    pub fn connect() void {
        // Connect to the bus
    }

    pub fn disconnect() void {
        // Disconnect from the bus
    }

    pub fn sendFrame() void {
        // Send a data frame
    }

    pub fn receiveFrame() void {
        // Receive a data frame
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


