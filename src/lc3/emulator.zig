test {
    std.testing.refAllDeclsRecursive(@This());
}

const std = @import("std");

/// MAX_MEMORY defines the max memory the emulator
pub const MAX_MEMORY = 1 << 16;

// Emulator is the actual emulator that will run things
pub const Emulator = struct {
    //The LC-3 has 65,536 memory locations (the maximum that is addressable by a 16-bit unsigned integer 2^16), each of which stores a 16-bit value. This means it can store a total of only 128KB, which is a lot smaller than you may be used to! In our program, this memory will be stored in a simple array:
    memory: [MAX_MEMORY]u16,

    // A register is a slot for storing a single value on the CPU. Registers are like the “workbench” of the CPU. For the CPU to work with a piece of data, it has to be in one of the registers. However, since there are just a few registers, only a minimal amount of data can be loaded at any given time. Programs work around this by loading values from memory into registers, calculating values into other registers, and then storing the final results back in memory.
    // The LC-3 has 10 total registers, each of which is 16 bits. Most of them are general purpose, but a few have designated roles. - 8 general purpose registers (R0-R7) - 1 program counter (PC) register - 1 condition flags (COND) register
    // The general purpose registers can be used to perform any program calculations. The program counter is an unsigned integer which is the address of the next instruction in memory to execute. The condition flags tell us information about the previous calculation.
    reg: [@intFromEnum(Register.R_COUNT)]u16,

    // DEfAULT_START is the starting location for the application
    const DEFAULT_START = 0x3000;

    // Here we define the registers that are available to us
    pub const Register = enum(u16) {
        R_R0,
        R_R1,
        R_R2,
        R_R3,
        R_R4,
        R_R5,
        R_R6,
        R_R7,
        R_PC, //program counter
        R_COND,
        R_COUNT, //keep this at the end, tells us how many their are
    };

    // An instruction is a command which tells the CPU to do some fundamental task, such as add two numbers. Instructions have both an opcode which indicates the kind of task to perform and a set of parameters which provide inputs to the task being performed.
    // Each opcode represents one task that the CPU “knows” how to do. There are just 16 opcodes in LC-3. Everything the computer can calculate is some sequence of these simple instructions. Each instruction is 16 bits long, with the left 4 bits storing the opcode. The rest of the bits are used to store the parameters.
    // We will discuss, in detail, what each instruction does later. For now, define the following opcodes. Make sure they stay in this order so that they are assigned the proper enum value:
    pub const Instruction = enum(u16) {
        OP_BR, // branch
        OP_ADD, // add
        OP_LD, // load
        OP_ST, // store
        OP_JSR, // jump register
        OP_AND, // bitwise and
        OP_LDR, // load register
        OP_STR, // store register
        OP_RTI, // unused
        OP_NOT, // bitwise not
        OP_LDI, // load indirect
        OP_STI, // store indirect
        OP_JMP, // jump
        OP_RES, // reserved (unused)
        OP_LEA, // load effective address
        OP_TRAP, // execute trap
    };

    // The R_COND register stores condition flags which provide information about the most recently executed calculation. This allows programs to check logical conditions such as if (x > 0) { ... }.
    // Each CPU has a variety of condition flags to signal various situations. The LC-3 uses only 3 condition flags which indicate the sign of the previous calculation.
    pub const Condition = enum(u16) {
        FL_POS = 1 << 0, // P
        FL_ZRO = 1 << 1, // Z
        FL_NEG = 1 << 2, // N
    };

    const OFFSET_OP = 12;
    const BITMASK_REGISTER = 0b111;
    const BITMASK_FLAG = 0b1;
    const BITMASK_COND = 0b111;
    const BITMASK_IMMVAL5 = 0b11111;
    const BITMASK_IMMVAL6 = 0b111111;
    const BITMASK_IMMVAL9 = 0b111111111;
    const BITMASK_IMMVAL11 = 0b11111111111;

    // Init a new emluator
    pub fn init() Emulator {
        var em: Emulator = .{
            .memory = undefined,
            .reg = undefined,
        };

        em.registerPtr(.R_PC).* = 0;
        em.registerPtr(.R_COND).* = 0;

        return em;
    }

    // step returns the program counter and increments it by 1
    pub fn step(self: *Emulator) u16 {
        defer self.registerPtr(.R_PC).* += 1;
        return self.register(.R_PC);
    }

    // loadImage loads the program from the provided reader and pushes
    // it into memory.
    pub fn loadImage(self: *Emulator, reader: *std.Io.Reader) !void {
        var origin: u16 = undefined;
        const origin_ptr: *[2]u8 = @ptrCast(&origin);
        try reader.readSliceAll(origin_ptr);
        origin = @byteSwap(origin);

        const memory_ptr: *[MAX_MEMORY * @sizeOf(u16)]u8 = @ptrCast(&self.memory);
        _ = try reader.readSliceShort(memory_ptr[origin..]);

        for ((origin / @sizeOf(u16))..self.memory.len) |x| {
            self.memory[x] = @byteSwap(self.memory[x]);
        }
    }

    pub fn run(self: *Emulator) !void {
        // Set the z flag to start with
        self.registerPtr(.R_COND).* = @intFromEnum(Condition.FL_ZRO);
        // Set the program counter to the current location
        self.registerPtr(.R_PC).* = DEFAULT_START;

        // var running: bool = true;
        while (true) {
            const instr: u16 = self.memRead(self.step());
            const op: Instruction = @enumFromInt(instr >> OFFSET_OP);

            switch (op) {
                .OP_BR => self.opBranch(instr),
                .OP_ADD => self.opAdd(instr),
                .OP_LD => self.opLoad(instr), // load
                .OP_ST => break, // store
                .OP_JSR => self.opJumpSubroutine(instr), // jump register
                .OP_AND => self.opBitwiseAnd(instr),
                .OP_LDR => self.opLoadBaseOffset(instr), // load register
                .OP_STR => break, // store register
                .OP_RTI => unreachable,
                .OP_NOT => break, // bitwise not
                .OP_LDI => self.opLoadIndirect(instr),
                .OP_STI => break, // store indirect
                .OP_JMP => self.opJump(instr), // jump
                .OP_RES => unreachable, // reserved (unused)
                .OP_LEA => break, // load effective address
                .OP_TRAP => break, // execute trap
            }
        }
    }

    // |15|14|13|12|11|10| 9| 8| 7| 6| 5| 4| 3| 2| 1| 0|
    // |-----------------------------------------------|
    // |    0110   |   DR   |  BaseR |     offset6     |
    // |-----------------------------------------------|
    //
    // An address is computed by sign-extending bits [5:0] to 16 bits and adding this
    // value to the contents of the register specified by bits [8:6]. The contents of memory
    // at this address are loaded into DR. The condition codes are set, based on whether
    // the value loaded is negative, zero, or positive.
    fn opLoadBaseOffset(self: *Emulator, instr: u16) void {
        const dr: Register = @enumFromInt((instr >> 9) & BITMASK_REGISTER);
        const base: Register = @enumFromInt((instr >> 6) & BITMASK_REGISTER);
        const addr = self.register(base) + signExtend(instr & BITMASK_IMMVAL6, 6);
        self.registerPtr(dr).* = self.memRead(addr);
        self.updateConds(dr);
    }

    test "opLoadBaseOffset" {
        var em = Emulator.init();
        em.memory[20] = 100;
        em.registerPtr(.R_R0).* = 10;
        em.opLoadBaseOffset(@intFromEnum(Instruction.OP_LDR) << 12 |
            @intFromEnum(Register.R_R1) << 9 |
            @intFromEnum(Register.R_R0) << 9 |
            10);
        try std.testing.expectEqual(100, em.register(.R_R1));
    }

    // |15|14|13|12|11|10| 9| 8| 7| 6| 5| 4| 3| 2| 1| 0|
    // |-----------------------------------------------|
    // |    0010   |   DR   |          PCOffset9       |
    // |-----------------------------------------------|
    //
    // An address is computed by sign-extending bits [8:0] to 16 bits and adding this
    // value to the incremented PC. The contents of memory at this address are loaded
    // into DR. The condition codes are set, based on whether the value loaded is
    // negative, zero, or positive
    fn opLoad(self: *Emulator, instr: u16) void {
        const dr: Register = @enumFromInt(instr >> 9 & BITMASK_REGISTER);
        const offset = signExtend(instr & BITMASK_IMMVAL9, 9);
        self.registerPtr(dr).* = self.memRead(self.register(.R_PC) + offset);
        self.updateConds(dr);
    }

    test "opLoad" {
        var em = Emulator.init();
        em.memory[100] = 255;
        em.opLoad(@intFromEnum(Instruction.OP_LD) << 12 |
            @intFromEnum(Register.R_R0) << 9 |
            100);
        try std.testing.expectEqual(255, em.register(.R_R0));
        try std.testing.expectEqual(@intFromEnum(Condition.FL_POS), em.register(.R_COND));
    }

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
    fn opJumpSubroutine(self: *Emulator, instr: u16) void {
        self.registerPtr(.R_R7).* = self.register(.R_PC);

        if ((instr >> 11) & BITMASK_FLAG > 0) {
            const offset = signExtend(instr & BITMASK_IMMVAL11, 11);
            self.registerPtr(.R_PC).* = self.register(.R_PC) + offset;
        } else {
            const base: Register = @enumFromInt((instr >> 6) & BITMASK_REGISTER);
            self.registerPtr(.R_PC).* = self.register(base);
        }
    }

    test "opJumpSubroutine reg" {
        var em = Emulator.init();
        em.registerPtr(.R_PC).* = 100;
        em.registerPtr(.R_R0).* = 1000;

        em.opJumpSubroutine(@intFromEnum(Instruction.OP_JSR) << 12 |
            @intFromEnum(Register.R_R0) << 6);

        try std.testing.expectEqual(100, em.register(.R_R7));
        try std.testing.expectEqual(1000, em.register(.R_PC));
    }

    test "opJumpSubroutine imm" {
        var em = Emulator.init();
        em.registerPtr(.R_PC).* = 100;
        em.registerPtr(.R_R0).* = 1000;

        em.opJumpSubroutine(@intFromEnum(Instruction.OP_JSR) << 12 |
            1 << 11 |
            255);

        try std.testing.expectEqual(100, em.register(.R_R7));
        try std.testing.expectEqual(355, em.register(.R_PC));
    }

    // |15|14|13|12|11|10| 9| 8| 7| 6| 5| 4| 3| 2| 1| 0|
    // |-----------------------------------------------|
    // |    1010   |   000  |  BASE  |     000000      |
    // |-----------------------------------------------|
    // The program unconditionally jumps to the location specified by the contents of
    // the base register. Bits [8:6] identify the base register.
    //
    // The RET instruction is a special case of the JMP instruction. The PC is loaded
    // with the contents of R7, which contains the linkage back to the instruction
    // following the subroutine call instruction
    fn opJump(self: *Emulator, instr: u16) void {
        const base: Register = @enumFromInt((instr >> 6) & BITMASK_REGISTER);
        self.registerPtr(.R_PC).* = self.register(base);
    }

    test "jump" {
        var em: Emulator = Emulator.init();
        em.registerPtr(.R_R7).* = 100;
        em.opJump(@intFromEnum(Instruction.OP_JMP) << 12 | @intFromEnum(Register.R_R7) << 6);
        try std.testing.expectEqual(100, em.register(.R_PC));
    }

    // |15|14|13|12|11|10| 9| 8| 7| 6| 5| 4| 3| 2| 1| 0|
    // |-----------------------------------------------|
    // |    1010   |   DR   |       PCOffset9          |
    // |-----------------------------------------------|
    // An address is computed by sign-extending bits [8:0] to 16 bits and adding
    // this value to the incremented PC. What is stored in memory at this address
    // is the address of the data to be loaded into DR. (Pg. 532)
    fn opLoadIndirect(self: *Emulator, instr: u16) void {
        const dr = (instr >> 9) & BITMASK_REGISTER;
        const addr = signExtend(instr & BITMASK_IMMVAL9, 9) + self.register(.R_PC);
        self.reg[dr] = self.memRead(self.memRead(addr));
    }

    test "Load Indirect" {
        var em: Emulator = Emulator.init();
        // set memory location 9 to the address of memory location 10
        em.memory[9] = 10;
        // set memory location 10 to the value 255
        em.memory[10] = 255;

        em.opLoadIndirect((@intFromEnum(Instruction.OP_LDI) << 12) |
            @intFromEnum(Register.R_R0) << 9 |
            9);
        try std.testing.expectEqual(255, em.register(.R_R0));
    }

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
    fn opAdd(self: *Emulator, instr: u16) void {
        const dr: Register = @enumFromInt((instr >> 9) & BITMASK_REGISTER);
        const sr1: Register = @enumFromInt((instr >> 6) & BITMASK_REGISTER);
        const immFlag = (instr >> 5) & BITMASK_FLAG;

        if (immFlag == 1) {
            const immVal = signExtend(instr & BITMASK_IMMVAL5, 5);
            self.registerPtr(dr).* = self.register(sr1) + immVal;
        } else {
            const sr2: Register = @enumFromInt(instr & BITMASK_REGISTER);
            self.registerPtr(dr).* = self.register(sr1) + self.register(sr2);
        }
        self.updateConds(dr);
    }

    test "opAdd reg" {
        var em: Emulator = Emulator.init();
        em.registerPtr(.R_R1).* = 10;
        em.registerPtr(.R_R2).* = 7;
        em.opAdd(@intFromEnum(Instruction.OP_ADD) << 12 |
            @intFromEnum(Register.R_R0) << 9 | // dr
            @intFromEnum(Register.R_R1) << 6 | // sr1
            // 0 flag 00 unused
            @intFromEnum(Register.R_R2)); // sr2
        try std.testing.expectEqual(17, em.register(.R_R0));
    }

    test "opAdd imm" {
        var em: Emulator = Emulator.init();
        em.registerPtr(.R_R1).* = 10;
        em.opAdd(@intFromEnum(Instruction.OP_ADD) << 12 |
            @intFromEnum(Register.R_R0) << 9 | // dr
            @intFromEnum(Register.R_R1) << 6 | // sr1
            1 << 5 | // set the imm flag
            7); // sr2
        try std.testing.expectEqual(17, em.register(.R_R0));
    }

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
    fn opBitwiseAnd(self: *Emulator, instr: u16) void {
        const dr: Register = @enumFromInt((instr >> 9) & BITMASK_REGISTER);
        const sr1: Register = @enumFromInt((instr >> 6) & BITMASK_REGISTER);
        const immFlag = (instr >> 5) & BITMASK_FLAG;

        if (immFlag == 1) {
            const immVal = signExtend(instr & BITMASK_IMMVAL5, 5);
            self.registerPtr(dr).* = self.register(sr1) & immVal;
        } else {
            const sr2: Register = @enumFromInt(instr & BITMASK_REGISTER);
            self.registerPtr(dr).* = self.register(sr1) & self.register(sr2);
        }
        self.updateConds(dr);
    }

    test "opBitwiseAnd reg" {
        var em: Emulator = Emulator.init();
        em.registerPtr(.R_R1).* = 0b0101100101111111;
        em.registerPtr(.R_R2).* = 0b1111111101010010;
        em.opBitwiseAnd(@intFromEnum(Instruction.OP_AND) << 12 |
            @intFromEnum(Register.R_R0) << 9 | // dr
            @intFromEnum(Register.R_R1) << 6 | // sr1
            // 0 flag 00 unused
            @intFromEnum(Register.R_R2)); // sr2
        try std.testing.expectEqual(0b0101100101010010, em.register(.R_R0));
    }

    test "opBitwiseAnd imm" {
        var em: Emulator = Emulator.init();
        em.registerPtr(.R_R1).* = 0b0000000000001001;
        em.opBitwiseAnd(@intFromEnum(Instruction.OP_AND) << 12 |
            @intFromEnum(Register.R_R0) << 9 | // dr
            @intFromEnum(Register.R_R1) << 6 | // sr1
            1 << 5 | // set the imm flag
            0b11110); // sr2
        try std.testing.expectEqual(0b0000000000001000, em.register(.R_R0));
    }

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
    fn opBranch(self: *Emulator, instr: u16) void {
        const pcOffset: u16 = signExtend(instr & BITMASK_IMMVAL9, 9);
        const instrCond: u16 = instr >> 9 & BITMASK_COND;

        inline for (std.meta.fields(Condition)) |cond| {
            if (instrCond & cond.value > 0 and self.register(.R_COND) & cond.value > 0) {
                self.registerPtr(.R_PC).* = self.register(.R_PC) + pcOffset;
                return;
            }
        }
    }

    test "opBranch all" {
        var em: Emulator = Emulator.init();
        em.registerPtr(.R_COND).* = 0b111; // turn them all on
        em.opBranch(@intFromEnum(Instruction.OP_BR) << 12 |
            @intFromEnum(Condition.FL_NEG) << 9 |
            20);
        try std.testing.expectEqual(20, em.register(.R_PC));
    }

    test "opBranch n" {
        var em: Emulator = Emulator.init();
        em.registerPtr(.R_COND).* = @intFromEnum(Condition.FL_NEG);
        em.opBranch(@intFromEnum(Instruction.OP_BR) << 12 |
            @intFromEnum(Condition.FL_NEG) << 9 |
            20);
        try std.testing.expectEqual(20, em.register(.R_PC));

        em.registerPtr(.R_COND).* = 0;
        em.opBranch(@intFromEnum(Instruction.OP_BR) << 12 |
            @intFromEnum(Condition.FL_NEG) << 9 |
            20);
        try std.testing.expectEqual(20, em.register(.R_PC));
    }

    test "opBranch z" {
        var em: Emulator = Emulator.init();
        em.registerPtr(.R_COND).* = @intFromEnum(Condition.FL_ZRO);
        em.opBranch(@intFromEnum(Instruction.OP_BR) << 12 |
            @intFromEnum(Condition.FL_ZRO) << 9 |
            20);
        try std.testing.expectEqual(20, em.register(.R_PC));

        em.registerPtr(.R_COND).* = 0;
        em.opBranch(@intFromEnum(Instruction.OP_BR) << 12 |
            @intFromEnum(Condition.FL_ZRO) << 9 |
            20);
        try std.testing.expectEqual(20, em.register(.R_PC));
    }

    test "opBranch p" {
        var em: Emulator = Emulator.init();
        em.registerPtr(.R_COND).* = @intFromEnum(Condition.FL_POS);
        em.opBranch(@intFromEnum(Instruction.OP_BR) << 12 |
            @intFromEnum(Condition.FL_POS) << 9 |
            20);
        try std.testing.expectEqual(20, em.register(.R_PC));

        em.reg[@intFromEnum(Register.R_COND)] = 0;
        em.opBranch(@intFromEnum(Instruction.OP_BR) << 12 |
            @intFromEnum(Condition.FL_POS) << 9 |
            20);
        try std.testing.expectEqual(20, em.register(.R_PC));
    }

    // register returns the value within the specified register
    fn register(self: *Emulator, reg: Register) u16 {
        return self.reg[@intFromEnum(reg)];
    }

    fn registerPtr(self: *Emulator, reg: Register) *u16 {
        return &self.reg[@intFromEnum(reg)];
    }

    pub fn memRead(self: *Emulator, addr: u16) u16 {
        return self.memory[addr];
    }

    // updateFlags updates the R_COND register
    // Any time a value is written to a register, we need to update the flags
    // to indicate its sign. We will write a function so that this can be reused
    pub fn updateConds(self: *Emulator, r: Register) void {
        const p = self.registerPtr(r);
        if (p.* == 0) {
            self.registerPtr(.R_COND).* = @intFromEnum(Condition.FL_ZRO);
        } else if (p.* >> 15 == 1) {
            self.registerPtr(.R_COND).* = @intFromEnum(Condition.FL_NEG);
        } else {
            self.registerPtr(.R_COND).* = @intFromEnum(Condition.FL_POS);
        }
    }

    // signExtend takes a u16 that was orignally smaller and "sign extends"
    // it to a u16 size. If the value was positive we pad with 0s and if it
    // is negative we pad with 1s to retain the original value
    // https://en.wikipedia.org/wiki/Two%27s_complement
    fn signExtend(i: u16, comptime bitCount: u16) u16 {
        var val = i;
        // check if the values is negative
        // if so prepend it with 1 bits
        if ((val >> (bitCount - 1)) & 1 > 0) {
            val |= @as(u16, 0xffff) << bitCount;
        }

        return val;
    }
};
