const std = @import("std");

pub const SliceReader = struct {
    const Self = @This();
    const ReadError = error {};
    const Reader = std.io.Reader(*Self, ReadError, readFn);

    bytes: []const u8,

    pub fn new(slice: []const u8) Self {
        return Self {
            .bytes = slice,
        };
    }

    pub fn reader(self: *Self) Reader {
        return Reader {
            .context = self,
        };
    }

    /// Returns the number of bytes read. It may be less than buffer.len.
    /// If the number of bytes read is 0, it means end of stream.
    /// End of stream is not an error condition.
    fn readFn(self: *Self, buffer:[]u8) ReadError!usize {
        var bytes_read: usize = 0;

        if (self.bytes.len == 0) {
            bytes_read = 0;
        } else if (self.bytes.len < buffer.len) {
            bytes_read = self.bytes.len;
            @memcpy(buffer[0..bytes_read], self.bytes);
        } else {
            bytes_read = buffer.len;
            @memcpy(buffer, self.bytes[0..bytes_read]);
        }

        self.bytes = self.bytes[bytes_read..];
        return bytes_read;
    }
};
