const std = @import("std");
const Registers = @import("../reg.zig").Registers;
const Register = Registers.Register;
const instr = @import("../instr.zig");
const Condition = @import("../condition.zig").Condition;
const Op = instr.Op;
const Instruction = instr.Instruction;

// |15|14|13|12|11|10| 9| 8| 7| 6| 5| 4| 3| 2| 1| 0|
// |-----------------------------------------------|
// |    0110   |   DR   |  BaseR |     offset6     |
// |-----------------------------------------------|
//
// An address is computed by sign-extending bits [5:0] to 16 bits and adding this
// value to the contents of the register specified by bits [8:6]. The contents of memory
// at this address are loaded into DR. The condition codes are set, based on whether
// the value loaded is negative, zero, or positive.
pub const LoadRegister = packed struct {
    offset: u6,
    base: u3,
    dest: u3,

    pub fn execute(self: @This(), reg: *Registers, mem: []u16) void {
        const dr: Register = @enumFromInt(self.dest);
        const base: Register = @enumFromInt(self.base);
        const addr = reg.register(base) +% instr.signExtend(self.offset);
        reg.setReg(dr, mem[addr]);
    }
};

test "opLoadBaseOffset" {
    var reg = Registers.init();
    var mem: [1024]u16 = undefined;

    mem[20] = 100;
    reg.registerPtr(.R0).* = 10;
    const num = @as(u16, @intFromEnum(Op.LDR)) << 12 |
        @as(u16, @intFromEnum(Register.R1)) << 9 |
        @as(u16, @intFromEnum(Register.R0)) << 9 |
        10;
    const ins: Instruction = @bitCast(num);
    ins.execute(&reg, &mem);

    try std.testing.expectEqual(100, reg.register(.R1));
    try std.testing.expectEqual(@intFromEnum(Condition.POS), reg.register(.COND));
}
