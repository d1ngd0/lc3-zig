const std = @import("std");
const instr = @import("../instr.zig");

const Instruction = instr.Instruction;
const Op = instr.Op;
const Registers = @import("../reg.zig").Registers;
const Condition = @import("../condition.zig").Condition;
const Register = Registers.Register;

// Assembler Formats:
//     AND DR, SR1, SR2
//     AND DR, SR1, imm5
//
// |15|14|13|12|11|10| 9| 8| 7| 6| 5| 4| 3| 2| 1| 0|
// |-----------------------------------------------|
// |    0001   |   DR   |   SR1  | 0|  00 |  SR2   |
// |-----------------------------------------------|
//
// |15|14|13|12|11|10| 9| 8| 7| 6| 5| 4| 3| 2| 1| 0|
// |-----------------------------------------------|
// |    0001   |   DR   |   SR1  | 1|   imm5       |
// |-----------------------------------------------|
//
// If bit [5] is 0, the second source operand is obtained from SR2. If bit [5] is 1,
// the second source operand is obtained by sign-extending the imm5 field to 16
// bits. In either case, the second source operand and the contents of SR1 are bit-
// wise ANDed, and the result stored in DR. The condition codes are set, based on
// whether the binary value produced, taken as a 2’s complement integer, is negative,
// zero, or positive
pub const And = packed struct {
    val: packed union {
        reg: packed struct {
            sr2: u3,
            _: u2,
        },
        val: u5,
    },
    isVal: bool,
    sr1: u3,
    dest: u3,

    pub fn execute(self: @This(), reg: *Registers, _: []u16) void {
        const dr: Register = @enumFromInt(self.dest);
        const sr1: Register = @enumFromInt(self.sr1);

        if (self.isVal) {
            reg.setReg(dr, reg.register(sr1) & instr.signExtend(self.val.val));
        } else {
            const sr2: Register = @enumFromInt(self.val.reg.sr2);
            reg.setReg(dr, reg.register(sr1) & reg.register(sr2));
        }
    }
};

test "opBitwiseAnd reg" {
    var reg = Registers.init();

    reg.registerPtr(.R1).* = 0b0101100101111111;
    reg.registerPtr(.R2).* = 0b1111111101010010;
    const num = @as(u16, @intFromEnum(Op.AND)) << 12 |
        @as(u16, @intFromEnum(Register.R0)) << 9 | // dr
        @as(u16, @intFromEnum(Register.R1)) << 6 | // sr1
        // 0 flag 00 unused
        @intFromEnum(Register.R2); // sr2
    const ins: Instruction = @bitCast(num);
    ins.execute(&reg, &.{});

    try std.testing.expectEqual(0b0101100101010010, reg.register(.R0));
}

test "opBitwiseAnd imm" {
    var reg = Registers.init();
    reg.registerPtr(.R1).* = 0b0000000000001001;

    const num = @as(u16, @intFromEnum(Op.AND)) << 12 |
        @as(u16, @intFromEnum(Register.R0)) << 9 | // dr
        @as(u16, @intFromEnum(Register.R1)) << 6 | // sr1
        1 << 5 | // set the imm flag
        0b11110; // sr2
    const ins: Instruction = @bitCast(num);
    ins.execute(&reg, &.{});

    try std.testing.expectEqual(0b0000000000001000, reg.register(.R0));
}
