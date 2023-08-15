// const CompiledStructuralMeta = struct {
//     BinType: type,
//     ValueType: type,
//     READ_ATTRS: Attrs,
//     WRITE_ATTRS: Attrs,
//     COMPILED_BINTYPE_META: ...,
// };
// 
// const Color = struct {
//     const ZBINRW_META = struct {
//         const MAGIC: []const u8 = "Color";
//         const DEFAULT_ENDIAN: meta.Endian = .Big;
//     }
//     r: u8,
//     g: u8,
//     b: u8,
// };
// 
// meta Color => CompiledStructuralMeta {
//     ...,
//     COMPILED_BINTYPE_META: struct {
//         r: CV,
//         g: CV,
//         b: CV,
//     }
// }
//
// const S = struct {
//     len: usize, 
//     c: []Color, 
// };
//
// meta S => CompiledStructuralMeta {
//     len: CV,
//     c: CV {
//        BinType: Color,
//        CompiledMeta: CompiledStructuralMeta { r: CV, g: CV, b: CV },
//        READ_ATTRS: .{ Size("len") },
//        WRITE_ATTRS: .{ Size("len") },
//     }
// }
// 
// const OS = enum {
//     Mac,
//     Linux,
//     Windows,
// };
// 
// meta OS => CV
// 
// const Shape = union(enum(u8)) {
//     Circle: Circle,
//     Square: Square,
// };
// 
// meta Shape => CompiledStructuralMeta {
//     ...,
//     COMPILED_BINTYPE_META: struct {
//         Circle: CompiledStructuralMeta {
//             BinType: Circle,
//             ValueType: Circle,
//             CompiledMeta: struct { r: CV },
//         },
//         Square: CompiledStructuralMeta {
//             BinType: Square,
//             ValueType: Square,
//             CompiledMeta: struct { r: CV },
//         },
//     }
// }
//

const std = @import("std");
const Type = std.builtin.Type;
const comptimePrint = std.fmt.comptimePrint;

const utils = @import("../utils.zig");
const assert = utils.assert;
const attributes = @import("attributes.zig");
const Attrs = attributes.Attrs;
const Endian = attributes.Endian;

pub const CompiledValueMeta = struct {
    BinType: type,
    ValueType: type,
    READ_ATTRS: Attrs,
    WRITE_ATTRS: Attrs,
};

const FieldInfo = struct {
    name: []const u8,
    type: type,
};

fn fieldLenOf(comptime T: type) comptime_int {
    const info: Type = @typeInfo(T);
    return switch (info) {
        .Struct => |s| s.fields.len,
        .Union => |u| u.fields.len,
        else => @compileError(comptimePrint(
            "Expected {s} is a Struct or Union but {s} is a {s}", 
            .{@typeName(T), @typeName(T), @tagName(info)}
        )),
    };
}

fn extractFieldInfo(comptime T: type) [fieldLenOf(T)]FieldInfo {
    var fields_info: [fieldLenOf(T)]FieldInfo = undefined;
    const info: Type = @typeInfo(T);
    switch (info) {
        .Struct => |s| {
            for (s.fields, &fields_info) |sf, *mf| {
                mf.name = sf.name;
                mf.type = sf.type;
            }
        },
        .Union => |u| {
            for (u.fields, &fields_info) |uf, *mf| {
                mf.name = uf.name;
                mf.type = uf.type;
            }
        },
        else => unreachable, // fieldLenOf would ensure T is Struct, Enum or Union
    }

    return fields_info;
}

fn StructWithFields(comptime fields: []const Type.StructField) type {
    const s = Type.Struct {
        .fields = fields,
        .decls = &[_]Type.Declaration{},
        .layout = .Auto,
        .backing_integer = null,
        .is_tuple = false,
    };
    const info = Type {
        .Struct = s,  
    };

    return @Type(info);
}

fn StructField(comptime name: []const u8, comptime T: type) Type.StructField {
    return Type.StructField {
        .name = name,
        .type = T,
        .default_value = null,
        .is_comptime = false,
        .alignment = @alignOf(T),
    };
}

fn CompiledStructuralType(
    comptime CompiledBinTypeMeta: type
) type {
    return StructWithFields(&[_] Type.StructField {
        StructField("BinType", type),
        StructField("ValueType", type),
        StructField("READ_ATTRS", Attrs),
        StructField("WRITE_ATTRS", Attrs),
        StructField("COMPILED_BINTYPE_META", CompiledBinTypeMeta),
    });
} 

fn StructrualTypeToFinalMetaType(comptime T: type) type {
    const t_fields = std.meta.fields(T);
    var m_fields: [t_fields.len]Type.StructField = undefined;
    inline for (t_fields, &m_fields) |tf, *mf| {
        const RWMeta = tryGetBinRWMetaIn(T) orelse DummyRWMeta;
        const FieldRWMeta = tryGetTypeOfField(RWMeta, tf.name);
        const FieldBinType = if (FieldRWMeta != null) FieldRWMeta.?.BinType else tf.type;
        const FieldMetaT = FinalMetaType(FieldBinType);
        mf.* = StructField(tf.name, FieldMetaT);
    }
    return CompiledStructuralType(StructWithFields(&m_fields));
}

pub fn FinalMetaType(comptime T: type) type {
    const t_info = @typeInfo(T);
    switch (t_info) {
        .Struct, .Union => return StructrualTypeToFinalMetaType(T), 
        .Pointer => |p| return CompiledStructuralType(FinalMetaType(p.child)),
        .Enum, .Int, .Float => return CompiledValueMeta,
        else => @compileError(comptimePrint(
            "ZBinRw do not support {s} type",
            .{@tagName(t_info)}
        )),
    }
}

const DummyRWMeta = struct {
    pub const READ_ATTRS = Attrs.new();
    pub const WRITE_ATTRS = Attrs.new();
};

