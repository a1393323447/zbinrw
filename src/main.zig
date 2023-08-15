pub const meta = @import("meta.zig");
pub const io = @import("io.zig");
pub const BinRW = @import("binrw.zig").BinRW;

const std = @import("std");

fn usizeToU8(val: u32) u8 {
    return @truncate(val);
}

const Color = struct {
    pub const ZBINRW_META: type = struct {
        pub const MAGIC: []const u8 = "Color";
        pub const DEFUALT_ENDIAN: meta.attr.Endian = .Little;
        r: meta.Value
            .InBin(u32)
            .Read(.{ meta.attr.Map(usizeToU8) })
            .done(),
    };

    r: u8,
    g: u32,
    b: u32,
};

const Tree = struct {
    c1: Color,
    c2: Color,
};

const ShapeType = enum(u8) {
    Square = 0,
    Circle = 1,
};

const Shape = union(ShapeType) {
    pub const ZBINRW_META = struct {
        pub const DEFUALT_ENDIAN: meta.attr.Endian = .Little;
    };
    Square: Square,
    Circle: Circle,
};

const Square = struct {
    w: usize,  
};

const Circle = struct {
    r: isize,
};

const ColorBits = struct {
    pub const ZBINRW_META: type = struct {
        pub const MAGIC: []const u8 = "Color";
        pub const DEFUALT_ENDIAN: meta.attr.Endian = .Native;
        bytes: meta.Value
            .InBin([]align(1) const usize)
            .Size("len")
            .done(),
    };

    len: usize,
    bytes: []align(1) const usize,
};

test "A" {
    const data = "Color" ++ &[_]u8 {
        0x08, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x03, 0x00, 0x00, 0x00,

        0x01, 0x00, 0x00, 0x00,
        0x02, 0x00, 0x00, 0x00,
        0x03, 0x00, 0x00, 0x00,
    };
    var slice_reader = io.reader.SliceReader.new(data);
    const color = try BinRW(ColorBits).read(slice_reader.reader());
    std.debug.print("{}\n\n\n", .{color});
}

pub fn main() !void {

}