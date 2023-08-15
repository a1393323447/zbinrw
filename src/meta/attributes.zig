const std = @import("std");
const comptimePrint = std.fmt.comptimePrint;
const Type = std.builtin.Type;

const utils = @import("../utils.zig");
const assert = utils.assert;

pub const Endian = enum {
    Big,
    Little,
    Native,  
};

pub fn Map(comptime f: anytype) _Map(f) {
    return _Map(f){};
}

fn checkMapFnType(comptime Fn: type) !void {
    const info = @typeInfo(Fn);
    switch(info) {
        .Fn => |f_info| {
            const is_expected_map_fn = 
                f_info.params.len == 1 and
                f_info.return_type != null and
                f_info.return_type.? != void;
            
            if (!is_expected_map_fn) {
                return error.InvalidFn;
            }
        },
        else => return error.NotAFn,
    }
}

fn isMapAttr(comptime M: type) bool {
    return @hasDecl(M, "map") and
           isMapFnType(@TypeOf(@field(M, "map")));
} 

fn isMapFnType(comptime Fn: type) bool {
    if (checkMapFnType(Fn)) |_| {
        return true;
    } else |_| {
        return false;
    }
}

fn _Map(comptime f: anytype) type {
    const MapFn = @TypeOf(f);

    checkMapFnType(MapFn) 
    catch |err| switch (err) {
        .NotAFn => @compileError(comptimePrint(
            "In meta.Map, expected f is a Fn, but got {s}",
            .{@typeName(MapFn)}
        )),
        .InvaildFn => @compileError(comptimePrint(
                "In meta.Map, expected f take one arg and return one value, but f is {s}",
                .{@typeName(MapFn)}
        )),
    };
    
    return struct {
        pub const map: MapFn = f;  
    };
}

fn isMagicAttr(comptime M: type) bool {
    return @hasDecl(M, "bits") and
           @TypeOf(@field(M, "bits")) == []const u8;
}

fn isSizeAttr(comptime S: type) bool {
    return @hasDecl(S, "size") and
           @TypeOf(@field(S, "size")) == []const u8;
}

pub const Attrs = struct {
    endian: ?Endian = null,
    map: ?MapEntry = null,
    magic_bits: ?MagicBits = null,
    size: ?Size = null,

    pub fn new() Attrs {
        return Attrs {
            .endian = null,
            .map = null,
            .magic_bits = null,
            .size = null,
        };
    }

    pub const MapEntry = struct {
        map_t: type,
        map_fn: *const anyopaque,

        pub fn new(
            comptime map_t: type, 
            comptime map_fn: *const anyopaque
        ) MapEntry {
            return MapEntry { .map_t = map_t, .map_fn = map_fn };    
        }

        pub fn getMap(comptime self: MapEntry) self.map_t {
            const map_fn_ptr: *const self.map_t = @ptrCast(self.map_fn);
            return map_fn_ptr.*;
        }
    };

    pub const MagicBits = struct {
        bits: []const u8,
        
        pub fn new(b: []const u8) MagicBits {
            return MagicBits { .bits = b };
        }
    };

    pub const Size = struct {
        size: []const u8,

        pub fn new(s: []const u8) Size {
            return Size { .size = s };
        }
    };
    
    pub fn fromTuple(comptime attrs: anytype) Attrs {
        const AttrsT = @TypeOf(attrs);
        const attrs_info = @typeInfo(AttrsT);
        comptime assert(
            attrs_info == .Struct and
            attrs_info.Struct.is_tuple,            
            "Expected attrs is a Tuple but got {s}",
            .{@typeName(AttrsT)}
        );

        var res = Attrs.new();

        inline for (attrs_info.Struct.fields) |af| {
            if (af.type == Endian) {
                res.endian = @field(attrs, af.name);
            } else if (isMapAttr(af.type)) {
                res.map = MapEntry.new(@TypeOf(af.type.map), @ptrCast(&af.type.map));
            } else if (isMagicAttr(af.type)) {
                @compileError("MagicBits should be set with Value.Magic()");
            } else if (isSizeAttr(af.type)) {
                @compileError("Size attribute should be set with Value.Size()");
            } else {
                @compileError(comptimePrint(
                    \\Expected attribute is one of meta.Endian, meta.Map
                    \\but got {s}
                    ,
                    .{@typeName(af.type)}
                ));
            }
        }

        return res;
    }

    pub fn checkedMerge(comptime self: Attrs, comptime other: Attrs) Attrs {
        var res = self;
        const info = @typeInfo(Attrs);
        inline for (info.Struct.fields) |f| {
            if (@field(other, f.name)) |other_v| {
                if (@field(res, f.name) != null)  {
                    const attr_name = @typeName(f.type)[1..];
                    @compileError(comptimePrint(
                        "attribute {s} is duplicate or conflict with existed one in Read/Write",
                        .{attr_name, attr_name}
                    ));
                } else {
                    @field(res, f.name) = other_v;
                }
            }
        }

        return res;
    }
};
