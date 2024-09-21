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

/// HTTP request from client
pub const Response = struct {
    /// Response headers
    headers: []*Header,
    /// Response body
    body: []const u8,
    /// Response status
    status: u8,

    pub fn to_str(self: *Response, allocator: std.mem.Allocator) ![]u8 {
        const headers = try self.get_headers_str(allocator);
        return try std.fmt.allocPrint(allocator, "HTTP/1.1 {d} {s}\r\n{s}\r\n{s}", .{ self.status, "Created", headers, self.body }); // TODO: Add a map from status to status string
    }

    fn get_headers_str(self: *Response, allocator: std.mem.Allocator) ![]u8 {
        if (self.headers.len == 0) return "";
        const sep = "\r\n";

        const total_len = blk: {
            var sum: usize = sep.len * (self.headers.len);
            for (self.headers) |header| sum += header.len();
            break :blk sum;
        };

        const buf = try allocator.alloc(u8, total_len);
        errdefer allocator.free(buf);

        @memcpy(buf[0..self.headers[0].len()], try self.headers[0].get_str(allocator));
        var buf_index: usize = self.headers[0].len();
        @memcpy(buf[buf_index .. buf_index + sep.len], sep);
        buf_index += sep.len;
        for (self.headers[1..]) |header| {
            @memcpy(buf[buf_index .. buf_index + header.len()], try header.get_str(allocator));
            buf_index += header.len();
            @memcpy(buf[buf_index .. buf_index + sep.len], sep);
            buf_index += sep.len;
        }

        return buf;
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

            const response = try self.allocator.create(Response);
            defer self.allocator.destroy(response);

            response.headers = &[0]*Header{};
            response.body = "HHHH";
            response.status = 201;

            const str = try response.to_str(self.allocator);

            _ = try writer.write(str);
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