/// Pass the BinType to this function and get a compiled meta 
pub fn compile(comptime T: type) type {
    return struct {
        pub fn to(comptime MetaT: type, comptime old_ctx: ?Ctx) MetaT {
            const ctx = old_ctx orelse Ctx.empty(T);
            const t_info = @typeInfo(T);
            return switch (t_info) {
                .Struct => compileStructrualTypeTo(MetaT, ctx),
                .Union => |u| compileUnionTo(u, MetaT, ctx),
                .Pointer => |p| compilePointerTo(p, MetaT, ctx),
                .Enum => |e| compile(e.tag_type).to(MetaT, Ctx.in(T, null, ctx)),
                .Int, .Float => compileNumericTypeTo(MetaT, ctx),
                else => unreachable,
            };
        }

        fn compileUnionTo(
            comptime u: Type.Union,
            comptime MetaT: type,
            comptime old_ctx: Ctx
        ) MetaT {
            comptime assert(
                u.tag_type != null,
                "ZBinRW does not support untagged union, and {s} is a untagged union",
                .{@typeName(T)}
            );
            return compileStructrualTypeTo(MetaT,  old_ctx);
        }

        fn compilePointerTo(
            comptime p: Type.Pointer,
            comptime MetaT: type,
            comptime old_ctx: Ctx
        ) MetaT {
            var compiled_meta = initCompiledMeta(MetaT, old_ctx);
            // check ptr size
            if (p.size == .One) {
                @compileError(comptimePrint(
                    "ZBinRW does not support reading or writting {} pointer",
                    .{@typeName(T)}
                ));
            }
            // check size attr
            const RWMeta = old_ctx.ParentRWMeta;
            if (tryGetTypeOfField(RWMeta, old_ctx.field_name.?)) |FieldMeta| {
                const READ_ATTRS: Attrs = FieldMeta.READ_ATTRS;
                if (READ_ATTRS.size) |size_attr| {
                    comptime assert(
                        @hasField(old_ctx.ParentT, size_attr.size),
                        "There is no such field named `{s}` in `{s}` while the Size Attr of field `{s}` reffernece to `{s}`",
                        .{size_attr.size, @typeName(old_ctx.ParentT), old_ctx.field_name.?, size_attr.size}
                    );
                    // check the type of size
                    const SizeT = tryGetTypeOfField(old_ctx.ParentT, size_attr.size).?;
                    const size_info = @typeInfo(SizeT);
                    comptime assert(
                        size_info == .Int or size_info == .Float,
                        "The type of field `{s}` of `{s}` as a Size attribute should be a numeric type but is `{s}`",
                        .{size_attr.size, @typeName(old_ctx.ParentT), @tagName(size_info)}
                    );
                    // check the order
                    inline for (std.meta.fields(old_ctx.ParentT)) |pf| {
                        if (std.mem.eql(u8, pf.name, old_ctx.field_name.?)) {
                            @compileError(comptimePrint(
                                "In {s}: The size reffernce field `{s}` is defined after `{s}`. Please define `{s}` before `{s}`!",
                                .{
                                        @typeName(old_ctx.ParentT), size_attr.size, 
                                        old_ctx.field_name.?, size_attr.size, old_ctx.field_name.?
                                    }
                            ));
                        } else if (std.mem.eql(u8, pf.name, size_attr.size)) {
                            break;
                        }
                    }
                    compiled_meta.READ_ATTRS.size = size_attr;
                    compiled_meta.WRITE_ATTRS.size = size_attr;
                } else {
                    @compileError(comptimePrint(
                        "Please set the Size Attr of field {s} in {s}.ZBINRW_META using Value.Size()",
                        .{@typeName(old_ctx.ParentT), old_ctx.field_name.?, @typeName(old_ctx.ParentT)}
                    ));
                }
            } else {
                @compileError(comptimePrint(
                    "Please define a field {s} with Size Attr in {s}.ZBINRW_META using Value.Size()",
                    .{@typeName(old_ctx.ParentT), old_ctx.field_name.?, @typeName(old_ctx.ParentT)}
                ));
            }

            const ChildT = p.child;
            compiled_meta.COMPILED_BINTYPE_META = compile(ChildT).to(FinalMetaType(ChildT), Ctx.in(T, null, old_ctx));
            
            return compiled_meta;
        }

        fn compileNumericTypeTo(comptime MetaT: type, comptime ctx: Ctx) MetaT {
            comptime assert(
                MetaT == CompiledValueMeta,
                "[ZBinRW Bug] compileNumericTypeTo: MetaT != CompiledValueMeta",
                .{}
            );

            var compiled_meta: CompiledValueMeta = initCompiledMeta(MetaT, ctx);

            if (ctx.field_name) |field_name| {
                // if field_name exist, then this is a field of ctx.ParentT
                // so the endian is the Endian defined in Attrs or the default endian
                var read_endian: ?Endian = null;
                var write_endian: ?Endian = null;
                if (tryGetTypeOfField(ctx.ParentRWMeta, field_name)) |FieldMeta| {
                    const READ_ATTRS = FieldMeta.READ_ATTRS;
                    const WRIET_ATTRS = FieldMeta.WRITE_ATTRS;
                    
                    read_endian = READ_ATTRS.endian orelse ctx.default_endian;
                    write_endian = WRIET_ATTRS.endian orelse ctx.default_endian;
                } else {
                    read_endian = ctx.default_endian;
                    write_endian = ctx.default_endian;
                }
                compiled_meta.READ_ATTRS.endian = read_endian orelse @compileError(comptimePrint(
                    "Missing Read Endian of `{s}.{s}`. ",
                    .{@typeName(ctx.ParentT), field_name}
                ));
                compiled_meta.WRITE_ATTRS.endian = write_endian orelse @compileError(comptimePrint(
                    "Missing Write Endian of `{s}.{s}`.",
                    .{@typeName(ctx.ParentT), field_name}
                ));
            } else if (ctx.default_endian) |default_endian| {
                compiled_meta.READ_ATTRS.endian = default_endian;
                compiled_meta.WRITE_ATTRS.endian = default_endian;
            } else {
                @compileError(comptimePrint(
                    "Missing bytes Endian of `{s}.{?}`. ",
                    .{@typeName(ctx.ParentT), ctx.field_name}
                ));
            }

            return compiled_meta;
        }

        fn compileStructrualTypeTo(
            comptime MetaT: type,
            comptime old_ctx: Ctx,
        ) MetaT {
            var compiled_meta: MetaT = initCompiledMeta(comptime MetaT, old_ctx);
            
            var cur_ctx = Ctx.in(T, null, old_ctx);
            for (std.meta.fields(T)) |field| {
                const RWMeta = tryGetBinRWMetaIn(T) orelse DummyRWMeta;
                const FieldRWMeta = tryGetTypeOfField(RWMeta, field.name);
                const FieldBinType = if (FieldRWMeta != null) FieldRWMeta.?.BinType else field.type;
                const FieldMetaT = FinalMetaType(FieldBinType);

                cur_ctx.field_name = field.name;
                const field_meta = compile(FieldBinType).to(FieldMetaT, cur_ctx);
                @field(compiled_meta.COMPILED_BINTYPE_META, field.name) = field_meta;
            }

            return compiled_meta;
        }

        fn initCompiledMeta(
            comptime MetaT: type,
            comptime old_ctx: Ctx,
        ) MetaT {
            var new_ctx = Ctx.in(T, null, old_ctx);

            var compiled_meta: MetaT = undefined;

            compiled_meta.READ_ATTRS = Attrs.new();
            compiled_meta.WRITE_ATTRS = Attrs.new();
            // set BinType
            compiled_meta.BinType = T;
            // set ValueType
            if (old_ctx.field_name) |field_name| {
                compiled_meta.ValueType = checkedGetTypeOfField(old_ctx.ParentT, field_name);
            } else {
                compiled_meta.ValueType = T;
            }
            // set Endian
            compiled_meta.READ_ATTRS.endian = new_ctx.default_endian;
            compiled_meta.WRITE_ATTRS.endian = new_ctx.default_endian;
            // set MagicBits
            const bits = tryGetMagicBitsOf(T, old_ctx);
            compiled_meta.READ_ATTRS.magic_bits = bits;
            compiled_meta.WRITE_ATTRS.magic_bits = bits;
            // check and set Map Attr
            if (checkedGetMapTable(old_ctx, T)) |map_table| {
                compiled_meta.READ_ATTRS.map = map_table.rmap;
                compiled_meta.WRITE_ATTRS.map = map_table.wmap;
            } else {
                compiled_meta.READ_ATTRS.map = null;
                compiled_meta.WRITE_ATTRS.map = null;
            }

            return compiled_meta;
        }

        /// check whether a field needs map attrs and return the MapTable if it has
        fn checkedGetMapTable(
            comptime ctx: Ctx,
            comptime BinType: type,
        ) ?MapTable {
            if (ctx.field_name == null) {
                // if ctx.field_name == null, then we in the first layer of meta
                // we don't need a map table
                // 
                // const Color = struct {  <- here we are
                //     r: usize,
                //     g: usize,
                //     b: usize,   
                // }
                // 
                return null;
            }
            // if `field_name` is not defined in ParentRWMeta 
            // then ValueT == BinType which means we don't need any Map Attr
            const RWMetaFieldT = tryGetTypeOfField(ctx.ParentRWMeta, ctx.field_name.?) orelse return null;
            const ValueT = tryGetTypeOfField(ctx.ParentT, ctx.field_name.?).?;
            if (ValueT == BinType) {
                // don't need map
                return null;
            }
            
            const READ_ATTRS: Attrs = RWMetaFieldT.READ_ATTRS;
            const WRITE_ATTRS: Attrs = RWMetaFieldT.WRITE_ATTRS;
            
            const t_info = @typeInfo(ValueT);
            const b_info = @typeInfo(BinType);
            if (
                (t_info != .Int and t_info != .Float) or
                (b_info != .Int and b_info != .Float) 
            ) {
                // if ValueT and BinType both are not Int or Float
                // then need a ReadMap(map(BinType) -> ValueType) 
                // and a WriteMap(map(ValueType) -> BinType)
                const rmap = checkedGetMapEntry(BinType, ValueT, "Read", READ_ATTRS, ctx);
                const wmap = checkedGetMapEntry(ValueT, BinType, "Write", WRITE_ATTRS, ctx);
                return MapTable.new(rmap, wmap);
            }
            
            const DUMMY_V: ValueT = undefined;
            const DUMMY_B: BinType = undefined;
            const PeerType = @TypeOf(DUMMY_V, DUMMY_B);

            if (PeerType == ValueT) {
                // if PeerType == ValueT then BinType can assign to ValueType
                // but ValueType can not assign to BinType
                // so we need a WriteMap(map(ValueType -> BinType))
                const wmap = checkedGetMapEntry(ValueT, BinType, "Write", WRITE_ATTRS, ctx);
                return MapTable.new(null, wmap);
            } else {
                // we need a ReadMap(map(BinType) -> ValueType)
                const rmap = checkedGetMapEntry(BinType, ValueT, "Read", READ_ATTRS, ctx);
                return MapTable.new(rmap, null);
            }
        }

        fn checkedGetMapEntry(
            comptime ExpectedArgT: type,
            comptime ExpectedRetT: type,
            comptime attr_type: []const u8,
            comptime attrs: Attrs,
            comptime ctx: Ctx,
        ) Attrs.MapEntry {
            comptime assert(
                attrs.map != null,
                \\Please define a {s} Attr Map(map({s}) -> {s})
                \\using Value.{s} for field {s} in {s}.ZBINRW_META
                ,
                .{
                    attr_type, @typeName(ExpectedArgT), @typeName(ExpectedRetT),
                    attr_type, ctx.field_name.?, @typeName(ctx.ParentT)
                }
            );
            // check the type of MapT
            const map_info = @typeInfo(attrs.map.?.map_t);
            const MArgT = map_info.Fn.params[0].type.?;
            const MRetT = map_info.Fn.return_type.?;
            comptime assert(
                MArgT == ExpectedArgT and
                MRetT == ExpectedRetT,
                \\ in {s}.ZBINRW_META.{s}:
                \\ Expected a {s} Attr Map(map({s}) -> {s}),
                \\ but got {s} Attr Map(map({s}) -> {s})
                ,
                .{
                    @typeName(ctx.ParentT), ctx.field_name.?,
                    attr_type, @typeName(ExpectedArgT), @typeName(ExpectedRetT),
                    attr_type, @typeName(MArgT), @typeName(MRetT),
                }
            );

            return attrs.map.?;
        }
    };
}

fn tryGetBinRWMetaIn(comptime U: type) ?type {
    const u_info = @typeInfo(U);
    if (u_info != .Struct and u_info != .Union and u_info != .Enum) {
        return null;
    }
    if (@hasDecl(U, "ZBINRW_META")) {
        const RWMeta = @field(U, "ZBINRW_META");
        checkIsVaildRWMeta(RWMeta, U);
        return RWMeta;
    } else {
        return null;
    }
}

fn checkIsVaildRWMeta(comptime RWMeta: anytype, comptime U: type) void {
    if (@TypeOf(RWMeta) != type) {
        @compileError(comptimePrint(
            "ZBINRW_META should be a struct type, but got {s}",
            .{@typeName(@TypeOf(RWMeta))}
        ));
    }
    
    if (@typeInfo(RWMeta) != .Struct) {
        @compileError(comptimePrint(
            "ZBINRW_META should be a Struct type, but got {s} type",
            .{@tagName(@typeInfo(RWMeta))}
        ));
    }

    const rw_info = @typeInfo(RWMeta);
    inline for (rw_info.Struct.fields) |f| {
        const error_msg = comptimePrint(
            "Expected all fields in {s}.ZBINRW_META is meta.Value.done() but field {s} is {s}",
            .{@typeName(U), f.name, @typeName(f.type) }
        );
        
        if (!@hasDecl(f.type, "BinType") or 
            !@hasDecl(f.type, "READ_ATTRS") or
            !@hasDecl(f.type, "WRITE_ATTRS")
        ) {
            @compileError(error_msg);
        }
        
        const FieldMeta: type = f.type;
        if (@TypeOf(FieldMeta.BinType) != type or
            @TypeOf(FieldMeta.READ_ATTRS) != Attrs or
            @TypeOf(FieldMeta.READ_ATTRS) != Attrs
        ) {
            @compileError(error_msg);
        }
    }
}

