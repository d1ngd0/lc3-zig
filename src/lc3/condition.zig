// The COND register stores condition flags which provide information about the most recently executed calculation. This allows programs to check logical conditions such as if (x > 0) { ... }.
// Each CPU has a variety of condition flags to signal various situations. The LC-3 uses only 3 condition flags which indicate the sign of the previous calculation.
pub const Condition = enum(u3) {
    UNSET = 0,
    POS = 1 << 0, // P
    ZRO = 1 << 1, // Z
    NEG = 1 << 2, // N
};
