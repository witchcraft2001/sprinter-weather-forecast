        DEVICE  NOSLOT64K
        ORG     0000h
        JP      START

        INCLUDE "harness.inc"

L_DIGITS EQU 07000h

START:
        LD      SP, 0FF00h
        CALL    T_BEGIN
        LD      IX, 08003h               ; current Estex-DSS layout
        CALL    TEST_SUITE
        XOR     A
        LD      (08003h), A              ; classic DSS leaves this PSP byte zero
        LD      IX, 08080h               ; classic DSS passes this pointer
        CALL    TEST_SUITE
        CALL    T_END
        HALT

TEST_SUITE:
        CALL    TEST_DEFAULT
        CALL    TEST_ONE
        CALL    TEST_FIVE
        CALL    TEST_MAX
        CALL    TEST_SPACES
        CALL    TEST_ONLY_SPACES
        CALL    TEST_ZERO
        CALL    TEST_SIGN
        CALL    TEST_MINUS
        CALL    TEST_ALPHA
        CALL    TEST_SECOND
        CALL    TEST_ABOVE_MAX
        CALL    TEST_TOO_LONG
        RET

TEST_DEFAULT:
        LD      HL, ARG_DEFAULT
        LD      B, ARG_DEFAULT_END - ARG_DEFAULT
        CALL    RUN_PARSE
        LD      DE, 5
        JR      CHECK_VALID
TEST_ONE:
        LD      HL, ARG_ONE
        LD      B, ARG_ONE_END - ARG_ONE
        CALL    RUN_PARSE
        LD      DE, 1
        JR      CHECK_VALID
TEST_FIVE:
        LD      HL, ARG_FIVE
        LD      B, ARG_FIVE_END - ARG_FIVE
        CALL    RUN_PARSE
        LD      DE, 5
        JR      CHECK_VALID
TEST_MAX:
        LD      HL, ARG_MAX
        LD      B, ARG_MAX_END - ARG_MAX
        CALL    RUN_PARSE
        LD      DE, 1440
        JR      CHECK_VALID
TEST_SPACES:
        LD      HL, ARG_SPACES
        LD      B, ARG_SPACES_END - ARG_SPACES
        CALL    RUN_PARSE
        LD      DE, 5
CHECK_VALID:
        LD      A, 1
        CALL    T_EXPECT_NC
        OR      A
        SBC     HL, DE
        LD      A, 2
        CALL    T_EXPECT_Z
        RET

TEST_ZERO:
        LD      HL, ARG_ZERO
        LD      B, ARG_ZERO_END - ARG_ZERO
        CALL    RUN_PARSE
        LD      A, 3
        JP      T_EXPECT_C
TEST_ONLY_SPACES:
        LD      HL, ARG_ONLY_SPACES
        LD      B, ARG_ONLY_SPACES_END - ARG_ONLY_SPACES
        CALL    RUN_PARSE
        LD      DE, 5
        JR      CHECK_VALID
TEST_SIGN:
        LD      HL, ARG_SIGN
        LD      B, ARG_SIGN_END - ARG_SIGN
        CALL    RUN_PARSE
        LD      A, 4
        JP      T_EXPECT_C
TEST_MINUS:
        LD      HL, ARG_MINUS
        LD      B, ARG_MINUS_END - ARG_MINUS
        CALL    RUN_PARSE
        LD      A, 14
        JP      T_EXPECT_C
TEST_ALPHA:
        LD      HL, ARG_ALPHA
        LD      B, ARG_ALPHA_END - ARG_ALPHA
        CALL    RUN_PARSE
        LD      A, 5
        JP      T_EXPECT_C
TEST_SECOND:
        LD      HL, ARG_SECOND
        LD      B, ARG_SECOND_END - ARG_SECOND
        CALL    RUN_PARSE
        LD      A, 6
        JP      T_EXPECT_C
TEST_ABOVE_MAX:
        LD      HL, ARG_ABOVE_MAX
        LD      B, ARG_ABOVE_MAX_END - ARG_ABOVE_MAX
        CALL    RUN_PARSE
        LD      A, 7
        JP      T_EXPECT_C
TEST_TOO_LONG:
        LD      HL, ARG_TOO_LONG
        LD      B, ARG_TOO_LONG_END - ARG_TOO_LONG
        CALL    RUN_PARSE
        LD      A, 8
        JP      T_EXPECT_C

RUN_PARSE:
        PUSH    IX
        POP     DE
        LD      C, B
        LD      B, 0
        LDIR
        JP      L_PARSE_INTERVAL

        INCLUDE "interval.asm"

ARG_DEFAULT:   DB 0
ARG_DEFAULT_END:
ARG_ONE:       DB 1, "1"
ARG_ONE_END:
ARG_FIVE:      DB 1, "5"
ARG_FIVE_END:
ARG_MAX:       DB 4, "1440"
ARG_MAX_END:
ARG_SPACES:    DB 3, " 5 "
ARG_SPACES_END:
ARG_ONLY_SPACES: DB 3, "   "
ARG_ONLY_SPACES_END:
ARG_ZERO:      DB 1, "0"
ARG_ZERO_END:
ARG_SIGN:      DB 2, "+", "1"
ARG_SIGN_END:
ARG_MINUS:     DB 2, "-", "1"
ARG_MINUS_END:
ARG_ALPHA:     DB 1, "x"
ARG_ALPHA_END:
ARG_SECOND:    DB 3, "5 1"
ARG_SECOND_END:
ARG_ABOVE_MAX: DB 4, "1441"
ARG_ABOVE_MAX_END:
ARG_TOO_LONG:  DB 5, "10000"
ARG_TOO_LONG_END:
