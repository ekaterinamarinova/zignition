const std = @import("std");
const net = std.net;
const debug = std.debug;

pub fn main() !void {
    const address: []const u8 = "127.0.0.1";
    try connect(8080, address);
}

pub fn connect(port: u16, address: []const u8) !void {
    const addr = try net.Address.parseIp4(address, port);
    debug.print("Using address with ip: {s}, port: {d}\n", .{address, port});

    const options = net.Address.ListenOptions {
        .kernel_backlog = 128,
        .reuse_address = true,
        .reuse_port = true,
        .force_nonblocking = false,
    };

    debug.print("Creating the server...\n", .{});
    var server = try net.Address.listen(addr, options);
    defer server.deinit();

    debug.print("Listening for connections...\n", .{});
    const connection = try server.accept();
    defer connection.stream.close();

    debug.print("Writing to the open stream...\n", .{});
    try write(connection.stream, "Hello, World!\n");
}

pub fn write(stream: net.Stream, bytes: []const u8) !void {
    try stream.writeAll(bytes);

    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(bytes);
}

pub fn read(stream: net.Stream, buffer: []const u8) !usize {
    return try stream.readAll(&buffer);
}
