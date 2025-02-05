const std = @import("std");
const net = std.net;

/// HTTP Headers
pub const Header = struct {
    key: []const u8,
    value: []const u8,

    pub fn get_str(self: *Header, allocator: std.mem.Allocator) ![]u8 {
        return try std.fmt.allocPrint(allocator, "{s}: {s}", .{ self.key, self.value });
    }

    pub fn len(self: *const Header) usize {
        return self.key.len + self.value.len + 2;
    }
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
    headers: std.StringHashMap(Header),
    /// Request body
    body: []const u8,
    /// Route to which request is made
    route: []const u8,

    pub fn get_header(self: *Request, key: []u16) ?Header {
        return self.headers.get(key);
    }
};

/// HTTP request from client
pub const Response = struct {
    /// Response headers
    headers: std.StringHashMap(*Header),
    /// Response body
    body: []const u8,
    /// Response status
    status: u16,

    pub fn to_str(self: *Response, allocator: std.mem.Allocator) ![]u8 {
        const headers = try self.get_headers_str(allocator);
        return try std.fmt.allocPrint(allocator, "HTTP/1.1 {d} {s}\r\n{s}\r\n{s}", .{ self.status, "Created", headers, self.body }); // TODO: Add a map from status to status string
    }

    fn get_headers_str(self: *Response, allocator: std.mem.Allocator) ![]u8 {
        if (self.headers.count() == 0) return "";
        const sep = "\r\n";

        const total_len = blk: {
            var sum: usize = sep.len * (self.headers.count());
            var iter = self.headers.iterator();
            while (iter.next()) |header| {
                sum += header.value_ptr.*.len();
            }
            break :blk sum;
        };

        const buf = try allocator.alloc(u8, total_len);
        errdefer allocator.free(buf);

        var iterator = self.headers.iterator();

        var buf_index: usize = 0;
        while (iterator.next()) |header| {
            const hdr = header.value_ptr.*;
            @memcpy(buf[buf_index .. buf_index + hdr.len()], try hdr.get_str(allocator));
            buf_index += hdr.len();
            @memcpy(buf[buf_index .. buf_index + sep.len], sep);
            buf_index += sep.len;
        }

        return buf;
    }
};

pub fn Server() type {
    return struct {
        running: bool = false,
        allocator: std.mem.Allocator,

        const Self = @This();
        const Allocator = Self.allocator;

        /// Create the server obcject
        pub fn init(allocator: std.mem.Allocator) !*Self {
            const server = try allocator.create(Server());
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

            // Parsing request
            const bytesRead = try reader.read(&buffer);
            const req = try self.parseAlloc(&buffer, bytesRead);
            defer self.allocator.destroy(req);

            const response = try self.allocator.create(Response);
            defer self.allocator.destroy(response);

            // Header test

            response.headers = std.StringHashMap(*Header).init(self.allocator);
            var cookieHeader = try self.allocator.create(Header);
            defer self.allocator.destroy(cookieHeader);

            cookieHeader.key = "Auth-Header";
            cookieHeader.value = "HELLO";
            try response.headers.put(cookieHeader.key, cookieHeader);

            // Find requested file in path
            const filePath = try self.allocator.alloc(u8, req.route.len + 1);
            defer self.allocator.free(filePath);
            @memcpy(filePath[0..1], ".");
            @memcpy(filePath[1 .. req.route.len + 1], req.route);

            response.status = 200;
            response.body = std.fs.cwd().readFileAlloc(self.allocator, filePath, 1024) catch |err| switch (err) {
                error.FileTooBig => body: {
                    response.status = 413;
                    break :body "Content Too Large";
                },
                error.FileNotFound => body: {
                    response.status = 404;
                    break :body req.route;
                },
                else => body: {
                    response.status = 500;
                    break :body "Internal Server Error";
                },
            };

            const str = try response.to_str(self.allocator);

            _ = try writer.write(str);
        }

        fn parseAlloc(self: *Self, buffer: []u8, bytes_read: usize) !*Request {
            if (bytes_read < 4) {
                return error.CantParse;
            }

            // Split call info, headers and body
            var iter = std.mem.splitSequence(u8, buffer, "\r\n");

            // first line e.g. GET / HTTP/1.1
            const uriLine = iter.first();
            var uriLineIter = std.mem.splitSequence(u8, uriLine, " ");
            const method = uriLineIter.first();

            const rest = iter.rest();
            iter = std.mem.splitSequence(u8, rest, "\r\n\r\n");

            const headers_str = iter.first();
            const body = iter.rest();

            var request = try self.allocator.create(Request);

            request.body = body;
            request.route = uriLineIter.next() orelse "";
            request.method = try get_method(method);
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

        fn get_headers(header_str: []const u8) !std.StringHashMap(Header) {
            var iter = std.mem.splitSequence(u8, header_str, "\r\n");
            var tmpHeaders = std.StringHashMap(Header).init(std.heap.page_allocator);

            while (iter.next()) |value| {
                var hdr = std.mem.splitSequence(u8, value, ":");
                const key = hdr.first();
                try tmpHeaders.put(key, Header{
                    .key = key,
                    .value = std.mem.trim(u8, hdr.rest(), " "),
                });
            }

            return tmpHeaders;
        }
    };
}
