const attributes = @import("attributes.zig");
const Attrs = attributes.Attrs;

pub const Value = struct {
    BinType: type,
    READ_ATTRS: Attrs,
    WRITE_ATTRS: Attrs, 

    const Self = @This();

    pub fn InBin(comptime T: type) Self {
        return Self {
            .BinType = T,
            .READ_ATTRS = Attrs.new(),
            .WRITE_ATTRS = Attrs.new(),
        };
    }

    pub fn Read(comptime self: Self, comptime attrs: anytype) Self {
        var new_v = self;
        new_v.READ_ATTRS = Attrs.fromTuple(attrs);
        return new_v;
    }

    pub fn Write(comptime self: Self, comptime attrs: anytype) Self {
        var new_v = self;
        new_v.WRITE_ATTRS = Attrs.fromTuple(attrs);
        return new_v;
    }

    pub fn RW(comptime self: Self, comptime attrs: anytype) Self {
        var new_v = self;
        const rw_attrs = Attrs.fromTuple(attrs);        
        new_v.READ_ATTRS = new_v.READ_ATTRS.checkedMerge(rw_attrs);
        new_v.WRITE_ATTRS = new_v.WRITE_ATTRS.checkedMerge(rw_attrs);
        
        return new_v;
    }

    pub fn Magic(comptime self: Self, comptime bits: []const u8) Self {
        var new_v = self;
        new_v.READ_ATTRS.magic_bits = Attrs.MagicBits.new(bits);
        new_v.WRITE_ATTRS.magic_bits = Attrs.MagicBits.new(bits);

        return new_v;
    }

    pub fn Size(comptime self: Self, comptime ref: []const u8) Self {
        var new_v = self;
        new_v.READ_ATTRS.size = Attrs.Size.new(ref);
        new_v.WRITE_ATTRS.size = Attrs.Size.new(ref);

        return new_v;
    }

    pub fn done(comptime self: Self) type {
        return struct {
            pub const BinType: type = self.BinType;
            pub const READ_ATTRS: Attrs = self.READ_ATTRS;
            pub const WRITE_ATTRS: Attrs = self.READ_ATTRS;
        };
    }
};
