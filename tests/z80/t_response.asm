        DEVICE  NOSLOT64K
        ORG     0
        JP      START

        INCLUDE "harness.inc"

; Real production transport is included below. These definitions provide the
; application storage and the otherwise unused UNET-facing symbols.
RESP_CONTINUE           EQU 0
RESP_COMPLETE           EQU 1
RESPONSE_BUFFER         EQU 08000h
RESPONSE_MAX            EQU 0100h
RESPONSE_SIZE           EQU RESPONSE_BUFFER + RESPONSE_MAX + 1
RESPONSE_LINE_START     EQU RESPONSE_SIZE + 2
RESPONSE_DONE           EQU RESPONSE_LINE_START + 1
RESPONSE_TERM_STATE     EQU RESPONSE_DONE + 1
TRANSPORT_STAGE         EQU RESPONSE_TERM_STATE + 1
TRANSPORT_CODE          EQU TRANSPORT_STAGE + 1
TRANSPORT_HAS_DETAIL    EQU TRANSPORT_CODE + 1
TRANSPORT_DETAIL_STATUS EQU TRANSPORT_HAS_DETAIL + 1
TRANSPORT_DETAIL        EQU TRANSPORT_DETAIL_STATUS + 1
TRANSPORT_DETAIL_SIZE   EQU 32
LAST_RECV_LENGTH        EQU TRANSPORT_DETAIL + TRANSPORT_DETAIL_SIZE
TRANSPORT_RESPONSE_SIZE EQU LAST_RECV_LENGTH + 2
TRANSPORT_IDLE_COUNT    EQU TRANSPORT_RESPONSE_SIZE + 2
CFG_HOST                EQU 08200h
CFG_PORT                EQU 08280h
CFG_SELECTOR            EQU 08290h
CFG_LOCATION            EQU 08300h
REQUEST_BUFFER          EQU 08400h
REQUEST_SIZE            EQU REQUEST_BUFFER + 193
REQUEST_MAX             EQU 192
RECV_BUFFER             EQU 08600h
RECV_BUFFER_SIZE        EQU 512
STATE_FLAGS             EQU 08800h
FLAG_CHANNEL_OPEN       EQU 4
UNET_FN_CONNECT         EQU 5
UNET_FN_SEND            EQU 6
UNET_FN_RECV            EQU 7
UNET_FN_LASTERR         EQU 16
NERR_OK                 EQU 0
NERR_CLOSED             EQU 7
NERR_CANCEL             EQU 8

START:
        CALL    T_BEGIN
        CALL    TEST_WHOLE_RESPONSE
        CALL    TEST_TERMINATOR_BYTEWISE
        CALL    TEST_TERMINATOR_SPLIT_AFTER_CR
        CALL    TEST_FALSE_TERMINATORS
        CALL    TEST_BUFFER_LIMIT
        CALL    T_END
        HALT

TEST_WHOLE_RESPONSE:
        CALL    RESET_RESPONSE
        LD      HL, FIXTURE
        LD      BC, FIXTURE_END - FIXTURE
        CALL    MAIN.RESPONSE_FEED
        LD      A, 1
        CALL    T_EXPECT_NC
        CP      RESP_COMPLETE
        LD      A, 2
        CALL    T_EXPECT_Z
        LD      A, (RESPONSE_DONE)
        CP      1
        LD      A, 3
        CALL    T_EXPECT_Z
        LD      HL, (RESPONSE_SIZE)
        LD      DE, FIXTURE_END - FIXTURE
        OR      A
        SBC     HL, DE
        LD      A, 4
        CALL    T_EXPECT_Z
        RET

