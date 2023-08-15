const std = @import("std");
const testing = std.testing;

const zbinrw = @import("../zbinrw.zig");
const meta = zbinrw.meta;
const attr = meta.attr;
const SliceReader = zbinrw.io.reader.SliceReader;
const Value = meta.Value;
const BinRW = zbinrw.BinRW;

test "byte_ptr" {
    const Code = struct {
        pub const ZBINRW_META: type = struct {
            pub const MAGIC: []const u8 = "XVM";
            pub const DEFUALT_ENDIAN: attr.Endian = .Little;
            bytecode: Value.InBin([]const u8).Size("len").done()
        };

        len: usize,
        bytecode: []const u8,
    };

    const bytecode = &[_]u8 { 
        0x01, 0x02,
        0x03, 0x04,
        0x05, 0x06
    };
    const len: usize = bytecode.len;
    const len_bytes = &[_]u8 { @intCast(len) } ++ (&[_]u8 { 0 } ** (@sizeOf(usize) - 1) );
    const data = "XVM" ++ len_bytes[0..] ++ bytecode;
    const expected = Code {
        .len = len,
        .bytecode = bytecode,
    };

    var slice_reader = SliceReader.new(data);
    const code = try BinRW(Code).read(slice_reader.reader());

    try std.testing.expectEqual(expected.len, code.len);
    try std.testing.expect(std.mem.eql(u8, expected.bytecode, code.bytecode));
}

// this example only pass on little endian machine
test "u32_ptr" {
    const U32Array = struct {
        pub const ZBINRW_META: type = struct {
            pub const DEFUALT_ENDIAN: attr.Endian = .Native; // expect native endian is little endian
            ele: Value.InBin([] const u32).Size("len").done()
        };

        len: u32,
        ele: [] const u32,
    };

    const ele_data = &[_]u8 {
        0x01, 0x00, 0x00, 0x00,
        0x00, 0x02, 0x00, 0x00,
        0x00, 0x00, 0x03, 0x00,
        0x00, 0x00, 0x00, 0x04,
    };
    const ele = &[_] u32 {
        0x00_00_00_01,
        0x00_00_02_00,
        0x00_03_00_00,
        0x04_00_00_00,
    };

    // u32 x 4
    const len_data = &[_] u8 {
        0x04, 0x00, 0x00, 0x00
    };
    const len: u32 = 4;

    const expected = U32Array {
        .len = len,
        .ele = ele,
    };

    const data = len_data ++ ele_data;
    
    var slice_reader = SliceReader.new(data);
    const arr = try BinRW(U32Array).read(slice_reader.reader());

    try std.testing.expectEqual(expected.len, arr.len);
    for (expected.ele, arr.ele) |ee, ae| {
        try std.testing.expectEqual(ee, ae);
    }
}

test "struct ptr" {
    const allocator = std.testing.allocator;
    const Color = struct {
        r: u8,
        g: u8,
        b: u8,
    };
    const Image = struct {
        pub const ZBINRW_META: type = struct {
            pub const DEFUALT_ENDIAN: attr.Endian = .Little;
            colors: Value.InBin([]Color).Size("len").done()
        };
        len: u32,
        colors: []Color,
    };

    const data = &[_] u8 {
        0x02, 0x00, 0x00, 0x00,
        0x01, 0x02, 0x03,
        0x04, 0x05, 0x06,
    };
    var colors = [_]Color {
        Color { .r = 0x1, .g = 0x2, .b = 0x3 },
        Color { .r = 0x4, .g = 0x5, .b = 0x6 },
    };
    const img_expected = Image {
        .len = 2,
        .colors = colors[0..],
    };

    var slice_reader = SliceReader.new(data);
    const img = try BinRW(Image).readWithAlloc(slice_reader.reader(), allocator);

    try std.testing.expectEqual(img_expected.len, img.len);

    for (img_expected.colors, img.colors) |ec, ac| {
        try std.testing.expectEqual(ec, ac);
    }

    allocator.free(img.colors);
}
