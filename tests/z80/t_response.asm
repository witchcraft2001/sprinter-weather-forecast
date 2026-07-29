        DEVICE  NOSLOT64K
        ORG     0
        JP      START

        INCLUDE "harness.inc"

; Production transport/parser storage, deliberately isolated from test code.
RESP_CONTINUE           EQU 0
RESP_COMPLETE           EQU 1
RESPONSE_MAX            EQU 0200h
RESPONSE_SIZE           EQU 08000h
RESPONSE_TAIL           EQU RESPONSE_SIZE + 2
TRANSPORT_INPUT_PTR     EQU RESPONSE_TAIL + 4
TRANSPORT_INPUT_SIZE    EQU TRANSPORT_INPUT_PTR + 2
TRANSPORT_STAGE         EQU TRANSPORT_INPUT_SIZE + 2
TRANSPORT_CODE          EQU TRANSPORT_STAGE + 1
TRANSPORT_RESPONSE_ERROR EQU TRANSPORT_CODE + 1
TRANSPORT_HAS_DETAIL    EQU TRANSPORT_RESPONSE_ERROR + 1
TRANSPORT_DETAIL_STATUS EQU TRANSPORT_HAS_DETAIL + 1
TRANSPORT_DETAIL        EQU TRANSPORT_DETAIL_STATUS + 1
TRANSPORT_DETAIL_SIZE   EQU 32
LAST_RECV_LENGTH        EQU TRANSPORT_DETAIL + TRANSPORT_DETAIL_SIZE
TRANSPORT_RESPONSE_SIZE EQU LAST_RECV_LENGTH + 2
WX1_LINE_BUFFER         EQU 08200h
WX1_LINE_LEN            EQU WX1_LINE_BUFFER + 160
WX1_STATE               EQU WX1_LINE_LEN + 1
WX1_LINE_COUNT          EQU WX1_STATE + 1
WX1_EOL_MODE            EQU WX1_LINE_COUNT + 1
WX1_PENDING_CR          EQU WX1_EOL_MODE + 1
WX1_RESULT              EQU WX1_PENDING_CR + 1
WX1_ERROR_CODE          EQU WX1_RESULT + 1
WX1_ERROR_LINE          EQU WX1_ERROR_CODE + 1
WX1_DAYS_LEFT           EQU WX1_ERROR_LINE + 1
WX1_FIELD_COUNT         EQU WX1_DAYS_LEFT + 1
WX1_FIELD_PTRS          EQU WX1_FIELD_COUNT + 1
WX1_NEXT_DAY_PTR        EQU WX1_FIELD_PTRS + 16
WX1_SERVICE_CODE        EQU WX1_NEXT_DAY_PTR + 2
WX1_SERVICE_CODE_SIZE   EQU 33
WX1_COPY_LEFT           EQU WX1_SERVICE_CODE + WX1_SERVICE_CODE_SIZE
WX1_INPUT_BYTE          EQU WX1_COPY_LEFT + 1
WX1_EOL_CANDIDATE       EQU WX1_INPUT_BYTE + 1
WX1_DIGIT               EQU WX1_EOL_CANDIDATE + 1
WX1_DIGITS              EQU WX1_DIGIT + 1
WX1_TMP16               EQU WX1_DIGITS + 1
WX1_DATE_MONTH          EQU WX1_TMP16 + 2
WX1_DATE_DAY            EQU WX1_DATE_MONTH + 1
WX1_DATE_YEAR           EQU WX1_DATE_DAY + 1
WX1_STAGE_MODEL         EQU 08400h
WX1_MODEL               EQU WX1_STAGE_MODEL + 300
CFG_HOST                EQU 09000h
CFG_PORT                EQU 09080h
CFG_SELECTOR            EQU 09090h
CFG_LOCATION            EQU 09100h
REQUEST_BUFFER          EQU 09200h
REQUEST_SIZE            EQU REQUEST_BUFFER + 193
REQUEST_MAX             EQU 192
RECV_BUFFER             EQU 09400h
RECV_BUFFER_SIZE        EQU 512
STATE_FLAGS             EQU 09700h
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
        CALL    TEST_NUMBERS
        CALL    TEST_WHOLE_RESPONSE
        CALL    TEST_SEVEN_DAY_BYTEWISE
        CALL    TEST_SERVICE_ERROR
        CALL    TEST_TERMINATOR_BYTEWISE
        CALL    TEST_CR_RESPONSE
        CALL    TEST_LF_RESPONSE
        CALL    TEST_MIXED_ENDINGS
        CALL    TEST_CR_TRAILING
        CALL    TEST_DIRECTION_LIMITS
        CALL    TEST_INVALID_FIELDS
        CALL    TEST_PARSER_LIMITS
        CALL    TEST_BUFFER_LIMIT
        CALL    T_END
        HALT

