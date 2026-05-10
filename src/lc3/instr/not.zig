const std = @import("std");
const Registers = @import("../reg.zig").Registers;
const Register = Registers.Register;
const instr = @import("../instr.zig");
const Condition = @import("../condition.zig").Condition;
const Op = instr.Op;
const Instruction = instr.Instruction;

// |15|14|13|12|11|10| 9| 8| 7| 6| 5| 4| 3| 2| 1| 0|
// |-----------------------------------------------|
// |    1001   |   DR   |   SR1  | 1|    11111     |
// |-----------------------------------------------|
//
// The bit-wise complement of the contents of SR is stored in DR. The condi-
// tion codes are set, based on whether the binary value produced, taken as a 2’s
// complement integer, is negative, zero, or positive
pub const Not = packed struct {
    _: u6,
    sr1: u3,
    dest: u3,

    pub fn execute(self: @This(), reg: *Registers, _: []u16) void {
        const dr: Register = @enumFromInt(self.dest);
        const sr1: Register = @enumFromInt(self.sr1);
        reg.setReg(dr, ~reg.register(sr1));
    }
};

test "opBitwiseComplement" {
    var reg = Registers.init();
    reg.registerPtr(.R0).* = 0b0000000011111111;

    const num = @as(u16, @intFromEnum(Op.NOT)) << 12 |
        @as(u16, @intFromEnum(Register.R1)) << 9 |
        @as(u16, @intFromEnum(Register.R0)) << 6 |
        0b111111;
    const ins: Instruction = @bitCast(num);
    ins.execute(&reg, &.{});

    try std.testing.expectEqual(0b1111111100000000, reg.register(.R1));
    try std.testing.expectEqual(@intFromEnum(Condition.NEG), reg.register(.COND));
}
