test {
    std.testing.refAllDecls(@This());
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

    // in is the input device
    in: *std.Io.Reader,

    // out is the output device
    out: *std.Io.Writer,

    origTerm: std.posix.termios,

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

    pub const EmulationError = error{
        ExecutionHault,
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

    const MR_KBSR = 0xFE00; // keyboard status
    const MR_KBDR = 0xFE02; // keyboard data

    const NULL = 0x0;
    const OFFSET_OP = 12;
    const BITMASK_REGISTER = 0b111;
    const BITMASK_FLAG = 0b1;
    const BITMASK_COND = 0b111;
    const BITMASK_IMMVAL5 = 0b11111;
    const BITMASK_IMMVAL6 = 0b111111;
    const BITMASK_IMMVAL8 = 0b11111111;
    const BITMASK_IMMVAL9 = 0b111111111;
    const BITMASK_IMMVAL11 = 0b11111111111;

    // Init a new emluator
    pub fn init(in: *std.Io.Reader, out: *std.Io.Writer) !Emulator {
        var em: Emulator = .{
            .memory = undefined,
            .reg = undefined,
            .in = in,
            .out = out,
            .origTerm = try std.posix.tcgetattr(std.posix.STDIN_FILENO),
        };

        em.registerPtr(.R_PC).* = 0;
        em.registerPtr(.R_COND).* = 0;

        return em;
    }

    pub fn initStd(io: std.Io, rbuf: []u8, wbuf: []u8) !Emulator {
        var stdin = std.Io.File.stdin().reader(io, rbuf);
        var stdout = std.Io.File.stdout().writer(io, wbuf);
        return .init(&stdin.interface, &stdout.interface);
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
        const size = try reader.readSliceShort(memory_ptr[origin * @sizeOf(u16) ..]) / @sizeOf(u16);

        for (origin..origin + size) |x| {
            self.memory[x] = @byteSwap(self.memory[x]);
        }
    }

    pub fn run(self: *Emulator) !void {
        try self.disableInputBuffering();
        defer self.restoreInputBuffering() catch {};
        // Set the z flag to start with
        self.registerPtr(.R_COND).* = @intFromEnum(Condition.FL_ZRO);
        // Set the program counter to the current location
        self.registerPtr(.R_PC).* = DEFAULT_START;

        // var running: bool = true;
        while (true) {
            const instr: u16 = self.memRead(self.step());
            // std.debug.print("{b:0>16}\n", .{instr});
            const op: Instruction = @enumFromInt(instr >> OFFSET_OP);

            try switch (op) {
                .OP_BR => self.opBranch(instr),
                .OP_ADD => self.opAdd(instr),
                .OP_LD => self.opLoad(instr), // load
                .OP_ST => self.opStore(instr), // store
                .OP_JSR => self.opJumpSubroutine(instr), // jump register
                .OP_AND => self.opBitwiseAnd(instr),
                .OP_LDR => self.opLoadBaseOffset(instr), // load register
                .OP_STR => self.opStoreBaseOffset(instr), // store register
                .OP_RTI => unreachable,
                .OP_NOT => self.opBitwiseComplement(instr), // bitwise not
                .OP_LDI => self.opLoadIndirect(instr),
                .OP_STI => self.opStoreIndirect(instr), // store indirect
                .OP_JMP => self.opJump(instr), // jump
                .OP_RES => unreachable, // reserved (unused)
                .OP_LEA => self.opLoadEffectiveAddress(instr), // load effective address
                .OP_TRAP => self.opTrap(instr), // execute trap
            };
        }
    }

    // |15|14|13|12|11|10| 9| 8| 7| 6| 5| 4| 3| 2| 1| 0|
    // |-----------------------------------------------|
    // |    1111   |    0000   |       trapvec8        |
    // |-----------------------------------------------|
    //
    // First R7 is loaded with the incremented PC. (This enables a return to the instruction
    // physically following the TRAP instruction in the original program after the service
    // routine has completed execution.) Then the PC is loaded with the starting address
    // of the system call specified by trapvector8. The starting address is contained in
    // the memory location whose address is obtained by zero-extending trapvector8 to
    // 16 bits.
    fn opTrap(self: *Emulator, instr: u16) !void {
        self.registerPtr(.R_R7).* = self.register(.R_PC);
        const trap: Trap = @enumFromInt(instr & BITMASK_IMMVAL8);
        try switch (trap) {
            .TRAP_GETC => self.trapGetC(), // get character from keyboard, not echoed onto the terminal
            .TRAP_OUT => self.trapOut(), // output a character
            .TRAP_PUTS => self.trapPuts(), // output a word string
            .TRAP_IN => self.trapIn(), // get character from keyboard, echoed onto the terminal
            .TRAP_PUTSP => self.trapPUTSP(), // output a byte string
            .TRAP_HALT => self.trapHalt(), // halt the program
        };
    }

    // Halt execution and print a message on the console.
    fn trapHalt(self: *Emulator) !void {
        try self.out.writeAll("goodbye");
        try self.out.flush();
        return EmulationError.ExecutionHault;
    }

    test "trapHalt" {
        var em = try Emulator.initStd(std.testing.io, &.{}, &.{});
        try std.testing.expectError(EmulationError.ExecutionHault, em.trapHalt());
    }

    // Write a string of ASCII characters to the console. The characters are contained in
    // consecutive memory locations, two characters per memory location, starting with the
    // address specified in R0. The ASCII code contained in bits [7:0] of a memory location
    // is written to the console first. Then the ASCII code contained in bits [15:8] of that
    // memory location is written to the console. (A character string consisting of an odd
    // number of characters to be written will have x00 in bits [15:8] of the memory
    // location containing the last character to be written.) Writing terminates with the
    // occurrence of x0000 in a memory location
    fn trapPUTSP(self: *Emulator) !void {
        for (self.register(.R_R0)..MAX_MEMORY) |a| {
            const addr: u16 = @intCast(a);
            if (self.memRead(addr) == NULL) {
                break;
            }

            const chars: *[2]u8 = @ptrCast(self.memPtr(addr));
            try self.out.writeByte(chars.*[1]);
            if (chars[0] != NULL) {
                try self.out.writeByte(chars.*[0]);
            }
            try self.out.flush();
        }
    }

    // Print a prompt on the screen and read a single character from the keyboard. The
    // character is echoed onto the console monitor, and its ASCII code is copied into R0.
    // The high eight bits of R0 are cleared
    fn trapIn(self: *Emulator) !void {
        try self.out.writeAll("> ");
        try self.out.flush();
        try self.trapGetC();
        try self.trapOut();
    }

    // Write a string of ASCII characters to the console display. The characters are contained
    // in consecutive memory locations, one character per memory location, starting with
    // the address specified in R0. Writing terminates with the occurrence of x0000 in a
    // memory location
    fn trapPuts(self: *Emulator) !void {
        for (self.register(.R_R0)..MAX_MEMORY) |a| {
            const addr: u16 = @intCast(a);
            if (self.memRead(addr) == NULL) {
                break;
            }
            try self.out.writeByte(@intCast(self.memRead(addr) & BITMASK_IMMVAL8));
        }
        try self.out.flush();
    }

    // Write a character in R0[7:0] to the console display
    fn trapOut(self: *Emulator) !void {
        _ = try self.out.writeByte(@intCast(self.register(.R_R0) & BITMASK_IMMVAL8));
        try self.out.flush();
    }

    // Read a single character from the keyboard. The character is not echoed onto the
    // console. Its ASCII code is copied into R0. The high eight bits of R0 are cleared.
    fn trapGetC(self: *Emulator) !void {
        const char: u8 = try self.in.takeByte();
        self.registerPtr(.R_R0).* = char & BITMASK_IMMVAL8;
    }

    // |15|14|13|12|11|10| 9| 8| 7| 6| 5| 4| 3| 2| 1| 0|
    // |-----------------------------------------------|
    // |    0111   |   SR   |  BaseR |   PCOffset6     |
    // |-----------------------------------------------|
    //
    // The contents of the register specified by SR are stored in the memory location
    // whose address is computed by sign-extending bits [5:0] to 16 bits and adding this
    // value to the contents of the register specified by bits [8:6]
    fn opStoreBaseOffset(self: *Emulator, instr: u16) void {
        const sr: Register = @enumFromInt((instr >> 9) & BITMASK_REGISTER);
        const base: Register = @enumFromInt((instr >> 6) & BITMASK_REGISTER);
        const offset = self.register(base) +% signExtend((instr & BITMASK_IMMVAL6), 6);
        self.memPtr(offset).* = self.register(sr);
    }

    test "opStoreBaseOffset" {
        var em = try Emulator.initStd(std.testing.io, &.{}, &.{});
        em.registerPtr(.R_R0).* = 5;
        em.registerPtr(.R_R1).* = 255;
        em.opStoreBaseOffset(@intFromEnum(Instruction.OP_STR) << 12 |
            @intFromEnum(Register.R_R1) << 9 |
            @intFromEnum(Register.R_R0) << 6 |
            5);
        try std.testing.expectEqual(255, em.memRead(10));
    }

    // |15|14|13|12|11|10| 9| 8| 7| 6| 5| 4| 3| 2| 1| 0|
    // |-----------------------------------------------|
    // |    1011   |   SR   |        PCOfsset9         |
    // |-----------------------------------------------|
    //
    // The contents of the register specified by SR are stored in the memory location
    // whose address is obtained as follows: Bits [8:0] are sign-extended to 16 bits and
    // added to the incremented PC. What is in memory at this address is the address of
    // the location to which the data in SR is stored
    fn opStoreIndirect(self: *Emulator, instr: u16) void {
        const sr: Register = @enumFromInt((instr >> 9) & BITMASK_REGISTER);
        const addr = self.register(.R_PC) +% signExtend(instr & BITMASK_IMMVAL9, 9);
        self.memPtr(self.memRead(addr)).* = self.register(sr);
    }

    test "opStoreIndirect" {
        var em = try Emulator.initStd(std.testing.io, &.{}, &.{});
        em.registerPtr(.R_R1).* = 255;
        em.memPtr(5).* = 10;
        em.opStoreIndirect(@intFromEnum(Instruction.OP_STI) << 12 |
            @intFromEnum(Register.R_R1) << 9 |
            5);
        try std.testing.expectEqual(255, em.memRead(10));
    }

    // |15|14|13|12|11|10| 9| 8| 7| 6| 5| 4| 3| 2| 1| 0|
    // |-----------------------------------------------|
    // |    0011   |   SR   |        PCOfsset9         |
    // |-----------------------------------------------|
    //
    // The contents of the register specified by SR are stored in the memory location
    // whose address is computed by sign-extending bits [8:0] to 16 bits and adding this
    // value to the incremented PC
    fn opStore(self: *Emulator, instr: u16) void {
        const sr: Register = @enumFromInt((instr >> 9) & BITMASK_REGISTER);
        const addr = self.register(.R_PC) +% signExtend(instr & BITMASK_IMMVAL9, 9);
        self.memPtr(addr).* = self.register(sr);
    }

    test "opStore" {
        var em = try Emulator.initStd(std.testing.io, &.{}, &.{});
        em.registerPtr(.R_R1).* = 100;
        em.opStore(@intFromEnum(Instruction.OP_ST) << 12 |
            @intFromEnum(Register.R_R1) << 9 |
            10);
        try std.testing.expectEqual(100, em.memRead(10));
    }

    // |15|14|13|12|11|10| 9| 8| 7| 6| 5| 4| 3| 2| 1| 0|
    // |-----------------------------------------------|
    // |    1001   |   DR   |   SR1  | 1|    11111     |
    // |-----------------------------------------------|
    //
    // The bit-wise complement of the contents of SR is stored in DR. The condi-
    // tion codes are set, based on whether the binary value produced, taken as a 2’s
    // complement integer, is negative, zero, or positive
    fn opBitwiseComplement(self: *Emulator, instr: u16) void {
        const dr: Register = @enumFromInt((instr >> 9) & BITMASK_REGISTER);
        const sr1: Register = @enumFromInt((instr >> 6) & BITMASK_REGISTER);
        self.registerPtr(dr).* = ~self.register(sr1);
        self.updateConds(dr);
    }

    test "opBitwiseComplement" {
        var em = try Emulator.initStd(std.testing.io, &.{}, &.{});
        em.registerPtr(.R_R0).* = 0b0000000011111111;
        em.opBitwiseComplement(@intFromEnum(Instruction.OP_NOT) << 12 |
            @intFromEnum(Register.R_R1) << 9 |
            @intFromEnum(Register.R_R0) << 6 |
            0b111111);
        try std.testing.expectEqual(0b1111111100000000, em.register(.R_R1));
        try std.testing.expectEqual(@intFromEnum(Condition.FL_NEG), em.register(.R_COND));
    }

    // |15|14|13|12|11|10| 9| 8| 7| 6| 5| 4| 3| 2| 1| 0|
    // |-----------------------------------------------|
    // |    1110   |   DR   |        PCOffset9         |
    // |-----------------------------------------------|
    //
    // An address is computed by sign-extending bits [8:0] to 16 bits and adding this
    // value to the incremented PC. This address is loaded into DR.‡ The condition
    // codes are set, based on whether the value loaded is negative, zero, or positive.
    fn opLoadEffectiveAddress(self: *Emulator, instr: u16) void {
        const dr: Register = @enumFromInt((instr >> 9) & BITMASK_REGISTER);
        const addr = self.register(.R_PC) +% signExtend(instr & BITMASK_IMMVAL9, 9);
        self.registerPtr(dr).* = addr;
        self.updateConds(dr);
    }

    test "loadeffectiveaddress" {
        var em = try Emulator.initStd(std.testing.io, &.{}, &.{});
        em.opLoadEffectiveAddress(@intFromEnum(Instruction.OP_LEA) << 12 |
            @intFromEnum(Register.R_R0) << 9 |
            100);
        try std.testing.expectEqual(100, em.register(.R_R0));
        try std.testing.expectEqual(@intFromEnum(Condition.FL_POS), em.register(.R_COND));
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
        const addr = self.register(base) +% signExtend(instr & BITMASK_IMMVAL6, 6);
        self.registerPtr(dr).* = self.memRead(addr);
        self.updateConds(dr);
    }

    test "opLoadBaseOffset" {
        var em = try Emulator.initStd(std.testing.io, &.{}, &.{});
        em.memory[20] = 100;
        em.registerPtr(.R_R0).* = 10;
        em.opLoadBaseOffset(@intFromEnum(Instruction.OP_LDR) << 12 |
            @intFromEnum(Register.R_R1) << 9 |
            @intFromEnum(Register.R_R0) << 9 |
            10);
        try std.testing.expectEqual(100, em.register(.R_R1));
        try std.testing.expectEqual(@intFromEnum(Condition.FL_POS), em.register(.R_COND));
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
        self.registerPtr(dr).* = self.memRead(self.register(.R_PC) +% offset);
        self.updateConds(dr);
    }

    test "opLoad" {
        var em = try Emulator.initStd(std.testing.io, &.{}, &.{});
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
            self.registerPtr(.R_PC).* = self.register(.R_PC) +% offset;
        } else {
            const base: Register = @enumFromInt((instr >> 6) & BITMASK_REGISTER);
            self.registerPtr(.R_PC).* = self.register(base);
        }
    }

    test "opJumpSubroutine reg" {
        var em = try Emulator.initStd(std.testing.io, &.{}, &.{});
        em.registerPtr(.R_PC).* = 100;
        em.registerPtr(.R_R0).* = 1000;

        em.opJumpSubroutine(@intFromEnum(Instruction.OP_JSR) << 12 |
            @intFromEnum(Register.R_R0) << 6);

        try std.testing.expectEqual(100, em.register(.R_R7));
        try std.testing.expectEqual(1000, em.register(.R_PC));
    }

    test "opJumpSubroutine imm" {
        var em = try Emulator.initStd(std.testing.io, &.{}, &.{});
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
    // |    1100   |   000  |  BASE  |     000000      |
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
        var em = try Emulator.initStd(std.testing.io, &.{}, &.{});
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
        const addr = self.register(.R_PC) +% signExtend(instr & BITMASK_IMMVAL9, 9);
        self.reg[dr] = self.memRead(self.memRead(addr));
    }

    test "Load Indirect" {
        var em = try Emulator.initStd(std.testing.io, &.{}, &.{});
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
            self.registerPtr(dr).* = self.register(sr1) +% immVal;
        } else {
            const sr2: Register = @enumFromInt(instr & BITMASK_REGISTER);
            self.registerPtr(dr).* = self.register(sr1) +% self.register(sr2);
        }
        self.updateConds(dr);
    }

    test "opAdd reg" {
        var em = try Emulator.initStd(std.testing.io, &.{}, &.{});
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
        var em = try Emulator.initStd(std.testing.io, &.{}, &.{});
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
        var em = try Emulator.initStd(std.testing.io, &.{}, &.{});
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
        var em = try Emulator.initStd(std.testing.io, &.{}, &.{});
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
                self.registerPtr(.R_PC).* = self.register(.R_PC) +% pcOffset;
                return;
            }
        }
    }

    test "opBranch all" {
        var em = try Emulator.initStd(std.testing.io, &.{}, &.{});
        em.registerPtr(.R_COND).* = 0b111; // turn them all on
        em.opBranch(@intFromEnum(Instruction.OP_BR) << 12 |
            @intFromEnum(Condition.FL_NEG) << 9 |
            20);
        try std.testing.expectEqual(20, em.register(.R_PC));
    }

    test "opBranch n" {
        var em = try Emulator.initStd(std.testing.io, &.{}, &.{});
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
        var em = try Emulator.initStd(std.testing.io, &.{}, &.{});
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
        var em = try Emulator.initStd(std.testing.io, &.{}, &.{});
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
        if (addr == MR_KBSR) {
            if (checkKey()) {
                const char = self.in.takeByte() catch NULL;
                self.memPtr(MR_KBSR).* = (1 << 15);
                self.memPtr(MR_KBDR).* = char;
            } else {
                self.memPtr(MR_KBSR).* = NULL;
            }
        }

        return self.memory[addr];
    }

    pub fn memPtr(self: *Emulator, addr: u16) *u16 {
        return &self.memory[addr];
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
        if (val >> (bitCount - 1) > 0) {
            val |= @as(u16, 0xffff) << bitCount;
        }

        return val;
    }

    test "signExtend" {
        try std.testing.expectEqual(0b0000000000000001, signExtend(0b0001, 4));
        try std.testing.expectEqual(0b1111111111111001, signExtend(0b1001, 4));
        try std.testing.expectEqual(0b1111111111111111, signExtend(0b11, 2));
    }

    fn disableInputBuffering(self: *Emulator) !void {
        const posix = std.posix;
        self.origTerm = try posix.tcgetattr(posix.STDIN_FILENO);
        var newTerm: posix.termios = self.origTerm;
        newTerm.lflag.ECHO = false;
        newTerm.lflag.ICANON = false;
        try std.posix.tcsetattr(posix.STDIN_FILENO, posix.TCSA.NOW, newTerm);
    }

    fn restoreInputBuffering(self: *Emulator) !void {
        const posix = std.posix;
        try std.posix.tcsetattr(posix.STDIN_FILENO, posix.TCSA.NOW, self.origTerm);
    }

    fn checkKey() bool {
        const posix = std.posix;
        var fd = posix.pollfd{
            .fd = posix.STDIN_FILENO,
            .events = posix.POLL.IN,
            .revents = 0,
        };
        const fds: *[1]posix.pollfd = @ptrCast(&fd);

        // timeout = 0 → non-blocking (same as your timeval = {0,0})
        const n = posix.poll(fds, 0) catch 0;

        return n != 0 and (fd.revents & posix.POLL.IN) != 0;
    }
};
