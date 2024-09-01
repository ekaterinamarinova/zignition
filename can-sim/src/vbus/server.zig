const std = @import("std");
const net = std.net;
const debug = std.debug;

const allocator = std.heap.PageAllocator{};
var map = std.AutoHashMap(u32, *net.Stream).init(allocator);

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
        .force_nonblocking = true,
    };

    debug.print("Creating the server...\n", .{});
    var server = try net.Address.listen(addr, options);
    defer server.deinit();

    while (true) {
        debug.print("Listening for connections...\n", .{});
        const connection = retry(&server);

        const thread = try std.Thread.spawn(
            .{},
            handle_client,
            .{connection.stream}
        );

        thread.detach();
    }
}

fn retry(server: *net.Server) net.Server.Connection {
    var conn: ?net.Server.Connection = null;
    while (true) {
        if (conn != null) {
            return conn.?;
        }

        conn = server.accept() catch |err| {
            if (err == error.WouldBlock) {
                continue;
            } else {
                return conn.?;
            }
        };
    }

}

pub fn handle_client(conn: net.Stream) !void {
    debug.print("Writing to the open stream...\n", .{});
    try write(conn, "Hello, World!\n");
    defer conn.close();
}

pub fn write(stream: net.Stream, bytes: []const u8) !void {
    try stream.writeAll(bytes);
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(bytes);
}

pub fn read(stream: net.Stream, buffer: []const u8) !usize {
    return try stream.readAll(&buffer);
}
