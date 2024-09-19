const std = @import("std");
const bus = @import("bus.zig");
const sr = @import("serial.zig");
const net = std.net;
const log = std.log;
const t = std.testing;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

threadlocal var boolBuff = std.ArrayList(bool).init(allocator);

threadlocal var rf: ?*bus.CanRemoteFrame = null;
threadlocal var df: ?*bus.CanDataFrame = null;

threadlocal var isRFSent: bool = false;

threadlocal var res: bus.CanUnion = undefined;
var mut = std.Thread.Mutex{};
var cond = std.Thread.Condition{};

pub const NodesConfig = struct {
    nodes: []NodeConfig
};

pub const NodeConfig = struct {
    id: u12,
    name: []const u8,
    host: []const u8,
    port: u32,
    isTransmitter: bool,
    ignoreFilter: union {
        id: u12,
        nodeName: []u8,
    }
};

pub fn main() !void {
    const t1 = try std.Thread.spawn(
        .{}, connect, .{"ecu", true});
    const t3 = try std.Thread.spawn(
        .{}, connect, .{"ecu2", true});
    const t2  = try std.Thread.spawn(
        .{}, connect, .{"oxs", false});

    t1.detach();
    t3.detach();
    t2.join();

    defer allocator.destroy(rf.?);
    defer allocator.destroy(df.?);
}

test "test json parse" {
    try parseConfig();
}

pub fn parseConfig() !void {
    const config: *NodesConfig = try allocator.create(NodesConfig);
    defer allocator.destroy(config);
    //TODO handle destroy accordingly in future

    const parsed = try std.json.parseFromSlice(
        NodesConfig,
        allocator,
        try readFile("/zig/resources/node-config.json"),
        .{}
    );

    config.* = parsed.value;
    std.debug.print("Parsed: {any}\n", .{config});
}

pub fn readFile(filePath: []const u8) ![]u8 {
    std.debug.print("Working dir: {any}\n", .{std.fs.cwd()});
    const file = try std.fs.openFileAbsolute(filePath, .{});
    defer file.close();

    const fileSize = try file.getEndPos();
    const buffer: []u8 = try allocator.alloc(u8, fileSize);
    _ = try file.reader().readAll(buffer);

    return buffer;
}

fn handler(client: net.Stream, doTransmit: bool, clName: []const u8, count: *u32) !void {
    if (doTransmit) {
        try read(client, clName, count);
    } else {
        if (isRFSent) {
           // wait for data frame to be received
            try read(client, clName, count);
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
        std.time.sleep(5 * std.time.ns_per_s);
    }
}

pub fn connect(clName: []const u8, doTransmit: bool) !void {
    const address: []const u8 = "127.0.0.1";
    const add = try net.Address.parseIp4(address, 8080);
    log.info("Connecing from node: {s} to address: {s} port: {d}\n", .{clName, address, 8080});
    var client = try net.tcpConnectToAddress(add);
    log.info("Connected to server, from node: {s} handling...\n", .{clName});
    var count: u32 = 0;
    while (true) {
        try handler(client, doTransmit, clName, &count);
    }

    defer client.close();
}

fn read(stream: net.Stream, clName: []const u8, count: *u32) !void {
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

    log.info("[{s}] Count: {d}\n", .{clName, count.*});

    res = try sr.mapBitsToFrames(bit, count.*);
    count.* += 1;

    switch (res) {
        .CanRemoteFrame => {
            log.info("[{s}] Remote frame received!\n", .{clName});
            rf = res.CanRemoteFrame;
            count.* = 0;
            if (rf != null and rf.?.*.eof == 127) {
                // confirmation we've mapped the full remote frame
                try sendDataFrame(stream, clName);
            }
        },
        .CanDataFrame => {
            df = res.CanDataFrame;
            if (df != null) {
                log.info("[{s}] Data frame values: {any}\n", .{clName, df.?});

                if (df.?.*.eof == 127) {
                    log.info("[{s}] Data frame received!\n", .{clName});
                }
            }
        },
        else => {
            // log.info("[{s}] Mapping bits to frames..\n", .{clName});
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