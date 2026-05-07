pub const Emulator = @import("emulator.zig").Emulator;
pub const Registers = @import("reg.zig").Registers;

test {
    @import("std").testing.refAllDecls(@This());
}