fn checkedGetTypeOfField(comptime U: type, comptime name: []const u8) type {
    if (tryGetTypeOfField(U, name)) |FieldType| {
        return FieldType;
    } else {
        @compileError(comptimePrint(
            "Expected a field {s} in type {s}",
            .{name, @typeName(U)}
        ));
    }
}

fn tryGetTypeOfField(comptime U: type, comptime name: []const u8) ?type {
    if (@hasField(U, name)) {
        const DUMMY_U: U = undefined;
        return @TypeOf(@field(DUMMY_U, name));
    } else {
        return null;
    }
}

fn checkedGetBinRWMetaIn(comptime U: type) type {
    if (tryGetBinRWMetaIn(U)) |RWMeta| {
        return RWMeta;
    } else {
        @compileError(comptimePrint(
            "Please define a ZBINRW_META in {s}",
            .{@typeName(U)}
        ));
    }
}

fn tryGetDefaultEndianIn(comptime U: type) ?Endian {
    const RWMeta = tryGetBinRWMetaIn(U) orelse return null;
    if (@hasDecl(RWMeta, "DEFUALT_ENDIAN")) {
        const DEFUALT_ENDIAN = @field(RWMeta, "DEFUALT_ENDIAN");
        if (@TypeOf(DEFUALT_ENDIAN) != Endian) {
            @compileError(comptimePrint(
                "DEFUALT_ENDIAN in {s}.ZBINRW_MEAT should be a meta.Endian, but got {s}",
                .{@typeName(U), @typeName(@TypeOf(DEFUALT_ENDIAN))}
            ));
        } else {
            return DEFUALT_ENDIAN;
        }
    } else {
        return null;
    }
}