TEST_NUMBERS:
        LD      HL, NUMBER_164
        CALL    MAIN.WX1_PARSE_S16
        LD      A, 70
        CALL    T_EXPECT_NC
        LD      HL, DE
        LD      DE, 164
        OR      A
        SBC     HL, DE
        LD      A, 71
        CALL    T_EXPECT_Z
        LD      HL, NUMBER_MIN
        CALL    MAIN.WX1_PARSE_S16
        LD      A, 72
        CALL    T_EXPECT_NC
        LD      HL, DE
        LD      DE, 08000h
        OR      A
        SBC     HL, DE
        LD      A, 73
        CALL    T_EXPECT_Z
        LD      HL, NUMBER_OVERFLOW
        CALL    MAIN.WX1_PARSE_S16
        LD      A, 74
        CALL    T_EXPECT_C
        RET

TEST_WHOLE_RESPONSE:
        CALL    RESET_RESPONSE
        LD      HL, FIXTURE_CRLF
        LD      BC, FIXTURE_CRLF_END - FIXTURE_CRLF
        CALL    MAIN.RESPONSE_FEED
        LD      A, 1
        CALL    T_EXPECT_NC
        CP      RESP_COMPLETE
        LD      A, 2
        CALL    T_EXPECT_Z
        LD      A, (WX1_RESULT)
        CP      MAIN.WX1_OK
        LD      A, 3
        CALL    T_EXPECT_Z
        LD      A, (WX1_MODEL)
        CP      1
        LD      A, 4
        CALL    T_EXPECT_Z
        LD      HL, (RESPONSE_SIZE)
        LD      DE, FIXTURE_CRLF_END - FIXTURE_CRLF
        OR      A
        SBC     HL, DE
        LD      A, 5
        CALL    T_EXPECT_Z
        RET

TEST_SEVEN_DAY_BYTEWISE:
        CALL    RESET_RESPONSE
        LD      HL, FIXTURE_7
.LOOP:
        PUSH    HL
        LD      BC, 1
        CALL    MAIN.RESPONSE_FEED
        LD      A, 80
        CALL    T_EXPECT_NC
        POP     HL
        INC     HL
        PUSH    HL
        LD      DE, FIXTURE_7_END
        OR      A
        SBC     HL, DE
        POP     HL
        JR      NZ, .LOOP
        LD      A, (WX1_RESULT)
        CP      MAIN.WX1_OK
        LD      A, 81
        CALL    T_EXPECT_Z
        LD      A, (WX1_MODEL + 199)
        CP      7
        LD      A, 82
        CALL    T_EXPECT_Z
        LD      A, (WX1_MODEL + 1)
        CP      08Ch
        LD      A, 83
        CALL    T_EXPECT_Z
        LD      HL, (WX1_MODEL + 232)
        LD      DE, 0FFF3h
        OR      A
        SBC     HL, DE
        LD      A, 84
        CALL    T_EXPECT_Z
        RET

