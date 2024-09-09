const std = @import("std");
const can = @import("can-main.zig");
const sr = @import("serial.zig");
const net = std.net;
const log = std.debug;
const t = std.testing;

var isFree = true;
var i: usize = 0;
var buffer: [60]u8 = undefined;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();
var boolBuff = std.ArrayList(bool).init(allocator);
var result: *can.CanRemoteFrame = undefined;

pub fn main() !void {
    result = try allocator.create(can.CanRemoteFrame);
    result.* = sr.createRemoteFrameEmpty();
    std.debug.print("rf after creation: {any}\n", .{result.*});
    const t1 = try std.Thread.spawn(
        .{}, connect, .{"ecu", true});
    const t2  = try std.Thread.spawn(
        .{}, connect, .{"oxs", false});

    defer allocator.destroy(result);
    t1.detach();
    t2.join();
}

fn handler(client: net.Stream, doRead: bool) !void {
    if (doRead) {
        try read(client, "ecu");
    } else {
        const rf = createRemoteFrame();
        const serialized = try sr.serializeRemoteFrame(rf);

        std.debug.print("Serialized frame: {any}\n", .{serialized.items});

        for (serialized.items) |value| {
            const cast: u8 = @intFromBool(value);
            write(client, cast, "ecu");
        }

        std.time.sleep(20 * std.time.ns_per_s);

        // now read the data frame
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
var count: u32 = 0;
//TODO enhance logic => detect sof, send bits for real time deserialization,
//TODO send back ack and a data frame response
fn read(stream: net.Stream, clName: []const u8) !void {
    var Mutex = std.Thread.Mutex{};
    Mutex.lock();
    defer Mutex.unlock();

    var bit: bool = undefined;
    const byte = try stream.reader().readByte();

    std.debug.print("\n [node] Full byte {b} count {d}\n", .{byte, count});
    switch (byte) {
        0 => {
            bit = false;
        },
        1 => {
            bit = true;
        },
        else => {
            log.print("[node] Error reading into buffer in node {s}.\n", .{clName});
            return;
        },
    }

    var status: i8 = 0;

    std.debug.print("rf object before: {any}\n", .{result});
    status = try sr.mapBitsToFrames(bit, count, result);

    if (status == 1) {
        count = 0;
        return;
    }
    
    count += 1;
    std.debug.print("result: {any}\n", .{result.*});

}

fn write(stream: net.Stream, bit: u8, clName: []const u8) void {
    var Mutex = std.Thread.Mutex{};
    Mutex.lock();
    defer Mutex.unlock();

    // log.print("Writing byte {b} from client {s}.. \n", .{bit, clName});
    stream.writer().writeByte(bit) catch |err| {
        if (error.WouldBlock == err) {
            write(stream, bit, clName);
        } else {
            log.print("Error writing to stream: {}\n", .{err});
        }
    };

}

fn createRemoteFrame() can.CanRemoteFrame {
    // const data = [_]u16{0, 0, 0, 0, 0, 0, 0, 0};
    return can.CanRemoteFrame {
        .sof = 0b0,
        .arbitration = 0x01,
        .control = 0x04,
        .crc = 0x7FF3,
        .ack = 0x1,
        .eof = 0x7F,
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
