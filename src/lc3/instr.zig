const std = @import("std");

const Registers = @import("reg.zig").Registers;
const Register = Registers.Register;
const Condition = @import("condition.zig").Condition;

pub const Branch = @import("instr/branch.zig").Branch;
pub const Add = @import("instr/add.zig").Add;
pub const Load = @import("instr/load.zig").Load;
pub const Store = @import("instr/store.zig").Store;
pub const JumpRegister = @import("instr/jump_register.zig").JumpRegister;
pub const And = @import("instr/and.zig").And;
pub const Not = @import("instr/not.zig").Not;
pub const LoadRegister = @import("instr/load_register.zig").LoadRegister;
pub const StoreRegister = @import("instr/store_register.zig").StoreRegister;

// An instruction is a command which tells the CPU to do some fundamental task, such as add two numbers. Instructions have both an opcode which indicates the kind of task to perform and a set of parameters which provide inputs to the task being performed.
// Each opcode represents one task that the CPU “knows” how to do. There are just 16 opcodes in LC-3. Everything the computer can calculate is some sequence of these simple instructions. Each instruction is 16 bits long, with the left 4 bits storing the opcode. The rest of the bits are used to store the parameters.
// We will discuss, in detail, what each instruction does later. For now, define the following opcodes. Make sure they stay in this order so that they are assigned the proper enum value:
pub const Op = enum(u4) {
    BR, // branch
    ADD, // add
    LD, // load
    ST, // store
    JSR, // jump register
    AND, // bitwise and
    LDR, // load register
    STR, // store register
    RTI, // unused
    NOT, // bitwise not
    LDI, // load indirect
    STI, // store indirect
    JMP, // jump
    RES, // reserved (unused)
    LEA, // load effective address
    TRAP, // execute trap
};

pub const Instruction = packed struct {
    body: packed union {
        BR: Branch,
        ADD: Add, // add
        LD: Load, // load
        ST: Store, // store
        JSR: JumpRegister, // jump register
        AND: And, // bitwise and
        LDR: LoadRegister, // load register
        STR: StoreRegister, // store register
        RTI: u12, // unused
        NOT: Not, // bitwise not
        LDI: u12, // load indirect
        STI: u12, // store indirect
        JMP: u12, // jump
        RES: u12, // reserved (unused)
        LEA: u12, // load effective address
        TRAP: u12, // execute trap
    },
    tag: Op,

    pub fn execute(self: @This(), reg: *Registers, mem: []u16) void {
        switch (self.tag) {
            .BR => self.body.BR.execute(reg, mem),
            .ADD => self.body.ADD.execute(reg, mem),
            .LD => self.body.LD.execute(reg, mem),
            .ST => self.body.ST.execute(reg, mem),
            .JSR => self.body.JSR.execute(reg, mem), // jump register
            .AND => self.body.AND.execute(reg, mem), // bitwise and
            .LDR => self.body.LDR.execute(reg, mem), // load register
            .STR => self.body.STR.execute(reg, mem), // store register
            .RTI => unreachable, // unused
            .NOT => self.body.NOT.execute(reg, mem), // bitwise not
            .LDI => unreachable, // load indirect
            .STI => unreachable, // store indirect
            .JMP => unreachable, // jump
            .RES => unreachable, // reserved (unused)
            .LEA => unreachable, // load effective address
            .TRAP => unreachable, // execute trap
        }
    }

    // The LC-3 provides a few predefined routines for performing common tasks and interacting with I/O devices.
    // For example, there are routines for getting input from the keyboard and for displaying strings to the console.
    // These are called trap routines which you can think of as the operating system or API for the LC-3.
    // Each trap routine is assigned a trap code which identifies it (similar to an opcode). To execute one,
    // the TRAP instruction is called with the trap code of the desired routine.
    const Trap = enum(u16) {
        TRAP_GETC = 0x20, // get character from keyboard, not echoed onto the terminal
        TRAP_OUT = 0x21, // output a character
        TRAP_PUTS = 0x22, // output a word string
        TRAP_IN = 0x23, // get character from keyboard, echoed onto the terminal
        TRAP_PUTSP = 0x24, // output a byte string
        TRAP_HALT = 0x25, // halt the program
    };
};

// signExtend takes a u16 that was orignally smaller and "sign extends"
// it to a u16 size. If the value was positive we pad with 0s and if it
// is negative we pad with 1s to retain the original value
// https://en.wikipedia.org/wiki/Two%27s_complement
pub fn signExtend(i: anytype) u16 {
    const bitCount = @bitSizeOf(@TypeOf(i));
    var val: u16 = @intCast(i);
    // check if the values is negative
    // if so prepend it with 1 bits
    if (val >> (bitCount - 1) > 0) {
        val |= @as(u16, 0xffff) << bitCount;
    }

    return val;
}

test "signExtend" {
    try std.testing.expectEqual(0b0000000000000001, signExtend(@as(u4, 0b0001)));
    try std.testing.expectEqual(0b1111111111111001, signExtend(@as(u4, 0b1001)));
    try std.testing.expectEqual(0b1111111111111111, signExtend(@as(u2, 0b11)));
}

test "u16 to Instruction" {
    const orig = Instruction{ .tag = .BR, .body = .{ .BR = .{ .condition = .UNSET, .pcOffset = 455 } } };

    const num: u16 = @bitCast(orig);
    try std.testing.expectEqual(0b0000000111000111, num);

    const instr: Instruction = @bitCast(num);
    try std.testing.expectEqual(orig, instr);
}

// run all the sub tests in the structs and stuff
test {
    @import("std").testing.refAllDecls(@This());
}