TEST_SERVICE_ERROR:
        CALL    RESET_RESPONSE
        LD      HL, FIXTURE_SERVICE_ERROR
        LD      BC, FIXTURE_SERVICE_ERROR_END - FIXTURE_SERVICE_ERROR
        CALL    MAIN.RESPONSE_FEED
        PUSH    AF
        LD      A, 90
        CALL    T_EXPECT_NC
        POP     AF
        CP      RESP_COMPLETE
        LD      A, 91
        CALL    T_EXPECT_Z
        LD      A, (WX1_RESULT)
        CP      MAIN.WX1_SERVICE_ERROR
        LD      A, 92
        CALL    T_EXPECT_Z
        LD      HL, WX1_SERVICE_CODE
        LD      DE, SERVICE_GEO
        CALL    MAIN.WX1_STREQ
        LD      A, 93
        CALL    T_EXPECT_Z
        RET

TEST_TERMINATOR_BYTEWISE:
        CALL    RESET_RESPONSE
        LD      HL, PREFIX_CRLF
        LD      BC, PREFIX_CRLF_END - PREFIX_CRLF
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

TEST_CR_RESPONSE:
        CALL    RESET_RESPONSE
        LD      HL, FIXTURE_CR
        LD      BC, FIXTURE_CR_END - FIXTURE_CR
        CALL    MAIN.RESPONSE_FEED
        CP      RESP_CONTINUE
        LD      A, 20
        CALL    T_EXPECT_Z
        CALL    MAIN.RESPONSE_EOF
        LD      A, 21
        CALL    T_EXPECT_NC
        LD      A, (WX1_RESULT)
        CP      MAIN.WX1_OK
        LD      A, 22
        CALL    T_EXPECT_Z
        RET

TEST_LF_RESPONSE:
        CALL    RESET_RESPONSE
        LD      HL, FIXTURE_LF
        LD      BC, FIXTURE_LF_END - FIXTURE_LF
        CALL    MAIN.RESPONSE_FEED
        CP      RESP_COMPLETE
        LD      A, 30
        CALL    T_EXPECT_Z
        LD      A, (WX1_RESULT)
        CP      MAIN.WX1_OK
        LD      A, 31
        CALL    T_EXPECT_Z
        RET

TEST_MIXED_ENDINGS:
        CALL    RESET_RESPONSE
        LD      HL, FIXTURE_MIXED
        LD      BC, FIXTURE_MIXED_END - FIXTURE_MIXED
        CALL    MAIN.RESPONSE_FEED
        LD      A, 40
        CALL    T_EXPECT_C
        LD      A, (WX1_ERROR_CODE)
        CP      MAIN.WXE_LINE_ENDING
        LD      A, 41
        CALL    T_EXPECT_Z
        RET

TEST_CR_TRAILING:
        CALL    RESET_RESPONSE
        LD      HL, FIXTURE_CR_TRAILING
        LD      BC, FIXTURE_CR_TRAILING_END - FIXTURE_CR_TRAILING
        CALL    MAIN.RESPONSE_FEED
        LD      A, 42
        CALL    T_EXPECT_C
        LD      A, (WX1_ERROR_CODE)
        CP      MAIN.WXE_TRAILING
        LD      A, 43
        CALL    T_EXPECT_Z
        LD      A, (TRANSPORT_RESPONSE_ERROR)
        CP      MAIN.TRESP_PARSER
        LD      A, 44
        CALL    T_EXPECT_Z
        RET

