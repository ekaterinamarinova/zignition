const std = @import("std");
const can = @import("../can-main.zig");
const net = std.net;
const log = std.debug;

pub fn main() !void {
    const t1 = try std.Thread.spawn(
        .{}, connect, .{"ecu"});
    const t2  = try std.Thread.spawn(
        .{}, connect, .{"oxs"});

    t1.join();
    t2.join();
}

fn connect(clName: []const u8) !void {
    var isFree = true;
    _ = &isFree;

    const address: []const u8 = "127.0.0.1";
    const add = try net.Address.parseIp4("127.0.0.1", 8080);
    log.print("Connecing from node: {s} to address: {s} port: {d}\n", .{clName, address, 8080});
    var client = try net.tcpConnectToAddress(add);
    log.print("Connected to server, from node: {s} reading...\n", .{clName});


    while (true) {
        // const r = try read(&client, clName, &isFree);

        // if (r == 2) {
        //     //error
        //     return;
        // }

        if (isFree) {
            writeBytes(&client, "TestDataFrame ", clName);
        }
    }

    defer client.close();
}


fn read(stream: *net.Stream, clName: []const u8, isFree: *bool) !usize {
    var Mutex = std.Thread.Mutex{};
    Mutex.lock();
    defer Mutex.unlock();

    var buffer: [100]u8 = undefined;
    const read_len = stream.*.readAll(&buffer) catch |err| {
        _ = &err;
        return 2;
    };

    if (read_len == 0) {
        // log.print("Nothing to read.\n", .{});
        isFree.* = true;
    } else if (read_len > 0 and read_len != 2) {
        log.print("Read bytes from node {s}: {s}\n", .{clName, buffer[0..read_len]});
    } else {
        log.print("Error reading into buffer from node {s}.\n", .{clName});
    }

    return read_len;
}

fn writeBytes(stream: *net.Stream, bytes: []const u8, clName: []const u8) void {
    var Mutex = std.Thread.Mutex{};
    Mutex.lock();
    defer Mutex.unlock();

    log.print("Writing bytes {s} from client {s}.. \n", .{bytes, clName});
    stream.*.writeAll(bytes) catch |err| {
        if (error.WouldBlock == err) {
            writeBytes(stream, bytes, clName);
        }
    };
}

fn write(comptime T: type, frame: T, stream: *net.Stream) void {
    // thsi is stupid design
    if (@TypeOf(frame) == can.CanDataFrame) {
        const dataFrame = @as(can.CanDataFrame, frame);
        try stream.writeAll(dataFrame.data);
    }

    // stream.writer().writeByte();

}