const std = @import("std");
const bus = @import("bus.zig");
const sr = @import("serial.zig");
const net = std.net;
const log = std.log;
const t = std.testing;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

var boolBuff = std.ArrayList(bool).init(allocator);
var rf: ?*bus.CanRemoteFrame = null;
var df: ?*bus.CanDataFrame = null;

var isRFSent: bool = false;
var count: u32 = 0;
var i: usize = 0;

var res: bus.CanUnion = undefined;
var mut = std.Thread.Mutex{};

pub fn main() !void {
    const t1 = try std.Thread.spawn(
        .{}, connect, .{"ecu", true});
    const t2  = try std.Thread.spawn(
        .{}, connect, .{"oxs", false});

    t1.detach();
    t2.join();

    defer allocator.destroy(rf.?);
    defer allocator.destroy(df.?);
}

fn handler(client: net.Stream, doTransmit: bool, clName: []const u8) !void {
    if (doTransmit) {
        // wait for a remote frame to start transmission
        try read(client, clName);
    } else {
        if (isRFSent) {
           // wait for data frame to be received
            try read(client, clName);
            return;
        }
        
        const remote = sr.createRemoteFrame();
        const serialized = try sr.serializeRemoteFrame(remote);
        log.info("[{s}] Serialized frame, sending...: {any}\n", .{clName, serialized.items});
        for (serialized.items) |value| {
            const cast: u8 = @intFromBool(value);
            write(client, cast, clName);
        }
        isRFSent = true;
        count = 0;
        std.time.sleep(10 * std.time.ns_per_s);
    }
}

pub fn connect(clName: []const u8, doTransmit: bool) !void {
    const address: []const u8 = "127.0.0.1";
    const add = try net.Address.parseIp4(address, 8080);
    log.info("Connecing from node: {s} to address: {s} port: {d}\n", .{clName, address, 8080});
    var client = try net.tcpConnectToAddress(add);
    log.info("Connected to server, from node: {s} handling...\n", .{clName});

    while (true) {
        try handler(client, doTransmit, clName);
    }

    defer client.close();
}

fn read(stream: net.Stream, clName: []const u8) !void {
    var bit: bool = undefined;
    const byte = try stream.reader().readByte();

    switch (byte) {
        0 => {
            bit = false;
        },
        1 => {
            bit = true;
        },
        else => {
            log.info("[{s}] Error reading into buffer in node.\n", .{clName});
            return;
        },
    }

    mut.lock();
    defer mut.unlock();

    log.info("[{s}] Count: {d}\n", .{clName, count});
    res = try sr.mapBitsToFrames(bit, count);
    count += 1;

    switch (res) {
        .CanRemoteFrame => {
            log.info("[{s}] Remote frame received!\n", .{clName});
            rf = res.CanRemoteFrame;
            count = 0;
            if (rf != null and rf.?.*.eof == 127) {
                // confirmation we've mapped the full remote frame
                try sendDataFrame(stream, clName);
            }
        },
        .CanDataFrame => {
            df = res.CanDataFrame;
            if (df != null) {
                log.info("[{s}] Data frame values: {any}\n", .{clName, df.?});
            }
        },
        else => {
            log.info("[{s}] Mapping bits to frames..\n", .{clName});
        }
    }
}

pub fn sendDataFrame(stream: net.Stream, clName: []const u8) !void {
    log.info("\n[{s}] Sending data frame..\n", .{clName});
    const data = sr.createDataFrame();
    const serialized = try sr.serializeDataFrame(data);
    defer serialized.deinit();

    log.info("Serialized data items: {any}\n", .{serialized.items});
    for (serialized.items) |value| {
        const cast: u8 = @intFromBool(value);
        write(stream, cast, clName);
    }
}

fn write(stream: net.Stream, bit: u8, clName: []const u8) void {
    stream.writer().writeByte(bit) catch |err| {
        if (error.WouldBlock == err) {
            write(stream, bit, clName);
        } else {
            log.info("Error writing to stream: {}\n", .{err});
        }
    };
}