TEST_DIRECTION_LIMITS:
        CALL    RESET_RESPONSE
        LD      HL, FIXTURE_DIRECTION_360
        LD      BC, FIXTURE_DIRECTION_360_END - FIXTURE_DIRECTION_360
        CALL    MAIN.RESPONSE_FEED
        LD      A, 100
        CALL    T_EXPECT_NC
        LD      A, (WX1_RESULT)
        CP      MAIN.WX1_OK
        LD      A, 101
        CALL    T_EXPECT_Z
        LD      HL, (WX1_MODEL + 214)
        LD      DE, 360
        OR      A
        SBC     HL, DE
        LD      A, 102
        CALL    T_EXPECT_Z

        CALL    RESET_RESPONSE
        LD      HL, FIXTURE_DIRECTION_361
        LD      BC, FIXTURE_DIRECTION_361_END - FIXTURE_DIRECTION_361
        CALL    MAIN.RESPONSE_FEED
        LD      A, 103
        CALL    T_EXPECT_C
        LD      A, (WX1_ERROR_CODE)
        CP      MAIN.WXE_RANGE
        LD      A, 104
        CALL    T_EXPECT_Z
        LD      A, (TRANSPORT_RESPONSE_ERROR)
        CP      MAIN.TRESP_PARSER
        LD      A, 105
        CALL    T_EXPECT_Z
        RET

TEST_INVALID_FIELDS:
        CALL    RESET_RESPONSE
        LD      HL, FIXTURE_HUMIDITY_101
        LD      BC, FIXTURE_HUMIDITY_101_END - FIXTURE_HUMIDITY_101
        CALL    MAIN.RESPONSE_FEED
        LD      A, 110
        CALL    T_EXPECT_C
        LD      A, (WX1_ERROR_CODE)
        CP      MAIN.WXE_RANGE
        LD      A, 111
        CALL    T_EXPECT_Z

        CALL    RESET_RESPONSE
        LD      HL, FIXTURE_DATE_NONLEAP
        LD      BC, FIXTURE_DATE_NONLEAP_END - FIXTURE_DATE_NONLEAP
        CALL    MAIN.RESPONSE_FEED
        LD      A, 112
        CALL    T_EXPECT_C
        LD      A, (WX1_ERROR_CODE)
        CP      MAIN.WXE_DATE_TIME
        LD      A, 113
        CALL    T_EXPECT_Z

        CALL    RESET_RESPONSE
        LD      HL, FIXTURE_DATE_FEB30
        LD      BC, FIXTURE_DATE_FEB30_END - FIXTURE_DATE_FEB30
        CALL    MAIN.RESPONSE_FEED
        LD      A, 114
        CALL    T_EXPECT_C
        LD      A, (WX1_ERROR_CODE)
        CP      MAIN.WXE_DATE_TIME
        LD      A, 115
        CALL    T_EXPECT_Z

        CALL    RESET_RESPONSE
        LD      HL, FIXTURE_CONTROL_TEXT
        LD      BC, FIXTURE_CONTROL_TEXT_END - FIXTURE_CONTROL_TEXT
        CALL    MAIN.RESPONSE_FEED
        LD      A, 116
        CALL    T_EXPECT_C
        LD      A, (WX1_ERROR_CODE)
        CP      MAIN.WXE_TEXT
        LD      A, 117
        CALL    T_EXPECT_Z

        CALL    RESET_RESPONSE
        LD      HL, FIXTURE_MISSING_DAY
        LD      BC, FIXTURE_MISSING_DAY_END - FIXTURE_MISSING_DAY
        CALL    MAIN.RESPONSE_FEED
        LD      A, 118
        CALL    T_EXPECT_C
        LD      A, (WX1_ERROR_CODE)
        CP      MAIN.WXE_FIELD_COUNT
        LD      A, 119
        CALL    T_EXPECT_Z
        RET

