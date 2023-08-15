const std = @import("std");
const comptimePrint = std.fmt.comptimePrint;

pub fn assert(ok: bool, comptime fmt: []const u8, args: anytype) void {
    if (!ok) {
        if (@inComptime()) {
            @compileError(comptimePrint(fmt, args));
        } else {
            std.debug.panic(fmt, args);
        }
    }
}
