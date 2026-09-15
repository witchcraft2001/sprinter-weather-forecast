        DEVICE  NOSLOT64K
        DEFINE  GRAPHICS_FRAME_TEST
        ORG     0000h
        JP      START

        INCLUDE "harness.inc"

CLOCK_BUFFER EQU 07000h
CLOCK_DRAWS  EQU 07021h
CLOCK_SECONDS EQU 07022h
GRAPHICS_LAST_SECOND EQU 07023h
GRAPHICS_SECONDS EQU 07024h
GRAPHICS_MINUTES EQU 07025h
GRAPHICS_INTERVAL EQU 07027h
MINUTE_PULSES EQU 07029h

START:
        LD      SP, 0FF00h
        CALL    T_BEGIN
        LD      HL, 0000h
        LD      B, 0
        CALL    FORMAT_CLOCK
        LD      HL, CLOCK_BUFFER
        LD      DE, EXPECT_000000
        CALL    CLOCK_STREQ
        LD      A, 1
        CALL    T_EXPECT_Z
        LD      HL, 0908h
        LD      B, 7
        CALL    FORMAT_CLOCK
        LD      HL, CLOCK_BUFFER
        LD      DE, EXPECT_090807
        CALL    CLOCK_STREQ
        LD      A, 2
        CALL    T_EXPECT_Z
        LD      HL, 173Bh
        LD      B, 59
        CALL    FORMAT_CLOCK
        LD      HL, CLOCK_BUFFER
        LD      DE, EXPECT_235959
        CALL    CLOCK_STREQ
        LD      A, 3
        CALL    T_EXPECT_Z
        LD      HL, 0B0Bh
        LD      B, 11
        CALL    FORMAT_CLOCK
        LD      HL, CLOCK_BUFFER
        LD      DE, EXPECT_111111
        CALL    CLOCK_STREQ
        LD      A, 4
        CALL    T_EXPECT_Z
        CALL    TEST_SECOND_GATE
        CALL    TEST_MINUTE_REFRESH
        CALL    T_END
        HALT

; H=hour, L=minute, B=second; this follows the production DSS formatter.
FORMAT_CLOCK:
        PUSH    BC
        LD      DE, CLOCK_BUFFER
        LD      A, H
        CALL    GRAPHICS_CLOCK_2D
        LD      A, ':'
        LD      (DE), A
        INC     DE
        LD      A, L
        CALL    GRAPHICS_CLOCK_2D
        POP     BC
        LD      A, ':'
        LD      (DE), A
        INC     DE
        LD      A, B
        CALL    GRAPHICS_CLOCK_2D
        XOR     A
        LD      (DE), A
        RET

CLOCK_STREQ:
.LOOP:  LD      A, (DE)
        CP      (HL)
        RET     NZ
        OR      A
        RET     Z
        INC     HL
        INC     DE
        JR      .LOOP

TEST_SECOND_GATE:
        XOR     A
        LD      (CLOCK_DRAWS), A
        LD      A, 10
        LD      (CLOCK_SECONDS), A
        LD      (GRAPHICS_LAST_SECOND), A
        CALL    GRAPHICS_FRAME_CLOCK
        LD      A, 5
        CALL    T_EXPECT_Z
        CALL    GRAPHICS_FRAME_CLOCK
        LD      A, 5
        CALL    T_EXPECT_Z
        LD      A, (CLOCK_DRAWS)
        OR      A
        LD      A, 6
        CALL    T_EXPECT_Z
        CALL    GRAPHICS_FRAME_CLOCK
        LD      A, 7
        CALL    T_EXPECT_Z
        LD      A, (CLOCK_DRAWS)
        CP      1
        LD      A, 8
        CALL    T_EXPECT_NZ
        LD      A, 11
        LD      (CLOCK_SECONDS), A
        CALL    GRAPHICS_FRAME_CLOCK
        LD      A, 9
        CALL    T_EXPECT_NZ
        LD      A, (CLOCK_DRAWS)
        CP      1
        LD      A, 10
        CALL    T_EXPECT_Z
        LD      A, (GRAPHICS_LAST_SECOND)
        CP      11
        LD      A, 11
        CALL    T_EXPECT_Z
        CALL    GRAPHICS_FRAME_CLOCK
        LD      A, 12
        CALL    T_EXPECT_Z
        LD      A, (CLOCK_DRAWS)
        CP      1
        LD      A, 13
        JP      T_EXPECT_Z

; Exercise the production integration: each observed DSS second feeds the
; minute timer once, including the 59 -> 00 wrap, and WEATHER 1 expires on the
; sixtieth pulse.
TEST_MINUTE_REFRESH:
        XOR     A
        LD      (CLOCK_SECONDS), A
        LD      (GRAPHICS_LAST_SECOND), A
        LD      (GRAPHICS_SECONDS), A
        LD      (GRAPHICS_MINUTES), A
        LD      (GRAPHICS_MINUTES + 1), A
        LD      HL, 1
        LD      (GRAPHICS_INTERVAL), HL
        LD      A, 60
        LD      (MINUTE_PULSES), A
.SECOND:
        LD      A, (CLOCK_SECONDS)
        INC     A
        CP      60
        JR      C, .STORE
        XOR     A
.STORE: LD      (CLOCK_SECONDS), A
        CALL    GRAPHICS_FRAME_CLOCK
        LD      A, 14
        CALL    T_EXPECT_NZ
        CALL    GRAPHICS_TIMER_SECOND
        PUSH    AF
        LD      A, (MINUTE_PULSES)
        DEC     A
        LD      (MINUTE_PULSES), A
        JR      Z, .DUE
        POP     AF
        LD      A, 15
        CALL    T_EXPECT_NC
        JR      .SECOND
.DUE:  POP     AF
        LD      A, 16
        JP      T_EXPECT_C

GRAPHICS_DRAW_CLOCK:
        LD      A, (CLOCK_DRAWS)
        INC     A
        LD      (CLOCK_DRAWS), A
        XOR     A
        RET

GRAPHICS_FRAME_TEST_SECOND:
        LD      A, (CLOCK_SECONDS)
        RET

        INCLUDE "graphics_frame.asm"
        INCLUDE "graphics_timer.asm"
        INCLUDE "graphics_clock.asm"

EXPECT_000000: DB "00:00:00", 0
EXPECT_090807: DB "09:08:07", 0
EXPECT_235959: DB "23:59:59", 0
EXPECT_111111:
        DB      "1",0FFh,0FFh,"1",0FFh,0FFh,":"
        DB      "1",0FFh,0FFh,"1",0FFh,0FFh,":"
        DB      "1",0FFh,0FFh,"1",0FFh,0FFh,0
