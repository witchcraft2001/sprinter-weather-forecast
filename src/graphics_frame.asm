; Sample DSS time after each EI/HALT wakeup; draw and report NZ only after
; the wall-clock second changes. Extra keyboard IRQs cannot advance the timer
; again within the same RTC second. CF reports a drawing error.
GRAPHICS_FRAME_CLOCK:
        IFDEF   GRAPHICS_FRAME_TEST
        CALL    GRAPHICS_FRAME_TEST_SECOND
        ELSE
        LD      C, DSS_SYSTIME
        RST     DSS
        LD      A, B
        ENDIF
        LD      B, A
        LD      A, (GRAPHICS_LAST_SECOND)
        CP      B
        RET     Z
        LD      A, B
        LD      (GRAPHICS_LAST_SECOND), A
        CALL    GRAPHICS_DRAW_CLOCK
        RET     C
        OR      1
        RET