TEST_TERMINATOR_BYTEWISE:
        CALL    RESET_RESPONSE
        LD      HL, PREFIX
        LD      BC, PREFIX_END - PREFIX
        CALL    MAIN.RESPONSE_FEED
        CP      RESP_CONTINUE
        LD      A, 10
        CALL    T_EXPECT_Z
        LD      HL, DOT
        LD      BC, 1
        CALL    MAIN.RESPONSE_FEED
        CP      RESP_CONTINUE
        LD      A, 11
        CALL    T_EXPECT_Z
        LD      HL, CR
        LD      BC, 1
        CALL    MAIN.RESPONSE_FEED
        CP      RESP_CONTINUE
        LD      A, 12
        CALL    T_EXPECT_Z
        LD      HL, LF
        LD      BC, 1
        CALL    MAIN.RESPONSE_FEED
        CP      RESP_COMPLETE
        LD      A, 13
        CALL    T_EXPECT_Z
        RET

TEST_TERMINATOR_SPLIT_AFTER_CR:
        CALL    RESET_RESPONSE
        LD      HL, PREFIX_DOT_CR
        LD      BC, PREFIX_DOT_CR_END - PREFIX_DOT_CR
        CALL    MAIN.RESPONSE_FEED
        CP      RESP_CONTINUE
        LD      A, 20
        CALL    T_EXPECT_Z
        LD      HL, LF
        LD      BC, 1
        CALL    MAIN.RESPONSE_FEED
        CP      RESP_COMPLETE
        LD      A, 21
        CALL    T_EXPECT_Z
        RET

TEST_FALSE_TERMINATORS:
        CALL    RESET_RESPONSE
        LD      HL, FALSE_TERMS
        LD      BC, FALSE_TERMS_END - FALSE_TERMS
        CALL    MAIN.RESPONSE_FEED
        CP      RESP_CONTINUE
        LD      A, 30
        CALL    T_EXPECT_Z
        LD      HL, DOT_CRLF
        LD      BC, DOT_CRLF_END - DOT_CRLF
        CALL    MAIN.RESPONSE_FEED
        CP      RESP_COMPLETE
        LD      A, 31
        CALL    T_EXPECT_Z
        RET

TEST_BUFFER_LIMIT:
        CALL    RESET_RESPONSE
        LD      HL, OVERFLOW_INPUT
        LD      BC, 257
        CALL    MAIN.RESPONSE_FEED
        LD      A, 40
        CALL    T_EXPECT_C
        LD      HL, (RESPONSE_SIZE)
        LD      DE, RESPONSE_MAX
        OR      A
        SBC     HL, DE
        LD      A, 41
        CALL    T_EXPECT_Z
        RET

RESET_RESPONSE:
        CALL    MAIN.TRANSPORT_RESET
        LD      HL, (RESPONSE_SIZE)
        LD      DE, 0
        OR      A
        SBC     HL, DE
        LD      A, 50
        CALL    T_EXPECT_Z
        LD      HL, (LAST_RECV_LENGTH)
        LD      DE, 0
        OR      A
        SBC     HL, DE
        LD      A, 51
        CALL    T_EXPECT_Z
        LD      A, (TRANSPORT_IDLE_COUNT)
        OR      A
        LD      A, 52
        CALL    T_EXPECT_Z
        LD      A, (TRANSPORT_DETAIL_STATUS)
        CP      0FFh
        LD      A, 53
        CALL    T_EXPECT_Z
        RET

; Never called by these tests; required because the included production
; transport also assembles its Gopher/UNET entry points.
CALL_UNET:
        XOR     A
        RET

        MODULE  MAIN
        INCLUDE "transport.asm"
        ENDMODULE

PREFIX:                 DB "WX1|OK|1",13,10
PREFIX_END:
DOT:                    DB '.'
CR:                     DB 13
LF:                     DB 10
PREFIX_DOT_CR:          DB "WX1|OK|1",13,10,'.',13
PREFIX_DOT_CR_END:
DOT_CRLF:               DB '.',13,10
DOT_CRLF_END:
FALSE_TERMS:            DB "X.\nY.\rX",13,10
FALSE_TERMS_END:
FIXTURE:                DB "WX1|OK|1",13,10,"D|today",13,10,'.',13,10
FIXTURE_END:
OVERFLOW_INPUT:         DS 257, 'A'
