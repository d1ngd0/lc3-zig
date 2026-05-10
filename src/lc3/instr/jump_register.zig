const std = @import("std");
const instr = @import("../instr.zig");

const Instruction = instr.Instruction;
const Op = instr.Op;
const Registers = @import("../reg.zig").Registers;
const Condition = @import("../condition.zig");
const Register = Registers.Register;

// |15|14|13|12|11|10| 9| 8| 7| 6| 5| 4| 3| 2| 1| 0|
// |-----------------------------------------------|
// |    0100   | 1|         PCOffset11             | JSR
// |-----------------------------------------------|
//
// |15|14|13|12|11|10| 9| 8| 7| 6| 5| 4| 3| 2| 1| 0|
// |-----------------------------------------------|
// |    0100   | 0|  00 |  BASE  |      000000     | JSRR
// |-----------------------------------------------|
// First, the incremented PC is saved in R7. This is the linkage back to the calling
// routine. Then the PC is loaded with the address of the first instruction of the
// subroutine, causing an unconditional jump to that address. The address of the
// subroutine is obtained from the base register (if bit [11] is 0), or the address is
// computed by sign-extending bits [10:0] and adding this value to the incremented
// PC (if bit [11] is 1).
pub const JumpRegister = packed struct {
    offset: packed union {
        offset: u11,
        reg: packed struct {
            _unused1: u6,
            val: u3,
            _unused2: u2,
        },
    },
    inReg: bool,

    pub fn execute(self: @This(), reg: *Registers, _: []u16) void {
        reg.storePCInto(.R7);

        if (self.inReg) {
            const offset = instr.signExtend(self.offset.offset);
            reg.offsetPC(offset);
        } else {
            const base: Register = @enumFromInt(self.offset.reg.val);
            reg.setPC(reg.register(base));
        }
    }
};

test "opJumpSubroutine reg" {
    var reg = Registers.init();

    reg.registerPtr(.PC).* = 100;
    reg.registerPtr(.R0).* = 1000;

    const num = @as(u16, @intFromEnum(Op.JSR)) << 12 |
        @as(u16, @intFromEnum(Register.R0)) << 6;
    const ins: Instruction = @bitCast(num);
    ins.execute(&reg, &.{});

    try std.testing.expectEqual(100, reg.register(.R7));
    try std.testing.expectEqual(1000, reg.register(.PC));
}

test "opJumpSubroutine imm" {
    var reg = Registers.init();

    reg.registerPtr(.PC).* = 100;
    reg.registerPtr(.R0).* = 1000;

    const num = @as(u16, @intFromEnum(Op.JSR)) << 12 |
        1 << 11 |
        255;
    const ins: Instruction = @bitCast(num);
    ins.execute(&reg, &.{});

    try std.testing.expectEqual(100, reg.register(.R7));
    try std.testing.expectEqual(355, reg.register(.PC));
}
