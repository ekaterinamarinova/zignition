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
    port: u16,
    isTransmitter: bool,
    ignoreFilter: struct {
        id: u12,
        nodeName: []u8,
    }
};

pub fn main() !void {
    const config = parseConfig();
    if (config == null) {
        log.debug("Config is null\n", .{});
        return;
    }

    log.debug("Config: {any}", .{config.?.nodes});

    for (config.?.nodes) |nodecf| {
        const threadd = try std.Thread.spawn(.{}, connect,.{
            nodecf.name,
            nodecf.id,
            nodecf.isTransmitter,
            nodecf.host,
            nodecf.port,
            nodecf.ignoreFilter.id,
        });
        threadd.detach();
    }

    while (true) {
        // since we're detaching the threads
        // we have to run the main thread indefinitely
        // until a critical error occurs
        // or the program is terminated
    }

    defer allocator.destroy(rf.?);
    defer allocator.destroy(df.?);
}

pub fn parseConfig() ?NodesConfig {
    const parsed = std.json.parseFromSlice(
        NodesConfig,
        allocator,
        readFile("/zig/resources/node-config.json") catch |err| {
            log.info("Error reading file: {any}\n", .{err});
            return null;
        },
        .{}
    ) catch |err| {
        log.info("Error parsing config: {any}\n", .{err});
        return null;
    };
    return parsed.value;
}

pub fn readFile(filePath: []const u8) ![]u8 {
    const file = try std.fs.openFileAbsolute(filePath, .{});
    defer file.close();

    const fileSize = try file.getEndPos();
    const buffer: []u8 = try allocator.alloc(u8, fileSize);
    _ = try file.reader().readAll(buffer);

    return buffer;
}

fn handler(client: net.Stream, id: u12, doTransmit: bool, clName: []const u8, count: *u32, ignoreId: u12) !void {
    if (doTransmit) {
        try read(client, id, clName, count, ignoreId);
    } else {
        if (isRFSent) {
           // wait for data frame to be received
            try read(client, id, clName, count, ignoreId);
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

pub fn connect(clName: []const u8, id: u12, doTransmit: bool, address: []const u8, port: u16, ignoreId: u12) !void {
    const add = try net.Address.parseIp4(address, port);
    log.info("Connecing from node: {s} to address: {s} port: {d}\n", .{clName, address, port});
    var client = try net.tcpConnectToAddress(add);
    log.info("Connected to server, from node: {s} handling...\n", .{clName});
    var count: u32 = 0;
    while (true) {
        try handler(client, id, doTransmit, clName, &count, ignoreId);
    }

    defer client.close();
}

fn read(stream: net.Stream, id: u12, clName: []const u8, count: *u32, ignoreId: u12) !void {
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

    res = try sr.mapBitsToFrames(bit, count.*, ignoreId);
    count.* += 1;

    switch (res) {
        .CanRemoteFrame => {
            log.info("[{s}] Remote frame received!\n", .{clName});
            rf = res.CanRemoteFrame;
            count.* = 0;
            if (rf != null and rf.?.*.eof == 127) {
                // confirmation we've mapped the full remote frame
                try sendDataFrame(stream, clName, id);
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

pub fn sendDataFrame(stream: net.Stream, clName: []const u8, id: u12) !void {
    log.info("\n[{s}] Sending data frame..\n", .{clName});
    const data = sr.createDataFrame(id);
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