; Minimal result protocol read by tools/run_z80_tests.sh.
TEST_RESULT     EQU     0E000h
TEST_DONE       EQU     0E001h
TEST_FIRST      EQU     0E002h
TEST_FAILS      EQU     0E003h
DONE_MAGIC      EQU     0A5h

T_BEGIN:
        XOR     A
        LD      (TEST_RESULT), A
        LD      (TEST_DONE), A
        LD      (TEST_FIRST), A
        LD      (TEST_FAILS), A
        RET
T_END:
        LD      A, DONE_MAGIC
        LD      (TEST_DONE), A
        RET
T_FAIL:
        PUSH    AF
        LD      A, 1
        LD      (TEST_RESULT), A
        LD      A, (TEST_FAILS)
        INC     A
        LD      (TEST_FAILS), A
        LD      A, (TEST_FIRST)
        OR      A
        JR      NZ, .DONE
        POP     AF
        LD      (TEST_FIRST), A
        RET
.DONE:
        POP     AF
        RET
T_EXPECT_NC:
        RET     NC
        JR      T_FAIL
T_EXPECT_C:
        RET     C
        JR      T_FAIL
T_EXPECT_Z:
        RET     Z
        JR      T_FAIL
T_EXPECT_NZ:
        RET     NZ
        JR      T_FAIL
