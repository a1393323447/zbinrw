const std = @import("std");
const Type = std.builtin.Type;
const Allocator = std.mem.Allocator;
const comptimePrint = std.fmt.comptimePrint;

const attr = @import("meta.zig").attr;
const utils = @import("utils.zig");
const compiler = @import("meta/compiler.zig");
const SliceReader = @import("io.zig").reader.SliceReader;

pub const BinRWError = error {
    ErrorMagicBytes,
    UnknownEnumValue,
};

pub fn BinRW(comptime T: type) type {
    return struct {
        const MetaT = compiler.FinalMetaType(T);
        const META: MetaT = compiler.compile(T).to(MetaT, null);

        const RWImpl = BinRWRecursive(MetaT, META);
        const DummyParent = struct {};

        pub fn read(reader: anytype) RWImpl.ReadImpl(@TypeOf(reader), DummyParent).ReadError!T {
            var read_impl = RWImpl.ReadImpl(@TypeOf(reader), DummyParent).init(reader, null);
            return read_impl.read();
        }

        pub fn readWithAlloc(reader: anytype, allocator: Allocator) RWImpl.ReadImpl(@TypeOf(reader), DummyParent).ReadError!T {
            var read_impl = RWImpl.ReadImpl(@TypeOf(reader), DummyParent).init(reader, null);
            read_impl.setAllocator(allocator);
            return read_impl.read();
        }
    };
}

fn isPtrNeedAllocator(comptime META: anytype, comptime p: Type.Pointer) bool {
    const READ_ATTRS: attr.Attrs = META.READ_ATTRS;
    const child_info = @typeInfo(p.child);
    const is_u8: bool = p.child == u8;
    const is_numeric: bool = child_info == .Float or child_info == .Int or child_info == .Enum;
    const is_native_endian = READ_ATTRS.endian == .Native;
    const need_allocator: bool = !is_u8 and !(is_numeric and is_native_endian);
    return need_allocator;
}

