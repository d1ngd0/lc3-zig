const std = @import("std");
const instr = @import("../instr.zig");

const Instruction = instr.Instruction;
const Registers = @import("../reg.zig").Registers;
const Condition = @import("../condition.zig").Condition;
const Register = Registers.Register;

// Assembler Formats
//     BRn LABEL BRzp LABEL
//     BRz LABEL BRnp LABEL
//     BRp LABEL BRnz LABEL
//     BR† LABEL BRnzp LABEL
//
// |15|14|13|12|11|10| 9| 8| 7| 6| 5| 4| 3| 2| 1| 0|
// |-----------------------------------------------|
// |   0000    | n| z| p|         PCOffset9        |
// |-----------------------------------------------|
//
// The condition codes specified by the state of bits [11:9] are tested. If bit [11] is
// set, N is tested; if bit [11] is clear, N is not tested. If bit [10] is set, Z is tested, etc.
// If any of the condition codes tested is set, the program branches to the location
// specified by adding the sign-extended PCoffset9 field to the incremented PC.
pub const Branch = packed struct {
    pcOffset: u9,
    condition: Condition,

    pub fn execute(self: @This(), reg: *Registers, _: []u16) void {
        const pcOffset: u16 = instr.signExtend(self.pcOffset);

        inline for (std.meta.fields(Condition)) |cond| {
            if (@intFromEnum(self.condition) & cond.value > 0 and reg.register(.COND) & cond.value > 0) {
                reg.offsetPC(pcOffset);
                return;
            }
        }
    }
};

// Test the n condition being on
test "opBranch n" {
    var reg = Registers.init();

    reg.setCond(.NEG);
    (Instruction{
        .tag = .BR,
        .body = .{ .BR = .{
            .condition = .NEG,
            .pcOffset = 20,
        } },
    }).execute(&reg, &.{});
    try std.testing.expectEqual(20, reg.register(.PC));

    reg.setCond(.UNSET);
    (Instruction{
        .tag = .BR,
        .body = .{ .BR = .{
            .condition = .NEG,
            .pcOffset = 20,
        } },
    }).execute(&reg, &.{});
    try std.testing.expectEqual(20, reg.register(.PC));
}

// Test the z condition being on
test "opBranch z" {
    var reg = Registers.init();

    reg.setCond(.ZRO);
    (Instruction{
        .tag = .BR,
        .body = .{ .BR = .{
            .condition = .ZRO,
            .pcOffset = 20,
        } },
    }).execute(&reg, &.{});
    try std.testing.expectEqual(20, reg.register(.PC));

    reg.setCond(.UNSET);
    (Instruction{
        .tag = .BR,
        .body = .{ .BR = .{
            .condition = .ZRO,
            .pcOffset = 20,
        } },
    }).execute(&reg, &.{});
    try std.testing.expectEqual(20, reg.register(.PC));
}

// test the p condition being on
test "opBranch p" {
    var reg = Registers.init();

    reg.setCond(.POS);
    (Instruction{
        .tag = .BR,
        .body = .{ .BR = .{
            .condition = .POS,
            .pcOffset = 20,
        } },
    }).execute(&reg, &.{});
    try std.testing.expectEqual(20, reg.register(.PC));

    reg.setCond(.UNSET);
    (Instruction{
        .tag = .BR,
        .body = .{ .BR = .{
            .condition = .POS,
            .pcOffset = 20,
        } },
    }).execute(&reg, &.{});
    try std.testing.expectEqual(20, reg.register(.PC));
}
