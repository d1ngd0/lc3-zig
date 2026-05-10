const std = @import("std");
const instr = @import("../instr.zig");
const Registers = @import("../reg.zig").Registers;
const Register = Registers.Register;
const Op = instr.Op;
const Instruction = instr.Instruction;

// |15|14|13|12|11|10| 9| 8| 7| 6| 5| 4| 3| 2| 1| 0|
// |-----------------------------------------------|
// |    0011   |   SR   |        PCOfsset9         |
// |-----------------------------------------------|
//
// The contents of the register specified by SR are stored in the memory location
// whose address is computed by sign-extending bits [8:0] to 16 bits and adding this
// value to the incremented PC
pub const Store = packed struct {
    offset: u9,
    sr1: u3,

    pub fn execute(self: @This(), reg: *Registers, mem: []u16) void {
        const addr = reg.register(.PC) +% instr.signExtend(self.offset);
        mem[addr] = reg.register(@enumFromInt(self.sr1));
    }
};

test "opStore" {
    var reg = Registers.init();
    reg.registerPtr(.R1).* = 100;

    var mem: [1024]u16 = undefined;

    const num = @as(u16, @intFromEnum(Op.ST)) << 12 |
        @as(u16, @intFromEnum(Register.R1)) << 9 |
        10;
    const ins: Instruction = @bitCast(num);
    ins.execute(&reg, &mem);

    try std.testing.expectEqual(100, mem[10]);
}