fn tryGetMagicBitsOf(comptime T: type, comptime ctx: Ctx) ?Attrs.MagicBits {
    const RWMeta = tryGetBinRWMetaIn(T) orelse DummyRWMeta;
    var bits: []const u8 = "";

    if (ctx.field_name) |name| {
        const FieldMeta = tryGetTypeOfField(ctx.ParentRWMeta, name) orelse DummyRWMeta;
        if (FieldMeta.READ_ATTRS.magic_bits) |magic_bits| {
            bits = bits ++ magic_bits.bits;
        }
    }

    if (@hasDecl(RWMeta, "MAGIC")) {
        const MAGIC = @field(RWMeta, "MAGIC");
        if (@TypeOf(MAGIC) != []const u8) {
            @compileError(comptimePrint(
                "MAGIC in {s}.ZBINRW_MEAT should be a []const u8, but got {s}",
                .{@typeName(T), @typeName(@TypeOf(MAGIC))}
            ));
        } else {
            bits = bits ++ MAGIC;
        }
    }

    return Attrs.MagicBits.new(bits);
}

/// Read Map and Write Map
const MapTable = struct {
    rmap: ?Attrs.MapEntry,
    wmap: ?Attrs.MapEntry,
    
    pub fn new(
        comptime rmap: ?Attrs.MapEntry, 
        comptime wmap: ?Attrs.MapEntry
    ) MapTable {
        return MapTable { .rmap = rmap, .wmap = wmap };
    }
};

/// compile context
const Ctx = struct {
    ParentT: type,
    ParentRWMeta: type,
    field_name: ?[]const u8,
    default_endian: ?Endian,

    pub fn new(
        comptime ParentT: type,
        comptime ParentRWMeta: type,
        comptime field_name: ?[]const u8,
        comptime default_endian: ?Endian,
    ) Ctx {
        return Ctx {
            .ParentT = ParentT,
            .ParentRWMeta = ParentRWMeta,
            .field_name = field_name,
            .default_endian = default_endian,
        };
    }

    pub fn empty(
        comptime T: type
    ) Ctx {
        return Ctx.new(void, DummyRWMeta, null, comptime tryGetDefaultEndianIn(T));
    }

    pub fn in(comptime T: type, comptime field_name: ?[]const u8, comptime old: Ctx) Ctx {
        const cur_defualt_endian = comptime tryGetDefaultEndianIn(T) orelse old.default_endian;
        const CurRWMeta = comptime tryGetBinRWMetaIn(T) orelse DummyRWMeta;
        return Ctx.new(T, CurRWMeta, field_name, cur_defualt_endian);
    }
};
