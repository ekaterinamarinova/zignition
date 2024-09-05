const std = @import("std");
const can = @import("can-main.zig");
const net = std.net;
const log = std.debug;
const t = std.testing;

var isFree = true;
var i: usize = 0;
var buffer: [30]u8 = undefined;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();
var boolBuff = std.ArrayList(bool).init(allocator);

pub fn main() !void {
    const t1 = try std.Thread.spawn(
        .{}, connect, .{"ecu", true});
    const t2  = try std.Thread.spawn(
        .{}, connect, .{"oxs", false});

    t1.detach();
    t2.join();
}

fn handler(client: net.Stream, doRead: bool) !void {
    if (doRead) {
        try read(client, "ecu");
    } else {
        var rf = createRemoteFrame();
        _ = &rf;

        writeByte(client, rf.sof, "ecu");
        std.time.sleep(10 * std.time.ns_per_s);
    }
}

pub fn connect(clName: []const u8, doRead: bool) !void {
    const address: []const u8 = "127.0.0.1";
    const add = try net.Address.parseIp4(address, 8080);
    log.print("Connecing from node: {s} to address: {s} port: {d}\n", .{clName, address, 8080});
    var client = try net.tcpConnectToAddress(add);
    log.print("Connected to server, from node: {s} handling...\n", .{clName});


    while (true) {
        try handler(client, doRead);
    }

    defer client.close();
}

fn read(stream: net.Stream, clName: []const u8) !void {
    var Mutex = std.Thread.Mutex{};
    Mutex.lock();
    defer Mutex.unlock();

    const byte = try stream.reader().readByte();

    switch (byte) {
        0 => {
            log.print("Read dominant byte in node {s}.\n", .{clName});
            try boolBuff.append(false);
        },
        1 => {
            log.print("Read recessive byte in node {s}.\n", .{clName});
            try boolBuff.append(true);
        },
        else => {
            log.print("Error reading into buffer in node {s}.\n", .{clName});
        },
    }

    std.debug.print("Buffer: {any} \n", .{boolBuff.items});
}

fn writeByte(stream: net.Stream, byte: u8, clName: []const u8) void {
    var Mutex = std.Thread.Mutex{};
    Mutex.lock();
    defer Mutex.unlock();

    log.print("Writing byte {b} from client {s}.. \n", .{byte, clName});
    stream.writer().writeByte(byte) catch |err| {
        if (error.WouldBlock == err) {
            writeByte(stream, byte, clName);
        } else {
            log.print("Error writing to stream: {}\n", .{err});
        }
    };

}

fn createRemoteFrame() can.CanRemoteFrame {
    const data = [_]u16{0, 0, 0, 0, 0, 0, 0, 0};
    return can.CanRemoteFrame{
        .sof = 0b0,
        //id(11b) + rtr(1b rec)
        .arbitration = 0b010000001010,
        .control = 0b00001000,
        .crc = can.calculateCRC(&data),
        .ack = 0b11,
        .eof = 0b1111111
    };
}

fn createDataFrame() can.CanDataFrame {
    const data = [_]u16{0, 0, 0, 0, 0, 0, 0, 0};
    return can.CanDataFrame{
        .sof = 0b0,
        //id(11b) + rtr(1b rec)
        .arbitration = 0b010000001010,
        .control = 0b00001000,
        .data = &data,
        .crc = can.calculateCRC(&data),
        .ack = 0b11,
        .eof = 0b1111111,
    };
}

fn createInterframeSpace() can.CanInterframeSpacing {
    return can.CanInterframeSpacing{
        .intermission = 0b111,
        .suspendTransmission = 0b11111111,
        // bus idle is of arbitrary length
        .busIdle = 0b1111,
    };
}
