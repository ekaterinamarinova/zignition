const std = @import("std");
const net = std.net;
const debug = std.debug;
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

pub fn create(address: *net.Address, options: *net.Address.ListenOptions) !net.Server {
    debug.print("Creating the server...\n", .{});
    return try net.Address.listen(address.*, options.*);
}

pub fn write(stream: net.Stream, bytes: []const u8) !void {
    try stream.writeAll(bytes);
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(bytes);
}

pub fn read(stream: *net.Stream, buffer: *std.ArrayList(u8)) !usize {
    debug.print("Reading from client.. \n", .{});

    const temp: []u8 = try allocator.alloc(u8, 100);
    defer allocator.free(temp);

    const re = try stream.*.readAll(temp);
    _ = &re;

    try buffer.appendSlice(temp);

    return buffer.items.len;
}
