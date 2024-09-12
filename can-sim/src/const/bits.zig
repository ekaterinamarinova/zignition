pub const Bits = enum(u8) {
    ControlFieldLastBit,
    DataFieldFirstBit,
    CrcFieldLastBit,
    AckFieldLastBit,
    EOFLastBit,

    pub fn value(self: Bits) u8 {
        return switch (self) {
            .ControlFieldLastBit => 18,
            .DataFieldFirstBit => 19,
            .CrcFieldLastBit => 34,
            .AckFieldLastBit => 36,
            .EOFLastBit => 44,
        };
    }
};