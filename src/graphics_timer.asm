; Called on each elapsed wall-clock second. Carry means N*60 seconds elapsed.
GRAPHICS_TIMER_SECOND:
        LD      A, (GRAPHICS_SECONDS)
        INC     A
        CP      60
        JR      C, .SAVE_SECOND
        XOR     A
        LD      (GRAPHICS_SECONDS), A
        LD      HL, (GRAPHICS_MINUTES)
        INC     HL
        LD      (GRAPHICS_MINUTES), HL
        LD      DE, (GRAPHICS_INTERVAL)
        OR      A
        SBC     HL, DE
        JR      C, .NOT_DUE
        SCF
        RET
.SAVE_SECOND:
        LD      (GRAPHICS_SECONDS), A
.NOT_DUE:
        OR      A
        RET
