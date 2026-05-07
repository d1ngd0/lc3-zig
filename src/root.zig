pub const lc3 = @import("lc3/root.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
