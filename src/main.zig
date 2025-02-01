const std = @import("std");
const http = @import("server.zig");
const net = std.net;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        _ = gpa.deinit();
    }

    var server = try http.Server().init(allocator);

    try server.start(4221);
}
