<p align="center">
    <a href="README.md">English</a>
    <span> | </span>
    <span>中文</span>
</p>
<p align="center" style="font-size: 32px; font-weight:bold;"><span>ZBinRW</span></p>
<p align="center"><span>一个声明式二进制文件解析库</span></p>

## example
为了使用 `zbinrw`，你需要在你的类型中声明一个公有的 `ZBINRW_META` 类型。

### parse to struct
通过在你的结构体中声明一个类型为 `zbinrw.meta.Endian` 的公有常量 `DEFAULT_ENDIAN`，来指定读写时的字节序：
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

通过在你的结构体中声明一个类型为 `[]const u8` 的公有常量 `MAGIC`，来指定读写时该类型对应的二进制文件的 `Magic Number`：
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

如果结构体中的某几个字段的读写字节序和其它字段不同，你可以:
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

如果一个字段的 `BinType` 是 `T`，而你想将其转化成 `U` 类型，你可以：
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

如果某个字段是一个指针，你需要通过 Value.Size(len_ref) 来指定指针指向内存的长度（可以理解为数组的 size）：
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

**更多的例子请看 `tests` 目录** 

### parse to union
`zbinrw` 只支持 `tagged union`.

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

## 编译时检查以及可读性高的错误信息

`zbinrw` 会在编译期完成所有的检查，并且会提供可读性非常高的错误信息。

### example
如果我们没有提供读写字节序：
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
我们会得到错误信息，如下：
```
error: Missing Read Endian of `tests.simple_struct.test.little.Color.r`.
```

如果我们没有提供 map 函数:
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
我们会得到错误信息，如下：
```
Please define a Read Attr Map(map(u16) -> u8)
using Value.Read for field g in tests.simple_struct.test.with_map.Color.ZBINRW_META
```

如果 Size attribute 引用了一个不存在的字段:
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
我们会得到错误信息，如下：
```
error: There is no such field named `le` in `tests.struct_with_ptr.test.byte_ptr.Code` while the Size Attr of field `bytecode` reffernece to `le`
```

`zbinrw` 还在编译期进行其它更多的检查以确保读写的正确性。

