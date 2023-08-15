pub const meta = @import("src/meta.zig");
pub const io = @import("src/io.zig");
pub const BinRW = @import("src/binrw.zig").BinRW;

test {
    const std = @import("std");
    std.testing.refAllDeclsRecursive(@This());
    inline for (.{
        @import("tests/simple_struct.zig"),
        @import("tests/struct_with_ptr.zig"),
        @import("tests/tagged_union.zig"),
    }) |source_file| std.testing.refAllDeclsRecursive(source_file);
}
