const std = @import("std");

const Condition = @import("condition.zig").Condition;

// A register is a slot for storing a single value on the CPU. Registers are like the “workbench” of the CPU. For the CPU to work with a piece of data, it has to be in one of the registers. However, since there are just a few registers, only a minimal amount of data can be loaded at any given time. Programs work around this by loading values from memory into registers, calculating values into other registers, and then storing the final results back in memory.
// The LC-3 has 10 total registers, each of which is 16 bits. Most of them are general purpose, but a few have designated roles. - 8 general purpose registers (R0-R7) - 1 program counter (PC) register - 1 condition flags (COND) register
// The general purpose registers can be used to perform any program calculations. The program counter is an unsigned integer which is the address of the next instruction in memory to execute. The condition flags tell us information about the previous calculation.
pub const Registers = struct {
    reg: [@intFromEnum(Register._COUNT)]u16,

    // Register is the reference location for each individual Register
    pub const Register = enum(u16) {
        R0,
        R1,
        R2,
        R3,
        R4,
        R5,
        R6,
        R7,
        PC,
        COND,
        _COUNT, //keep this at the end, tells us how many their are
    };

    pub fn init() @This() {
        var reg = @This(){
            .reg = undefined,
        };
        // Set the z flag to start with
        reg.setCond(.UNSET);
        // Set the program counter to the current location
        reg.setPC(0);

        return reg;
    }

    // register returns the value within the specified register
    pub fn register(self: *@This(), reg: Register) u16 {
        return self.reg[@intFromEnum(reg)];
    }

    // registerPtr return a pointer to the register, the value
    // being changed will update the register.
    pub fn registerPtr(self: *@This(), reg: Register) *u16 {
        return &self.reg[@intFromEnum(reg)];
    }

    // incPC increments the program counter by 1 and returns the previous value
    pub fn incPC(self: *@This()) u16 {
        defer self.registerPtr(.PC).* += 1;
        return self.register(.PC);
    }

    // setPC is a helper function which updates the value of the program counter to
    // the specified location.
    pub fn setPC(self: *@This(), loc: u16) void {
        self.registerPtr(.PC).* = loc;
    }

    /// offsetPC will add the specified offset to the program counter
    pub fn offsetPC(self: *@This(), offset: u16) void {
        self.registerPtr(.PC).* +%= offset;
    }

    // storePC will store the Program Counter into the specified Register
    pub fn storePCInto(self: *@This(), reg: Register) void {
        self.registerPtr(reg).* = self.register(.PC);
    }

    test "PC functions" {
        const testing = std.testing;
        var reg = Registers.init();
        reg.setPC(100);
        try testing.expectEqual(100, reg.incPC());
        try testing.expectEqual(101, reg.incPC());
    }

    // setReg sets the given register **AND** it sets the
    // COND register based on the sign of the value given
    pub fn setReg(self: *@This(), r: Register, val: u16) void {
        self.registerPtr(r).* = val;
        if (val == 0) {
            self.setCond(.ZRO);
        } else if (val >> 15 == 1) {
            self.setCond(.NEG);
        } else {
            self.setCond(.POS);
        }
    }

    // setCond will set the condition register
    pub fn setCond(self: *@This(), cond: Condition) void {
        self.registerPtr(.COND).* = @intCast(@intFromEnum(cond));
    }
};

test "Testing Register" {
    const testing = std.testing;
    const tests = [_]struct {
        name: []const u8,
        set: Registers.Register,
        value: u16,
    }{
        .{
            .name = "R0",
            .set = .R0,
            .value = 87,
        },
        .{
            .name = "R1",
            .set = .R1,
            .value = 100,
        },
        .{
            .name = "R2",
            .set = .R2,
            .value = 675,
        },
        .{
            .name = "R3",
            .set = .R3,
            .value = 23,
        },
        .{
            .name = "R4",
            .set = .R4,
            .value = 777,
        },
        .{
            .name = "R5",
            .set = .R5,
            .value = 4,
        },
        .{
            .name = "R6",
            .set = .R6,
            .value = 87,
        },
        .{
            .name = "R7",
            .set = .R7,
            .value = 188,
        },
        .{
            .name = "PC",
            .set = .PC,
            .value = 2000,
        },
        .{
            .name = "Cond",
            .set = .PC,
            .value = @intFromEnum(Condition.POS),
        },
    };

    for (tests) |t| {
        std.debug.print("subtest \"{s}\"\n", .{t.name});
        var reg = Registers.init();
        reg.registerPtr(t.set).* = t.value;
        try testing.expectEqual(t.value, reg.register(t.set));
    }
}
