<p align="center">
    <span>English</span>
    <span> | </span>
    <a href="README_CN.md">中文</a>
</p>
<p align="center" style="font-size: 32px; font-weight:bold;"><span>ZBinRW</span></p>
<p align="center"><span>A declarative binary file parsing library</span></p>

## example
To use `ZBinRW`, you need to define a public `ZBINRW_META` type in your `struct` or `tagged union`.

### parse to struct
To set the byte order for reading and writing, you need to declare a public const variable `DEFAULT_ENDIAN` of type `zbinrw.meta.Endian`.
```zig
const zbinrw = @import("zbinrw");
const meta = zbinrw.meta;
const attr = meta.attr;
const SliceReader = zbinrw.io.reader.SliceReader;
const BinRW = zbinrw.BinRW;

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
const expected = Color {
    .r = 0x0201,
    .g = 0x0403,
    .b = 0x0605,
};

var slice_reader = SliceReader.new(data);
// read function accept a std.io.Reader
const color = try BinRW(Color).read(slice_reader.reader());

try std.testing.expectEqual(expected, color);
```

To specify some magic number for your type, you need to declare a public const variable `MAGIC` of type `[]const u8`.
```zig
const zbinrw = @import("zbinrw");
const meta = zbinrw.meta;
const attr = meta.attr;
const SliceReader = zbinrw.io.reader.SliceReader;
const BinRW = zbinrw.BinRW;

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
const expected = Color {
    .r = 0x0201,
    .g = 0x0403,
    .b = 0x0605,
};

var slice_reader = SliceReader.new(data);
const color = try BinRW(Color).read(slice_reader.reader());

try std.testing.expectEqual(expected, color);
```

If you want some field in your type using a different byte order:
```zig
const zbinrw = @import("../zbinrw.zig");
const meta = zbinrw.meta;
const attr = meta.attr;
const SliceReader = zbinrw.io.reader.SliceReader;
const Value = meta.Value;
const BinRW = zbinrw.BinRW;

const Color = struct {
    pub const ZBINRW_META: type = struct {
        pub const DEFUALT_ENDIAN: attr.Endian = .Big;
        // the type of g in binary is u16, and its Read/Write attributes is `{ Endian.Little }`,
        // which means zbinrw would read this field with little-endian order
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
```

If `BinType` of a field is `T` and you want to map it to `U`, you can provide a map attribute.
```zig
const zbinrw = @import("../zbinrw.zig");
const meta = zbinrw.meta;
const attr = meta.attr;
const SliceReader = zbinrw.io.reader.SliceReader;
const Value = meta.Value;
const BinRW = zbinrw.BinRW;

const truncatU16 = struct {
    pub fn truncate(v: u16) u8 {
        return @truncate(v);
    }
}.truncate;

const Color = struct {
    pub const ZBINRW_META: type = struct {
        pub const MAGIC: []const u8 = "Color";
        pub const DEFUALT_ENDIAN: attr.Endian = .Little;
        // `BinType` is u16, `ValueType` is u8, so zbinrw need a read map to map(u16) -> u8
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
    .g = 0x0003, // truncate(0x0403) == 0x0003
    .b = 0x0605,
};

try std.testing.expectEqual(expected, color);
```

If a field is a pointer, you need to specify its len using Value.Size(len_ref). (len_ref is a field name in your type):
```zig
const Code = struct {
    pub const ZBINRW_META: type = struct {
        pub const MAGIC: []const u8 = "XVM";
        pub const DEFUALT_ENDIAN: attr.Endian = .Little;
        bytecode: Value.InBin([]const u8).Size("len").done()
    };
    //                                          |
    // .-----------------------------------------
    // v 
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
```

**More examples are in `tests`** 

### parse to union
`zbinrw` only support `tagged union`.

```zig
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
    0x01, // circle tag,
    0x02, 0x03, 0x04, 0x05, // r
};
const circle_expected = Shape {
    .Circle = Circle { .r = 0x05040302 }
};
var circle_reader = SliceReader.new(circle_data);
const circle = try BinRW(Shape).read(circle_reader.reader());
try std.testing.expectEqual(circle_expected, circle);

const rectangle_data = &[_] u8 {
    0x02, // rectangle tag,
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
```

## compile time checking and user-friendly error message
All the checking in `zbinrw` is done at compile time and would provide user-friendly error message if any error occurs.

### example
If we forget to provide a byte order:
```zig
const Color = struct {
    pub const ZBINRW_META: type = struct {
        // ops! wo forgot it!
        // pub const DEFUALT_ENDIAN: attr.Endian = .Little;
    };
    r: u16,
    g: u16,
    b: u16,
};
```
then we would get a compile error like:
```
error: Missing Read Endian of `tests.simple_struct.test.little.Color.r`.
```

If we forget to provide a map function:
```zig
const Color = struct {
    pub const ZBINRW_META: type = struct {
        pub const MAGIC: []const u8 = "Color";
        pub const DEFUALT_ENDIAN: attr.Endian = .Little;
        g: Value
            .InBin(u16)
            // ops! wo forgot it!
            // .Read(.{attr.Map(truncatU16)})
            .done(),
    };
    r: u16,
    g: u8,
    b: u16,
};
```
then we would get a compile error like:
```
Please define a Read Attr Map(map(u16) -> u8)
using Value.Read for field g in tests.simple_struct.test.with_map.Color.ZBINRW_META
```


If Size attribute refers to a non-existent field:
```zig
const Code = struct {
    pub const ZBINRW_META: type = struct {
        pub const MAGIC: []const u8 = "XVM";
        pub const DEFUALT_ENDIAN: attr.Endian = .Little;
        bytecode: Value
                    .InBin([]const u8)
                    // wait! there is no such field named "le"
                    .Size("le")
                    .done()
    };

    len: usize,
    bytecode: []const u8,
};
```
then we would get a compile error like:
```
error: There is no such field named `le` in `tests.struct_with_ptr.test.byte_ptr.Code` while the Size Attr of field `bytecode` reffernece to `le`
```

And there are more checking would be done at compile time.