TEST_PARSER_LIMITS:
        CALL    RESET_RESPONSE
        LD      HL, FIXTURE_PARTIAL
        LD      BC, FIXTURE_PARTIAL_END - FIXTURE_PARTIAL
        CALL    MAIN.RESPONSE_FEED
        LD      A, 120
        CALL    T_EXPECT_NC
        CALL    MAIN.RESPONSE_EOF
        LD      A, 121
        CALL    T_EXPECT_C
        LD      A, (WX1_ERROR_CODE)
        CP      MAIN.WXE_PREMATURE_EOF
        LD      A, 122
        CALL    T_EXPECT_Z
        LD      A, (TRANSPORT_RESPONSE_ERROR)
        CP      MAIN.TRESP_PARSER
        LD      A, 123
        CALL    T_EXPECT_Z

        CALL    RESET_RESPONSE
        LD      HL, FIXTURE_LONG_LINE
        LD      BC, FIXTURE_LONG_LINE_END - FIXTURE_LONG_LINE
        CALL    MAIN.RESPONSE_FEED
        LD      A, 124
        CALL    T_EXPECT_C
        LD      A, (WX1_ERROR_CODE)
        CP      MAIN.WXE_LINE_TOO_LONG
        LD      A, 125
        CALL    T_EXPECT_Z

        CALL    RESET_RESPONSE
        LD      A, MAIN.WX1_MAX_LINES
        LD      (WX1_LINE_COUNT), A
        LD      HL, LF
        LD      BC, 1
        CALL    MAIN.RESPONSE_FEED
        LD      A, 126
        CALL    T_EXPECT_C
        LD      A, (WX1_ERROR_CODE)
        CP      MAIN.WXE_LINE_COUNT
        LD      A, 127
        CALL    T_EXPECT_Z
        RET

TEST_BUFFER_LIMIT:
        CALL    RESET_RESPONSE
        LD      HL, RESPONSE_MAX
        LD      (RESPONSE_SIZE), HL
        LD      HL, DOT
        LD      BC, 1
        CALL    MAIN.RESPONSE_FEED
        LD      A, 50
        CALL    T_EXPECT_C
        LD      HL, (RESPONSE_SIZE)
        LD      DE, RESPONSE_MAX
        OR      A
        SBC     HL, DE
        LD      A, 51
        CALL    T_EXPECT_Z
        LD      A, (WX1_ERROR_CODE)
        OR      A
        LD      A, 52
        CALL    T_EXPECT_Z
        LD      A, (TRANSPORT_RESPONSE_ERROR)
        CP      MAIN.TRESP_TRANSPORT
        LD      A, 53
        CALL    T_EXPECT_Z
        RET

RESET_RESPONSE:
        CALL    MAIN.TRANSPORT_RESET
        LD      HL, (RESPONSE_SIZE)
        LD      DE, 0
        OR      A
        SBC     HL, DE
        LD      A, 60
        CALL    T_EXPECT_Z
        LD      A, (WX1_STATE)
        OR      A
        LD      A, 61
        CALL    T_EXPECT_Z
        LD      A, (WX1_ERROR_CODE)
        OR      A
        LD      A, 62
        CALL    T_EXPECT_Z
        RET

; Never called by these tests; required by included production transport.
CALL_UNET:
        XOR     A
        RET

        MODULE  MAIN
        INCLUDE "wx1.asm"
        INCLUDE "transport.asm"
        ENDMODULE

DOT:                    DB '.'
NUMBER_164:             DB "164",0
NUMBER_MIN:             DB "-32768",0
NUMBER_OVERFLOW:        DB "32768",0
CR:                     DB 13
LF:                     DB 10
PREFIX_CRLF:
        DB "WX1|OK|1",13,10,"L|X|KZ",13,10
        DB "N|20260722T1430|235|241|63|2|117|230",13,10
        DB "D|20260722|164|257|61|40|153",13,10
        DB "A|S|u",13,10
PREFIX_CRLF_END:
FIXTURE_CRLF:
        DB "WX1|OK|1",13,10,"L|X|KZ",13,10
        DB "N|20260722T1430|235|241|63|2|117|230",13,10
        DB "D|20260722|164|257|61|40|153",13,10
        DB "A|S|u",13,10,'.',13,10
FIXTURE_CRLF_END:
FIXTURE_CR:
        DB "WX1|OK|1",13,"L|X|KZ",13
        DB "N|20260722T1430|235|241|63|2|117|230",13
        DB "D|20260722|164|257|61|40|153",13
        DB "A|S|u",13,'.',13
