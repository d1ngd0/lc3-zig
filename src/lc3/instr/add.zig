const std = @import("std");
const instr = @import("../instr.zig");

const Instruction = instr.Instruction;
const Op = instr.Op;
const Registers = @import("../reg.zig").Registers;
const Condition = @import("../condition.zig");
const Register = Registers.Register;

// Assembler Formats:
//     ADD DR, SR1, SR2
//     ADD DR, SR1, imm5
//
// |15|14|13|12|11|10| 9| 8| 7| 6| 5| 4| 3| 2| 1| 0|
// |-----------------------------------------------|
// |  0001     |   DR   |   SR1  | 0|  00 |  SR2   |
// |-----------------------------------------------|
//
// |15|14|13|12|11|10| 9| 8| 7| 6| 5| 4| 3| 2| 1| 0|
// |-----------------------------------------------|
// |  0001     |   DR   |   SR1  | 1|   imm5       |
// |-----------------------------------------------|
//
// If bit [5] is 0, the second source operand is obtained from SR2. If bit [5] is 1, the
// second source operand is obtained by signoextending the imm5 field to 16 bits.
// In both cases, the second source operand is added to the contents of SR1 and the
// result stored in DR. The condition codes are set, based on whether the result is
// negative, zero, or positive.
pub const Add = packed struct {
    offset: packed struct {
        val: packed union {
            sr2: packed struct { val: u3, _: u2 },
            imm: u5,
        },
        immFlag: bool,
    },
    sr1: u3,
    dest: u3,

    pub fn execute(self: @This(), reg: *Registers, _: []u16) void {
        if (self.offset.immFlag) {
            reg.setReg(
                @enumFromInt(self.dest),
                reg.register(@enumFromInt(self.sr1)) +% instr.signExtend(self.offset.val.imm),
            );
        } else {
            reg.setReg(
                @enumFromInt(self.dest),
                reg.register(@enumFromInt(self.sr1)) +% reg.register(@enumFromInt(self.offset.val.sr2.val)),
            );
        }
    }
};

test "opAdd reg" {
    var reg = Registers.init();
    reg.registerPtr(.R1).* = 10;
    reg.registerPtr(.R2).* = 7;

    const num: u16 = @as(u16, @intFromEnum(Op.ADD)) << 12 |
        @as(u16, @intFromEnum(Register.R0)) << 9 | // dr
        @as(u16, @intFromEnum(Register.R1)) << 6 | // sr1
        // 0 flag 00 unused
        @intFromEnum(Register.R2); // sr2
    var ins: Instruction = @bitCast(num);

    ins.execute(&reg, &.{});
    try std.testing.expectEqual(17, reg.register(.R0));
}

test "opAdd imm" {
    var reg = Registers.init();
    reg.registerPtr(.R1).* = 10;

    const num: u16 = @as(u16, @intFromEnum(Op.ADD)) << 12 |
        @as(u16, @intFromEnum(Register.R0)) << 9 | // dr
        @as(u16, @intFromEnum(Register.R1)) << 6 | // sr1
        1 << 5 | // set the imm flag
        7; // sr2
    var ins: Instruction = @bitCast(num);

    ins.execute(&reg, &.{});
    try std.testing.expectEqual(17, reg.register(.R0));
}
