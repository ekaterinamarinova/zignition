pub const CanId = enum(u16) {
    ECU = 0x10,      // Engine Control Unit
    TPMS = 0x20,     // Tire Pressure Monitoring System
    ABS = 0x30,      // Anti-lock Braking System
    AIRBAG = 0x40,   // Airbag System
    BODY_CONTROL = 0x50, // Body Control Module
    DIAGNOSTIC = 0x60,   // Diagnostic Tool

    pub fn toString(self: CanId) []const u8 {
        return switch (self) {
            .ECU => "ECU",
            .TPMS => "Tire Pressure Monitoring System",
            .ABS => "ABS",
            .AIRBAG => "Airbag",
            .BODY_CONTROL => "Body Control",
            .DIAGNOSTIC => "Diagnostic",
        };
    }
};
