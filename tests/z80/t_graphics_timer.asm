        DEVICE  NOSLOT64K
        ORG     0000h
        JP      START

        INCLUDE "harness.inc"

GRAPHICS_SECONDS  EQU 07000h
GRAPHICS_MINUTES  EQU GRAPHICS_SECONDS + 1
GRAPHICS_INTERVAL EQU GRAPHICS_MINUTES + 2

START:
        LD      SP, 0FF00h
        CALL    T_BEGIN
        LD      HL, 1
        CALL    TIMER_RESET
        LD      BC, 59
        CALL    TIMER_SECONDS
        LD      A, 1
        CALL    T_EXPECT_NC
        LD      HL, (GRAPHICS_MINUTES)
        LD      DE, 0
        OR      A
        SBC     HL, DE
        LD      A, 2
        CALL    T_EXPECT_Z
        LD      A, (GRAPHICS_SECONDS)
        CP      59
        LD      A, 3
        CALL    T_EXPECT_Z
        LD      BC, 1
        CALL    TIMER_SECONDS
        LD      A, 5
        CALL    T_EXPECT_C
        CALL    TEST_INTERVAL_FIVE
        CALL    TEST_INTERVAL_MAX
        CALL    TEST_INTERVAL_ONE_AGAIN
        CALL    T_END
        HALT

TEST_INTERVAL_FIVE:
        LD      HL, 5
        CALL    TIMER_RESET
        LD      BC, 299
        CALL    TIMER_SECONDS
        LD      A, 6
        CALL    T_EXPECT_NC
        LD      HL, (GRAPHICS_MINUTES)
        LD      DE, 4
        OR      A
        SBC     HL, DE
        LD      A, 7
        CALL    T_EXPECT_Z
        LD      A, (GRAPHICS_SECONDS)
        CP      59
        LD      A, 8
        CALL    T_EXPECT_Z
        LD      BC, 1
        CALL    TIMER_SECONDS
        LD      A, 9
        CALL    T_EXPECT_C
        RET

TEST_INTERVAL_MAX:
        LD      HL, 1440
        CALL    TIMER_RESET
        LD      HL, 1439
        LD      (GRAPHICS_MINUTES), HL
        LD      A, 59
        LD      (GRAPHICS_SECONDS), A
        LD      BC, 1
        CALL    TIMER_SECONDS
        LD      A, 11
        JP      T_EXPECT_C

TEST_INTERVAL_ONE_AGAIN:
        LD      HL, 1
        CALL    TIMER_RESET
        LD      BC, 59
        CALL    TIMER_SECONDS
        LD      A, 12
        CALL    T_EXPECT_NC
        LD      BC, 1
        CALL    TIMER_SECONDS
        LD      A, 13
        JP      T_EXPECT_C

; HL=minutes, reset elapsed time, then call once per elapsed wall-clock second.
TIMER_RESET:
        LD      (GRAPHICS_INTERVAL), HL
        XOR     A
        LD      (GRAPHICS_SECONDS), A
        LD      (GRAPHICS_MINUTES), A
        LD      (GRAPHICS_MINUTES + 1), A
        RET

; BC=elapsed-second pulses. Carry returns as soon as the interval expires.
TIMER_SECONDS:
.LOOP:  CALL    GRAPHICS_TIMER_SECOND
        RET     C
        DEC     BC
        LD      A, B
        OR      C
        JR      NZ, .LOOP
        OR      A
        RET

        INCLUDE "graphics_timer.asm"
