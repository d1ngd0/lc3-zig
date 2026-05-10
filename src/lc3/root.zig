pub const Emulator = @import("emulator.zig").Emulator;
pub const Registers = @import("reg.zig").Registers;
pub const Condition = @import("condition.zig").Condition;
pub const Instruction = @import("instr.zig").Instruction;

test {
    @import("std").testing.refAllDecls(@This());
}
