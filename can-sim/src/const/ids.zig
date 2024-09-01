pub const CanId = enum(u16) {
    ECU = 0x100,      // Engine Control Unit
    TPMS = 0x200,     // Tire Pressure Monitoring System
    ABS = 0x300,      // Anti-lock Braking System
    AIRBAG = 0x400,   // Airbag System
    BODY_CONTROL = 0x500, // Body Control Module
    DIAGNOSTIC = 0x600,   // Diagnostic Tool

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
