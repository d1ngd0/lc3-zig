const std = @import("std");
const Registers = @import("../reg.zig").Registers;
const Register = Registers.Register;
const instr = @import("../instr.zig");
const Condition = @import("../condition.zig").Condition;
const Op = instr.Op;
const Instruction = instr.Instruction;

// |15|14|13|12|11|10| 9| 8| 7| 6| 5| 4| 3| 2| 1| 0|
// |-----------------------------------------------|
// |           |   sr1  |  base  |     offset6     |
// |-----------------------------------------------|
// The contents of the register specified by SR are stored in the memory location
// whose address is computed by sign-extending bits [5:0] to 16 bits and adding this
// value to the contents of the register specified by bits [8:6]
pub const StoreRegister = packed struct {
    offset: u6,
    base: u3,
    sr1: u3,

    pub fn execute(self: @This(), reg: *Registers, mem: []u16) void {
        const sr: Register = @enumFromInt(self.sr1);
        const base: Register = @enumFromInt(self.base);
        const offset = reg.register(base) +% instr.signExtend(self.offset);
        mem[offset] = reg.register(sr);
    }
};

test "opStoreBaseOffset" {
    var reg = Registers.init();
    reg.registerPtr(.R0).* = 5;
    reg.registerPtr(.R1).* = 255;

    var mem: [1024]u16 = undefined;

    const num = @as(u16, @intFromEnum(Op.STR)) << 12 |
        @as(u16, @intFromEnum(Register.R1)) << 9 |
        @as(u16, @intFromEnum(Register.R0)) << 6 |
        5;
    const ins: Instruction = @bitCast(num);
    ins.execute(&reg, &mem);

    try std.testing.expectEqual(255, mem[10]);
}