fn BinRWRecursive(comptime MetaT: type, comptime META: MetaT) type {
return struct {

    pub fn ReadImpl(comptime Reader: type, comptime ParentT: type) type {
    return struct {
        reader: Reader,
        parent: ?*ParentT = null,
        allocator: ?Allocator = null,

        const Self = @This();
        pub const ReadError: type = BinRWError || Reader.Error || 
                            error{EndOfStream} || Allocator.Error;

        pub fn init(reader: Reader, parent: ?*ParentT) Self {
            return Self {
                .reader = reader,
                .parent = parent,
                .allocator = null,
            };
        }

        pub fn setAllocator(self: *Self, allocator: ?Allocator) void {
            self.allocator = allocator;
        }

        pub fn read(self: *Self) ReadError!META.ValueType {
            const READ_ATTRS: attr.Attrs = META.READ_ATTRS;

            if (READ_ATTRS.magic_bits) |magic_bits| {
                var bits: [magic_bits.bits.len]u8 = undefined;
                try self.reader.readNoEof(&bits);
                if (!std.mem.eql(u8, &bits, magic_bits.bits)) {
                    return BinRWError.ErrorMagicBytes;
                }
            }

            const t_info = @typeInfo(META.ValueType);
            const res: META.BinType = switch(t_info) {
                .Struct => |s| try self.readStruct(s),
                .Union => |u| try self.readUnion(u),
                .Pointer => |p| try self.readPointer(p),
                .Int, .Float => try self.readNumericWithEndian(META.BinType, READ_ATTRS.endian),
                else => unreachable,
            };

            if (READ_ATTRS.map) |map_entry| {
                const map = map_entry.getMap();
                return map(res);
            } else {
                return res;
            }
        }

        fn readStruct(self: *Self, comptime s: Type.Struct) ReadError!META.BinType {
            const COMPILED_BINTYPE_META = META.COMPILED_BINTYPE_META;
            
            var res: META.BinType = undefined;
            inline for (s.fields) |field| {
                const FIELD_META = @field(COMPILED_BINTYPE_META, field.name);
                const FieldReader = BinRWRecursive(@TypeOf(FIELD_META), FIELD_META)
                    .ReadImpl(Reader, META.BinType);
                var field_reader = FieldReader.init(self.reader, &res);
                field_reader.setAllocator(self.allocator);
                @field(res, field.name) = try field_reader.read();
            }

            return res;
        }

        fn readUnion(self: *Self, comptime u: Type.Union) ReadError!META.BinType {
            const COMPILED_BINTYPE_META = META.COMPILED_BINTYPE_META;

            var res: META.BinType = undefined;

            const READ_ATTRS: attr.Attrs = META.READ_ATTRS;
            const e_info = @typeInfo(u.tag_type.?);
            const ETagT = e_info.Enum.tag_type;

            const val = try self.readNumericWithEndian(ETagT, READ_ATTRS.endian);

            inline for (e_info.Enum.fields) |ef| {
                if (val == ef.value) {
                    const VARIANT_META = @field(COMPILED_BINTYPE_META, ef.name);
                    const VariantReader = BinRWRecursive(@TypeOf(VARIANT_META), VARIANT_META)
                        .ReadImpl(Reader, META.BinType);
                    var variant_reader = VariantReader.init(self.reader, &res);
                    const variant = try variant_reader.read();
                    variant_reader.setAllocator(self.allocator);
                    res = @unionInit(META.BinType, ef.name, variant);
                    
                    return res;
                }
            }

            return BinRWError.UnknownEnumValue;
        }

        fn readPointer(self: *Self, comptime p: Type.Pointer) ReadError!META.BinType {
            const READ_ATTRS: attr.Attrs = META.READ_ATTRS;

            const size_ref = READ_ATTRS.size.?.size;
            const len = @field(self.parent.?, size_ref);
            const need_allocator = comptime isPtrNeedAllocator(META, p);
            if (need_allocator or self.allocator != null) {
                return self.allocReadPtr(@intCast(len));
            } else {
                return self.zeroCopyReadPtr(@intCast(len));
            }
        }

        fn allocReadPtr(self: *Self, len: usize) ReadError!META.BinType {
            utils.assert(
                self.allocator != null,
                "ZBinRW need a allocator to allocate memory for pointer in {s} with type {s}.",
                .{@typeName(ParentT), @typeName(META.BinType)}
            );
            const CHILD_META = META.COMPILED_BINTYPE_META;
            const slice = try self.allocator.?.alloc(CHILD_META.BinType, len);
            const ChildReader = BinRWRecursive(@TypeOf(CHILD_META), CHILD_META)
                    .ReadImpl(Reader, CHILD_META.BinType);
            var child_reader = ChildReader.init(self.reader, null);
            for (slice) |*ele| {
                ele.* = try child_reader.read();
            }
            return @ptrCast(slice);
        }

        fn zeroCopyReadPtr(self: *Self, len: usize) ReadError!META.BinType {
            comptime utils.assert(
                    @TypeOf(self.reader.context) == *SliceReader,
                    "zcopy reading must use SliceReader",
                        .{}
                );
                const CHILD_META = META.COMPILED_BINTYPE_META;
                const remaining_bytes = self.reader.context.bytes.len;
                if (len > remaining_bytes) {
                    return error.EndOfStream;
                }
                const bytes = self.reader.context.bytes[0..(len * @sizeOf(CHILD_META.BinType))];
                const slice = std.mem.bytesAsSlice(CHILD_META.BinType, bytes);
                self.reader.context.bytes = self.reader.context.bytes[len..];
                return @alignCast(@ptrCast(slice));
        }

        inline fn readNumericWithEndian(self: *Self, comptime T: type, comptime endian: ?attr.Endian) ReadError!T {
            return switch (comptime endian.?) {
                .Big => try self.reader.readIntBig(T),
                .Little => try self.reader.readIntLittle(T),
                .Native => try self.reader.readIntNative(T),
            };
        }
    };
    }
};
}
