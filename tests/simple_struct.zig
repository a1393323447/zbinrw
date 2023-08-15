const std = @import("std");
const testing = std.testing;

const zbinrw = @import("../zbinrw.zig");
const meta = zbinrw.meta;
const attr = meta.attr;
const SliceReader = zbinrw.io.reader.SliceReader;
const Value = meta.Value;
const BinRW = zbinrw.BinRW;

test "little" {
    const Color = struct {
        pub const ZBINRW_META: type = struct {
            pub const DEFUALT_ENDIAN: attr.Endian = .Little;
        };
        r: u16,
        g: u16,
        b: u16,
    };

    const data = &[_]u8 { 
        0x01, 0x02,
        0x03, 0x04,
        0x05, 0x06
    };
    var slice_reader = SliceReader.new(data);
    const color = try BinRW(Color).read(slice_reader.reader());
    const expected = Color {
        .r = 0x0201,
        .g = 0x0403,
        .b = 0x0605,
    };

    try std.testing.expectEqual(expected, color);
}

test "big_endian" {
    const Color = struct {
        pub const ZBINRW_META: type = struct {
            pub const DEFUALT_ENDIAN: attr.Endian = .Big;
        };
        r: u16,
        g: u16,
        b: u16,
    };

    const data = &[_]u8 { 
        0x01, 0x02,
        0x03, 0x04,
        0x05, 0x06
    };
    var slice_reader = SliceReader.new(data);
    const color = try BinRW(Color).read(slice_reader.reader());
    const expected = Color {
        .r = 0x0102,
        .g = 0x0304,
        .b = 0x0506,
    };

    try std.testing.expectEqual(expected, color);
}

test "mixed_endian" {
    const Color = struct {
        pub const ZBINRW_META: type = struct {
            pub const DEFUALT_ENDIAN: attr.Endian = .Big;
            g: Value.InBin(u16).RW(.{attr.Endian.Little}).done(),
        };
        r: u16,
        g: u16,
        b: u16,
    };

    const data = &[_]u8 { 
        0x01, 0x02,
        0x03, 0x04,
        0x05, 0x06
    };
    var slice_reader = SliceReader.new(data);
    const color = try BinRW(Color).read(slice_reader.reader());
    const expected = Color {
        .r = 0x0102,
        .g = 0x0403,
        .b = 0x0506,
    };

    try std.testing.expectEqual(expected, color);
}

test "with_magic" {
    const Color = struct {
        pub const ZBINRW_META: type = struct {
            pub const MAGIC: []const u8 = "Color";
            pub const DEFUALT_ENDIAN: attr.Endian = .Little;
        };
        r: u16,
        g: u16,
        b: u16,
    };

    const data = "Color" ++ &[_]u8 { 
        0x01, 0x02,
        0x03, 0x04,
        0x05, 0x06
    };
    var slice_reader = SliceReader.new(data);
    const color = try BinRW(Color).read(slice_reader.reader());
    const expected = Color {
        .r = 0x0201,
        .g = 0x0403,
        .b = 0x0605,
    };

    try std.testing.expectEqual(expected, color);
}

test "with_map" {
    const truncatU16 = struct {
        pub fn truncate(v: u16) u8 {
            return @truncate(v);
        }
    }.truncate;

    const Color = struct {
        pub const ZBINRW_META: type = struct {
            pub const MAGIC: []const u8 = "Color";
            pub const DEFUALT_ENDIAN: attr.Endian = .Little;
            g: Value.InBin(u16).Read(.{attr.Map(truncatU16)}).done(),
        };
        r: u16,
        g: u8,
        b: u16,
    };

    const data = "Color" ++ &[_]u8 { 
        0x01, 0x02,
        0x03, 0x04,
        0x05, 0x06
    };
    var slice_reader = SliceReader.new(data);
    const color = try BinRW(Color).read(slice_reader.reader());
    const expected = Color {
        .r = 0x0201,
        .g = 0x0003,
        .b = 0x0605,
    };

    try std.testing.expectEqual(expected, color);
}
