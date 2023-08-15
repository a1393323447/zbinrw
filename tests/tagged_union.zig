const std = @import("std");
const testing = std.testing;

const zbinrw = @import("../zbinrw.zig");
const meta = zbinrw.meta;
const attr = meta.attr;
const SliceReader = zbinrw.io.reader.SliceReader;
const Value = meta.Value;
const BinRW = zbinrw.BinRW;


test "simple union" {
    const Circle = struct {
        r: u32,
    };

    const Rectangle = struct {
        w: u32,
        h: u32,
    };

    const ShapeTag = enum(u8) {
        Circle = 0x01,
        Rectangle = 0x02,
    };

    const Shape = union(ShapeTag) {
        pub const ZBINRW_META: type = struct {
            pub const DEFUALT_ENDIAN: attr.Endian = .Little;
        };
        Circle: Circle,
        Rectangle: Rectangle,
    };

    const circle_data = &[_] u8 {
        0x01, // tag,
        0x02, 0x03, 0x04, 0x05, // r
    };
    const circle_expected = Shape {
        .Circle = Circle { .r = 0x05040302 }
    };
    var circle_reader = SliceReader.new(circle_data);
    const circle = try BinRW(Shape).read(circle_reader.reader());
    try std.testing.expectEqual(circle_expected, circle);

    const rectangle_data = &[_] u8 {
        0x02, // tag,
        0x02, 0x03, 0x04, 0x05, // w
        0x06, 0x07, 0x08, 0x09, // h
    };
    const rectangle_expected = Shape {
        .Rectangle = Rectangle { 
            .w = 0x05040302,
            .h = 0x09080706,
        }
    };
    var rectangle_reader = SliceReader.new(rectangle_data);
    const rectangle = try BinRW(Shape).read(rectangle_reader.reader());
    try std.testing.expectEqual(rectangle_expected, rectangle);
}

