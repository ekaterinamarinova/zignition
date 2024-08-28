const std = @import("std");
const net = std.net;
const log = std.debug;

pub fn main() !void {
    const address: []const u8 = "127.0.0.1";
    const add = try net.Address.parseIp4(address, 8080);
    log.print("Connecing to address: {s} port {d}\n", .{address, 8080});
    var client = try net.tcpConnectToAddress(add);
    log.print("Connected to server, reading...\n", .{});

    var buffer: [1024]u8 = undefined;
    const read_len = try client.readAll(&buffer);

    if (read_len <= 0) {
        std.debug.print("Error reading into buffer", .{});
    }

    std.debug.print("Read bytes: {s}", .{buffer[0..read_len]});
}