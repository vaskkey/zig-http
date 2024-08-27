const std = @import("std");
const net = std.net;

/// HTTP Headers
pub const Header = struct {
    key: []const u8,
    value: []const u8,
};

/// HTTP method
pub const Method = enum {
    GET,
    POST,
    PUT,
    PATCH,
    DELETE,
};

/// HTTP request from client
pub const Request = struct {
    /// Request method
    method: Method,
    /// Request headers
    headers: []Header,
    /// Request body
    body: []const u8,
    /// Route to which request is made
    route: []u8,

    pub fn get_header(self: *Request, key: []u16) ?Header {
        for (self.headers) |header| {
            if (header.key == key) {
                return header;
            }
        }

        return null;
    }
};

pub fn GetServer() type {
    return struct {
        running: bool = false,
        allocator: std.mem.Allocator,

        const Self = @This();
        const Allocator = Self.allocator;

        /// Create the server obcject
        pub fn init(allocator: std.mem.Allocator) !*Self {
            const server = try allocator.create(GetServer());
            server.allocator = allocator;

            return server;
        }

        /// Start the server and listen on the given port
        pub fn start(self: *Self, comptime port: u16) !void {
            self.running = true;
            while (self.running) {
                try self.listen(port);
            }
        }

        /// Force the server to stop
        pub fn stop(self: *Self) !void {
            self.running = false;
        }

        fn listen(self: *Self, comptime port: u16) !void {
            const address = try net.Address.resolveIp("127.0.0.1", port);
            var listener = try address.listen(.{
                .reuse_address = true,
            });
            defer listener.deinit();

            const server = try listener.accept();
            defer server.stream.close();

            const writer = server.stream.writer();
            const reader = server.stream.reader();
            var buffer: [1024]u8 = undefined;

            const bytesRead = try reader.read(&buffer);
            const req = try self.parse(&buffer, bytesRead);
            defer self.allocator.destroy(req);

            _ = try writer.write("HTTP/1.1 200 OK\r\n\r\n");
        }

        fn parse(self: *Self, buffer: []u8, bytes_read: usize) !*Request {
            if (bytes_read < 4) {
                return error.CantParse;
            }

            // Split call info, headers and body
            var iter = std.mem.splitSequence(u8, buffer, "\r\n");
            const call = iter.first();
            const rest = iter.rest();
            iter = std.mem.splitSequence(u8, rest, "\r\n\r\n");
            const headers_str = iter.first();
            const body = iter.rest();

            var request = try self.allocator.create(Request);

            request.body = body;
            request.route = "";
            request.method = try get_method(call);
            request.headers = try get_headers(headers_str);

            return request;
        }

        fn get_method(header: []const u8) !Method {
            if (std.mem.startsWith(u8, header, "GET")) {
                return .GET;
            } else if (std.mem.startsWith(u8, header, "PUT")) {
                return .PUT;
            } else if (std.mem.startsWith(u8, header, "POST")) {
                return .POST;
            } else if (std.mem.startsWith(u8, header, "PATCH")) {
                return .PATCH;
            } else if (std.mem.startsWith(u8, header, "DELETE")) {
                return .DELETE;
            }

            return error.InvalidMethod;
        }

        fn get_headers(header_str: []const u8) ![]Header {
            var iter = std.mem.splitSequence(u8, header_str, "\r\n");
            var tmpHeaders = std.ArrayList(Header).init(std.heap.page_allocator);

            while (iter.next()) |value| {
                var hdr = std.mem.splitSequence(u8, value, ":");
                try tmpHeaders.append(Header{
                    .key = hdr.first(),
                    .value = std.mem.trim(u8, hdr.rest(), " "),
                });
            }

            return tmpHeaders.toOwnedSlice();
        }
    };
}
