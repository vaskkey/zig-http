const std = @import("std");
const http = @import("server.zig");
const net = std.net;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("Logs from your program will appear here!\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        _ = gpa.deinit();
    }

    var server = try http.GetServer().init(allocator);

    try server.start(4221);
}
