const std = @import("std");
const net = std.net;
const log = std.log;

var Mutex = std.Thread.Mutex{};
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();
var map = std.AutoHashMap(u16, bool).init(allocator);

var activeConnections = std.ArrayList(net.Server.Connection).init(allocator);

pub fn main() !void {
    var buffer = std.ArrayList(bool).init(allocator);
    defer buffer.deinit();
    defer map.deinit();

    //TODO handle node reconnects, currently new thread is created on reconnect
    try start(8085, "127.0.0.1", &buffer);
}

pub fn start(port: u16, address: []const u8, buff: *std.ArrayList(bool)) !void {
    // Start the virtual bus server
    const addr = try net.Address.parseIp4(address, port);
    log.info("[main] Using address with ip: {s}, port: {d}\n", .{ address, port });
    const options = net.Address.ListenOptions{
        .kernel_backlog = 128,
        .reuse_address = true,
        .reuse_port = true,
        .force_nonblocking = true,
    };

    var s: net.Server = try net.Address.listen(addr, options);
    defer s.deinit();
    var threadId: isize = 0;

    while (true) {
        log.info("[main] Listening for connections...\n", .{});
        var client: net.Server.Connection = retry(&s);
        _ = &client;

        log.info("[main] Client with address {any} connected, adding active connection..\n", .{client.address});
        try activeConnections.append(client);
        log.info("[main] Active connections: {any}\n", .{activeConnections.items});
        threadId += 1;

        const thread = try std.Thread.spawn(.{}, handleClient, .{ buff, client, threadId });

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

var waitingToAppend = false;

pub fn handleClient(buff: *std.ArrayList(bool), client: net.Server.Connection, threadId: isize) !void {
    log.info("[Thread-{d}] Accepted connection from client..\n", .{threadId});
    var r_byte: u8 = 0;
   _ = buff;
    while (true) {
        r_byte = client.stream.reader().readByte() catch |err| {
            if (err == error.EndOfStream) {
                log.info("[Thread-{d}] Closing connection.. \n", .{threadId});
                Mutex.lock();
                defer Mutex.unlock();
                for (activeConnections.items, 0..activeConnections.items.len) |conn, i| {
                    if (conn.address.getPort() == client.address.getPort()) {
                        conn.stream.close();
                        _ = activeConnections.orderedRemove(i);
                        //TODO kill thread
                    }
                }
                return;
            } else {
                return err;
            }
        };
        
        if (r_byte > 0) {
            Mutex.lock();
            std.debug.print("[Thread-{d} Putting.. k-{d} v-{}]\n", .{threadId, client.address.getPort(), true});
            try map.put(client.address.getPort(), true);
            Mutex.unlock();
        }
        
        if (r_byte == 0) {
            Mutex.lock();
            std.debug.print("[Thread-{d} Putting.. k-{d} v-{}]\n", .{threadId, client.address.getPort(), false});
            try map.put(client.address.getPort(), false);
            Mutex.unlock();
        }
        
        log.info("Thread-{d} Added to buffer...\n", .{threadId});

        // std.time.sleep(1 * std.time.ns_per_ms);

        Mutex.lock();
        var iterator = map.valueIterator();
        Mutex.unlock();
        var eval: u8 = 1;
        log.info("[Thread-{d}] Map count {d}\n", .{threadId, map.count()});
        if (map.count() > 1) {
            log.info("[Thread-{d}] Map count again {d}\n", .{threadId, map.count()});

            Mutex.lock();
            while (iterator.next()) |val| {
                const v = @intFromBool(val.*);
                eval &= v;
                log.info("[Thread-{d}] Eval is {d} \n", .{threadId, eval});
            }

            for (activeConnections.items) |conn| {
                log.info("[Thread-{d}] Broadcasting to: {any} value {d} \n", .{ threadId, conn.address, eval });

                if (eval != 0 and eval != 1) {
                    return error.WrongValue;
                }

                try conn.stream.writer().writeByte(eval);
            }
            Mutex.unlock();
        } else if (map.count() == 1) {} {
            Mutex.lock();
            defer Mutex.unlock();
           for (activeConnections.items) |conn| {
                log.info("[Thread-{d}] Broadcasting to: {any}\n", .{ threadId, conn.address });
                if (r_byte == 0) {
                    try conn.stream.writer().writeByte(0);
                } else {
                    try conn.stream.writer().writeByte(1);
                }
           }
        }

        Mutex.lock();
        defer Mutex.unlock();
        log.info("[Thread-{d}] Clearing map.. \n", .{threadId});
        map.clearRetainingCapacity();
    }

       // try append(client, buff, r_byte);
}


fn append(client: net.Server.Connection, buff: *std.ArrayList(bool), byte: u8, threadId: isize) !void {
    if (Mutex.tryLock()) {
        if (byte == 0) {
            log.info("[Thread-{d}] Read dominant bit, adding to buffer. \n", .{threadId});
            try buff.*.append(false);
            try map.put(client.address.getPort(), false);
        }

        if (byte > 0) {
            log.info("[Thread-{d}] Read byte from client: {b}\n", .{ threadId, byte });
            try buff.*.append(true);
            try map.put(client.address.getPort(), true);
        }

        for (activeConnections.items) |conn| {
            log.info("[Thread-{d}] Broadcasting to: {any}\n", .{ threadId, conn.address });
            if (waitingToAppend and buff.items.len < 2 ) {
                // Mutex.unlock();
                // let the other thread append
                break;
            }

            if (waitingToAppend and buff.items.len >= 2) {
                waitingToAppend = false;
                
            }

            for (buff.items) |i| {

                if (i == true) {
                    try conn.stream.writer().writeByte(1);
                } else {
                    try conn.stream.writer().writeByte(0);
                }
            }
        }
        // buff.clearRetainingCapacity();
        Mutex.unlock();
    } else {
        std.debug.print("[Thread-{d}] Failed to acq mutex..\n", .{threadId});
        waitingToAppend = true;
        std.time.sleep(1 * std.time.ns_per_ms);
        append(buff, byte);
    }
}

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

pub fn calculateCRC(data: []const u8) u16 {
    const generatorPolynomial: u16 = 0x4599;
    var crcRegister: u16 = 0;

    for (data) |byte| {
        var count: u3 = 0;
        for (0..8) |_| {
            const next = (byte >> (7 - count)) & 1;
            if (count != 7) {
                count = count + 1;
            }

            crcRegister = (crcRegister << 1) & 0x7FFF;
            if (next != 0) {
                crcRegister ^= generatorPolynomial;
            }
        }
    }

    //add recessive bit delimiter at the end
    crcRegister = (crcRegister << 1) | 1;
    return crcRegister;
}

pub const CanDataFrame = struct {
    // 1 dominant bit (0)
    sof: u1,
    // id - 11b; rtr - 1b dominant (0)
    arbitration: u12,
    // 2b dominant, 4b data len
    control: u6,
    // 8B, transmittet MSB first
    data: []u8,
    // 15 bit register; 1b recessive delimiter
    crc: u16,

    // 1b ack slot 1b ack delimiter;
    // transmitting station sends [11]
    // receiver sends to transmitter [10] if received correctly
    ack: u2,
    // 7 recessive bits (1)
    eof: u7,

    pub fn init(sof: u1, arbitration: u12, control: u6, data: []u8, crc: u16, ack: u2, eof: u7) CanDataFrame {
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
};

pub const CanRemoteFrame = struct {
    sof: u1,
    arbitration: u12,
    control: u6,
    crc: u16,
    ack: u2,
    eof: u7,

    pub fn init(sof: u1, arbitration: u12, control: u6, crc: u16, ack: u2, eof: u7) CanRemoteFrame {
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
    // 3 recessive (1)
    intermission: u3,
    // 8 recessive (1) for error passive
    suspendTransmission: u8,
    // arbitrary number of recessive bits (1)
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

const Tag = enum { CanDataFrame, CanErrorFrame, CanRemoteFrame, CanInterframeSpacing };

pub const CanUnion = union(Tag) { CanDataFrame: *CanDataFrame, CanErrorFrame: *CanErrorFrame, CanRemoteFrame: *CanRemoteFrame, CanInterframeSpacing: *CanInterframeSpacing };
