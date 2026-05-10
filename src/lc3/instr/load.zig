const std = @import("std");
const instr = @import("../instr.zig");

const Instruction = instr.Instruction;
const Op = instr.Op;
const Registers = @import("../reg.zig").Registers;
const Condition = @import("../condition.zig").Condition;
const Register = Registers.Register;

// |15|14|13|12|11|10| 9| 8| 7| 6| 5| 4| 3| 2| 1| 0|
// |-----------------------------------------------|
// |    0010   |   DR   |          PCOffset9       |
// |-----------------------------------------------|
//
// An address is computed by sign-extending bits [8:0] to 16 bits and adding this
// value to the incremented PC. The contents of memory at this address are loaded
// into DR. The condition codes are set, based on whether the value loaded is
// negative, zero, or positive
pub const Load = packed struct {
    offset: u9,
    dr: u3,

    pub fn execute(self: @This(), reg: *Registers, mem: []u16) void {
        reg.setReg(@enumFromInt(self.dr), mem[reg.register(.PC) +% self.offset]);
    }
};

test "opLoad" {
    var mem: [1024]u16 = undefined;
    mem[100] = 255;
    var reg = Registers.init();

    const num = @as(u16, @intFromEnum(Op.LD)) << 12 |
        @as(u16, @intFromEnum(Register.R0)) << 9 |
        100;
    const ins: Instruction = @bitCast(num);
    ins.execute(&reg, &mem);

    try std.testing.expectEqual(255, reg.register(.R0));
    try std.testing.expectEqual(@intFromEnum(Condition.POS), reg.register(.COND));
}
