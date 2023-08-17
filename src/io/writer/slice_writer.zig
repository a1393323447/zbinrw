const std = @import("std");

pub const SliceWriter = struct {
    const Self = @This();
    const WriteError = error {OutOfBoundary};
    const Writer = std.io.Writer(*Self, WriteError, writeFn);

    slice: []u8,

    pub fn new(slice: []u8) Self {
        return SliceWriter { .slice = slice };
    }

    pub fn writer(self: *Self) Writer {
        return Writer { .context = self };
    }

    fn writeFn(self: *Self, bytes: []const u8) WriteError!usize {
        if (self.slice.len < bytes.len) {
            return WriteError.OutOfBoundary;
        }
        @memcpy(self.slice[0..bytes.len], bytes);
        
        return bytes.len;
    }
};