FIXTURE_CR_END:
FIXTURE_LF:
        DB "WX1|OK|1",10,"L|X|KZ",10
        DB "N|20260722T1430|235|241|63|2|117|230",10
        DB "D|20260722|164|257|61|40|153",10
        DB "A|S|u",10,'.',10
FIXTURE_LF_END:
FIXTURE_MIXED:
        DB "WX1|OK|1",13,10,"L|X|KZ",10
FIXTURE_MIXED_END:
FIXTURE_CR_TRAILING:
        DB "WX1|OK|1",13,"L|X|KZ",13
        DB "N|20260722T1430|235|241|63|2|117|230",13
        DB "D|20260722|164|257|61|40|153",13
        DB "A|S|u",13,'.',13,'X'
FIXTURE_CR_TRAILING_END:
FIXTURE_DIRECTION_360:
        DB "WX1|OK|1",13,10,"L|X|KZ",13,10
        DB "N|20260722T1430|235|241|63|2|117|360",13,10
        DB "D|20260722|164|257|61|40|153",13,10
        DB "A|S|u",13,10,'.',13,10
FIXTURE_DIRECTION_360_END:
FIXTURE_DIRECTION_361:
        DB "WX1|OK|1",13,10,"L|X|KZ",13,10
        DB "N|20260722T1430|235|241|63|2|117|361",13,10
FIXTURE_DIRECTION_361_END:
FIXTURE_HUMIDITY_101:
        DB "WX1|OK|1",13,10,"L|X|KZ",13,10
        DB "N|20260722T1430|235|241|101|2|117|230",13,10
FIXTURE_HUMIDITY_101_END:
FIXTURE_DATE_NONLEAP:
        DB "WX1|OK|1",13,10,"L|X|KZ",13,10
        DB "N|20260229T1430|235|241|63|2|117|230",13,10
FIXTURE_DATE_NONLEAP_END:
FIXTURE_DATE_FEB30:
        DB "WX1|OK|1",13,10,"L|X|KZ",13,10
        DB "N|20260228T1430|235|241|63|2|117|230",13,10
        DB "D|20260230|164|257|61|40|153",13,10
FIXTURE_DATE_FEB30_END:
FIXTURE_CONTROL_TEXT:
        DB "WX1|OK|1",13,10,"L|X",1,"Y|KZ",13,10
FIXTURE_CONTROL_TEXT_END:
FIXTURE_MISSING_DAY:
        DB "WX1|OK|2",13,10,"L|X|KZ",13,10
        DB "N|20260722T1430|235|241|63|2|117|230",13,10
        DB "D|20260722|164|257|61|40|153",13,10
        DB "A|S|u",13,10
FIXTURE_MISSING_DAY_END:
FIXTURE_PARTIAL:
        DB "WX1|OK|1",13,10,"L|X"
FIXTURE_PARTIAL_END:
FIXTURE_LONG_LINE:
        DS 160, 'X'
FIXTURE_LONG_LINE_END:
SERVICE_GEO:            DB "GEO_UNAVAILABLE",0
FIXTURE_SERVICE_ERROR:
        DB "WX1|ERR|0",13,10,"E|GEO_UNAVAILABLE",13,10,'.',13,10
FIXTURE_SERVICE_ERROR_END:
FIXTURE_7:
        DB "WX1|OK|7",13,10
        DB "L|",08Ch,0AEh,0E1h,0AAh,0A2h,0A0h,"|RU",13,10
        DB "N|20260722T1430|235|241|63|2|117|230",13,10
        DB "D|20260722|164|257|61|40|153",13,10
        DB "D|20260723|-13|27|3|20|128",13,10
        DB "D|20260724|30|130|0|0|30",13,10
        DB "D|20260725|40|140|1|1|40",13,10
        DB "D|20260726|50|150|2|2|50",13,10
        DB "D|20260727|60|160|45|3|60",13,10
        DB "D|20260728|70|170|95|4|70",13,10
        DB "A|Open-Meteo.com|https://open-meteo.com/",13,10,'.',13,10
FIXTURE_7_END:
