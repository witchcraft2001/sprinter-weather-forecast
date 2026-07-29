; Streaming WX1 parser. Included inside MODULE MAIN.
;
; Input is never required to be NUL-terminated and may be split at any byte.
; A response uses one consistent line separator: CRLF, CR or LF.  The parser
; publishes WX1_MODEL only after the final terminator line has been accepted.

WX1_MORE                EQU 0
WX1_OK                  EQU 1
WX1_SERVICE_ERROR       EQU 2

WXS_HEADER              EQU 0
WXS_OK_LOCATION         EQU 1
WXS_OK_NOW              EQU 2
WXS_OK_DAY              EQU 3
WXS_OK_ATTRIBUTION      EQU 4
WXS_OK_DOT              EQU 5
WXS_ERR_CODE            EQU 6
WXS_ERR_DOT             EQU 7

WXE_NONE                EQU 0
WXE_LINE_TOO_LONG       EQU 090h
WXE_LINE_ENDING         EQU 091h
WXE_HEADER              EQU 092h
WXE_VERSION             EQU 093h
WXE_FIELD_COUNT         EQU 094h
WXE_ORDER               EQU 095h
WXE_NUMBER              EQU 096h
WXE_RANGE               EQU 097h
WXE_DATE_TIME           EQU 098h
WXE_TEXT                EQU 099h
WXE_MISSING             EQU 09Ah
WXE_TRAILING            EQU 09Bh
WXE_PREMATURE_EOF       EQU 09Ch
WXE_LINE_COUNT          EQU 09Dh

WX1_EOL_NONE            EQU 0
WX1_EOL_LF              EQU 1
WX1_EOL_CR              EQU 2
WX1_EOL_CRLF            EQU 3

WX1_LINE_MAX            EQU 159
WX1_MAX_LINES           EQU 16
WX1_MAX_DAYS            EQU 7

; WeatherModel layout. All strings include their terminating NUL.
WM_VALID                EQU 0
WM_LOCATION             EQU 1
WM_LOCATION_SIZE        EQU 65
WM_COUNTRY              EQU WM_LOCATION + WM_LOCATION_SIZE
WM_COUNTRY_SIZE         EQU 3
WM_SOURCE               EQU WM_COUNTRY + WM_COUNTRY_SIZE
WM_SOURCE_SIZE          EQU 33
WM_SOURCE_URL           EQU WM_SOURCE + WM_SOURCE_SIZE
WM_SOURCE_URL_SIZE      EQU 97
WM_DAY_COUNT            EQU WM_SOURCE_URL + WM_SOURCE_URL_SIZE
WM_CURRENT              EQU WM_DAY_COUNT + 1
WC_YEAR                 EQU 0
WC_MONTH                EQU 2
WC_DAY                  EQU 3
WC_HOUR                 EQU 4
WC_MINUTE               EQU 5
WC_TEMPERATURE          EQU 6
WC_APPARENT             EQU 8
WC_HUMIDITY             EQU 10
WC_CODE                 EQU 11
WC_WIND                 EQU 12
WC_DIRECTION            EQU 14
WM_CURRENT_SIZE         EQU 16
WM_DAYS                 EQU WM_CURRENT + WM_CURRENT_SIZE
WD_YEAR                 EQU 0
WD_MONTH                EQU 2
WD_DAY                  EQU 3
WD_MIN                  EQU 4
WD_MAX                  EQU 6
WD_CODE                 EQU 8
WD_PRECIPITATION        EQU 9
WD_WIND                 EQU 10
WM_DAY_SIZE             EQU 12
WM_MODEL_SIZE           EQU WM_DAYS + WX1_MAX_DAYS * WM_DAY_SIZE

; Reset parser-only state. The caller owns model validity between attempts.
WX1_RESET:
        XOR     A
        LD      (WX1_STATE), A
        LD      (WX1_LINE_LEN), A
        LD      (WX1_LINE_COUNT), A
        LD      (WX1_EOL_MODE), A
        LD      (WX1_PENDING_CR), A
        LD      (WX1_RESULT), A
        LD      (WX1_ERROR_CODE), A
        LD      (WX1_DAYS_LEFT), A
        LD      (WX1_FIELD_COUNT), A
        LD      (WX1_SERVICE_CODE), A
        LD      (WX1_STAGE_MODEL + WM_VALID), A
        LD      (WX1_MODEL + WM_VALID), A
        LD      (WX1_ERROR_LINE), A
        LD      HL, WX1_STAGE_MODEL + WM_DAYS
        LD      (WX1_NEXT_DAY_PTR), HL
        OR      A
        RET

; HL=data, BC=size. A=WX1_MORE/WX1_OK/WX1_SERVICE_ERROR, CF on parse error.
WX1_FEED:
WX1_FEED_LOOP:
        LD      A, B
        OR      C
        JR      Z, WX1_FEED_RESULT
        LD      A, (HL)
        INC     HL
        DEC     BC
        PUSH    HL
        PUSH    BC
        CALL    WX1_FEED_BYTE
        POP     BC
        POP     HL
        RET     C
        JR      WX1_FEED_LOOP
WX1_FEED_RESULT:
        LD      A, (WX1_RESULT)
        OR      A
        RET

; EOF is only valid after an explicit final line terminator.
WX1_EOF:
        LD      A, (WX1_PENDING_CR)
        OR      A
        JR      Z, .CHECK_RESULT
        XOR     A
        LD      (WX1_PENDING_CR), A
        LD      A, WX1_EOL_CR
        CALL    WX1_CONFIRM_EOL
        RET     C
.CHECK_RESULT:
        LD      A, (WX1_RESULT)
        OR      A
        RET     NZ
        LD      A, WXE_PREMATURE_EOF
        JP      WX1_FAIL_A

; Consume one byte. CR is held until the following byte makes CRLF/CR clear.
WX1_FEED_BYTE:
        LD      (WX1_INPUT_BYTE), A
        LD      A, (WX1_RESULT)
        OR      A
        JR      Z, .NOT_DONE
        LD      A, WXE_TRAILING
        JP      WX1_FAIL_A
.NOT_DONE:
        LD      A, (WX1_PENDING_CR)
        OR      A
        JR      NZ, .HAS_PENDING_CR
        LD      A, (WX1_INPUT_BYTE)
        JR      .NORMAL
.HAS_PENDING_CR:
        XOR     A
        LD      (WX1_PENDING_CR), A
        LD      A, (WX1_INPUT_BYTE)
        CP      10
        JR      Z, .CRLF
        LD      A, WX1_EOL_CR
        CALL    WX1_CONFIRM_EOL
        RET     C
        LD      A, (WX1_RESULT)
        OR      A
        JR      Z, .REPROCESS
        LD      A, WXE_TRAILING
        JP      WX1_FAIL_A
.REPROCESS:
        LD      A, (WX1_INPUT_BYTE)
        JR      .NORMAL
.CRLF:
        LD      A, WX1_EOL_CRLF
        JP      WX1_CONFIRM_EOL
.NORMAL:
        CP      13
        JR      Z, .CR
        CP      10
        JR      Z, .LF
        JP      WX1_APPEND_A
.CR:
        LD      A, (WX1_EOL_MODE)
        CP      WX1_EOL_LF
        JR      Z, .BAD_EOL
        LD      A, 1
        LD      (WX1_PENDING_CR), A
        OR      A
        RET
.LF:
        LD      A, WX1_EOL_LF
        JP      WX1_CONFIRM_EOL
.BAD_EOL:
        LD      A, WXE_LINE_ENDING
        JP      WX1_FAIL_A

; A is the first observed separator format for the current line.
WX1_CONFIRM_EOL:
        LD      (WX1_EOL_CANDIDATE), A
        LD      A, (WX1_EOL_MODE)
        OR      A
        JR      Z, .SET
        LD      B, A
        LD      A, (WX1_EOL_CANDIDATE)
        CP      B
        JR      NZ, .BAD
        JR      WX1_COMPLETE_LINE
.SET:
        LD      A, (WX1_EOL_CANDIDATE)
        LD      (WX1_EOL_MODE), A
        JR      WX1_COMPLETE_LINE
.BAD:
        LD      A, WXE_LINE_ENDING
        JP      WX1_FAIL_A

WX1_APPEND_A:
        LD      B, A
        LD      A, (WX1_LINE_LEN)
        CP      WX1_LINE_MAX
        JR      NC, .FULL
        LD      E, A
        LD      D, 0
        LD      HL, WX1_LINE_BUFFER
        ADD     HL, DE
        LD      A, B
        LD      (HL), A
        LD      A, (WX1_LINE_LEN)
        INC     A
        LD      (WX1_LINE_LEN), A
        OR      A
        RET
.FULL:
        LD      A, WXE_LINE_TOO_LONG
        JP      WX1_FAIL_A

WX1_COMPLETE_LINE:
        LD      A, (WX1_LINE_LEN)
        LD      E, A
        LD      D, 0
        LD      HL, WX1_LINE_BUFFER
        ADD     HL, DE
        XOR     A
        LD      (HL), A
        LD      A, (WX1_LINE_COUNT)
        INC     A
        LD      (WX1_LINE_COUNT), A
        CP      WX1_MAX_LINES + 1
        JR      NC, .TOO_MANY
        CALL    WX1_PARSE_LINE
        RET     C
        XOR     A
        LD      (WX1_LINE_LEN), A
        OR      A
        RET
.TOO_MANY:
        LD      A, WXE_LINE_COUNT
        JP      WX1_FAIL_A

WX1_PARSE_LINE:
        CALL    WX1_TOKENIZE
        RET     C
        LD      A, (WX1_STATE)
        OR      A
        JP      Z, WX1_PARSE_HEADER
        CP      WXS_OK_LOCATION
        JP      Z, WX1_PARSE_LOCATION
        CP      WXS_OK_NOW
        JP      Z, WX1_PARSE_NOW
        CP      WXS_OK_DAY
        JP      Z, WX1_PARSE_DAY
        CP      WXS_OK_ATTRIBUTION
        JP      Z, WX1_PARSE_ATTRIBUTION
        CP      WXS_OK_DOT
        JP      Z, WX1_PARSE_OK_DOT
        CP      WXS_ERR_CODE
        JP      Z, WX1_PARSE_SERVICE_CODE
        CP      WXS_ERR_DOT
        JP      Z, WX1_PARSE_ERR_DOT
        LD      A, WXE_ORDER
        JP      WX1_FAIL_A

WX1_PARSE_HEADER:
        LD      A, 3
        CALL    WX1_REQUIRE_FIELDS
        RET     C
        LD      HL, (WX1_FIELD_PTRS)
        LD      DE, WX1_TEXT_VERSION
        CALL    WX1_STREQ
        JR      Z, .VERSION_OK
        LD      A, WXE_VERSION
        JP      WX1_FAIL_A
.VERSION_OK:
        LD      HL, (WX1_FIELD_PTRS + 2)
        LD      DE, WX1_TEXT_OK
        CALL    WX1_STREQ
        JR      Z, .OK
        LD      HL, (WX1_FIELD_PTRS + 2)
        LD      DE, WX1_TEXT_ERR
        CALL    WX1_STREQ
        JR      Z, .ERR
        LD      A, WXE_HEADER
        JP      WX1_FAIL_A
.OK:
        LD      HL, (WX1_FIELD_PTRS + 4)
        CALL    WX1_PARSE_U8
        JP      C, WX1_BAD_NUMBER
        OR      A
        JP      Z, WX1_BAD_RANGE
        CP      WX1_MAX_DAYS + 1
        JP      NC, WX1_BAD_RANGE
        LD      (WX1_DAYS_LEFT), A
        LD      (WX1_STAGE_MODEL + WM_DAY_COUNT), A
        LD      A, WXS_OK_LOCATION
        LD      (WX1_STATE), A
        OR      A
        RET
.ERR:
        LD      HL, (WX1_FIELD_PTRS + 4)
        CALL    WX1_PARSE_U8
        JP      C, WX1_BAD_NUMBER
        OR      A
        JP      NZ, WX1_BAD_RANGE
        LD      A, WXS_ERR_CODE
        LD      (WX1_STATE), A
        OR      A
        RET

WX1_PARSE_LOCATION:
        LD      A, 3
        CALL    WX1_REQUIRE_FIELDS
        RET     C
        LD      HL, (WX1_FIELD_PTRS)
        LD      DE, WX1_TEXT_LOCATION
        CALL    WX1_STREQ
        JR      Z, .TYPE_OK
        LD      A, WXE_ORDER
        JP      WX1_FAIL_A
.TYPE_OK:
        LD      HL, (WX1_FIELD_PTRS + 2)
        LD      DE, WX1_STAGE_MODEL + WM_LOCATION
        LD      B, WM_LOCATION_SIZE
        CALL    WX1_COPY_FIELD
        JP      C, WX1_BAD_TEXT
        LD      HL, (WX1_FIELD_PTRS + 4)
        CALL    WX1_COUNTRY_OK
        JP      C, WX1_BAD_TEXT
        LD      HL, (WX1_FIELD_PTRS + 4)
        LD      DE, WX1_STAGE_MODEL + WM_COUNTRY
        LD      B, WM_COUNTRY_SIZE
        CALL    WX1_COPY_FIELD
        JP      C, WX1_BAD_TEXT
        LD      A, WXS_OK_NOW
        LD      (WX1_STATE), A
        OR      A
        RET

WX1_PARSE_NOW:
        LD      A, 8
        CALL    WX1_REQUIRE_FIELDS
        RET     C
        LD      HL, (WX1_FIELD_PTRS)
        LD      DE, WX1_TEXT_NOW
        CALL    WX1_STREQ
        JR      Z, .TYPE_OK
        LD      A, WXE_ORDER
        JP      WX1_FAIL_A
.TYPE_OK:
        LD      HL, (WX1_FIELD_PTRS + 2)
        LD      DE, WX1_STAGE_MODEL + WM_CURRENT
        CALL    WX1_PARSE_DATETIME
        JP      C, WX1_BAD_DATETIME
        LD      HL, (WX1_FIELD_PTRS + 4)
        CALL    WX1_PARSE_S16
        JP      C, WX1_BAD_NUMBER
        LD      (WX1_STAGE_MODEL + WM_CURRENT + WC_TEMPERATURE), DE
        LD      HL, (WX1_FIELD_PTRS + 6)
        CALL    WX1_PARSE_S16
        JP      C, WX1_BAD_NUMBER
        LD      (WX1_STAGE_MODEL + WM_CURRENT + WC_APPARENT), DE
        LD      HL, (WX1_FIELD_PTRS + 8)
        CALL    WX1_PARSE_U8
        JP      C, WX1_BAD_NUMBER
        CP      101
        JP      NC, WX1_BAD_RANGE
        LD      (WX1_STAGE_MODEL + WM_CURRENT + WC_HUMIDITY), A
        LD      HL, (WX1_FIELD_PTRS + 10)
        CALL    WX1_PARSE_U8
        JP      C, WX1_BAD_NUMBER
        LD      (WX1_STAGE_MODEL + WM_CURRENT + WC_CODE), A
        LD      HL, (WX1_FIELD_PTRS + 12)
        CALL    WX1_PARSE_U16
        JP      C, WX1_BAD_NUMBER
        LD      (WX1_STAGE_MODEL + WM_CURRENT + WC_WIND), DE
        LD      HL, (WX1_FIELD_PTRS + 14)
        CALL    WX1_PARSE_U16
        JP      C, WX1_BAD_NUMBER
        LD      HL, 360
        OR      A
        SBC     HL, DE
        JP      C, WX1_BAD_RANGE
        LD      (WX1_STAGE_MODEL + WM_CURRENT + WC_DIRECTION), DE
        LD      A, WXS_OK_DAY
        LD      (WX1_STATE), A
        OR      A
        RET

WX1_PARSE_DAY:
        LD      A, 7
        CALL    WX1_REQUIRE_FIELDS
        RET     C
        LD      HL, (WX1_FIELD_PTRS)
        LD      DE, WX1_TEXT_DAY
        CALL    WX1_STREQ
        JR      Z, .TYPE_OK
        LD      A, WXE_ORDER
        JP      WX1_FAIL_A
.TYPE_OK:
        LD      IX, (WX1_NEXT_DAY_PTR)
        LD      HL, (WX1_FIELD_PTRS + 2)
        PUSH    IX
        POP     DE
        CALL    WX1_PARSE_DATE
        JP      C, WX1_BAD_DATETIME
        LD      HL, (WX1_FIELD_PTRS + 4)
        CALL    WX1_PARSE_S16
        JP      C, WX1_BAD_NUMBER
        LD      (IX + WD_MIN), E
        LD      (IX + WD_MIN + 1), D
        LD      HL, (WX1_FIELD_PTRS + 6)
        CALL    WX1_PARSE_S16
        JP      C, WX1_BAD_NUMBER
        LD      (IX + WD_MAX), E
        LD      (IX + WD_MAX + 1), D
        LD      HL, (WX1_FIELD_PTRS + 8)
        CALL    WX1_PARSE_U8
        JP      C, WX1_BAD_NUMBER
        LD      (IX + WD_CODE), A
        LD      HL, (WX1_FIELD_PTRS + 10)
        CALL    WX1_PARSE_U8
        JP      C, WX1_BAD_NUMBER
        CP      101
        JP      NC, WX1_BAD_RANGE
        LD      (IX + WD_PRECIPITATION), A
        LD      HL, (WX1_FIELD_PTRS + 12)
        CALL    WX1_PARSE_U16
        JP      C, WX1_BAD_NUMBER
        LD      (IX + WD_WIND), E
        LD      (IX + WD_WIND + 1), D
        LD      DE, WM_DAY_SIZE
        ADD     IX, DE
        LD      (WX1_NEXT_DAY_PTR), IX
        LD      A, (WX1_DAYS_LEFT)
        DEC     A
        LD      (WX1_DAYS_LEFT), A
        JR      NZ, .MORE
        LD      A, WXS_OK_ATTRIBUTION
        LD      (WX1_STATE), A
        OR      A
        RET
.MORE:
        OR      A
        RET

WX1_PARSE_ATTRIBUTION:
        LD      A, 3
        CALL    WX1_REQUIRE_FIELDS
        RET     C
        LD      HL, (WX1_FIELD_PTRS)
        LD      DE, WX1_TEXT_ATTRIBUTION
        CALL    WX1_STREQ
        JR      Z, .TYPE_OK
        LD      A, WXE_ORDER
        JP      WX1_FAIL_A
.TYPE_OK:
        LD      HL, (WX1_FIELD_PTRS + 2)
        LD      DE, WX1_STAGE_MODEL + WM_SOURCE
        LD      B, WM_SOURCE_SIZE
        CALL    WX1_COPY_FIELD
        JP      C, WX1_BAD_TEXT
        LD      HL, (WX1_FIELD_PTRS + 4)
        LD      DE, WX1_STAGE_MODEL + WM_SOURCE_URL
        LD      B, WM_SOURCE_URL_SIZE
        CALL    WX1_COPY_FIELD
        JP      C, WX1_BAD_TEXT
        LD      A, WXS_OK_DOT
        LD      (WX1_STATE), A
        OR      A
        RET

WX1_PARSE_OK_DOT:
        CALL    WX1_REQUIRE_DOT
        RET     C
        LD      A, (WX1_DAYS_LEFT)
        OR      A
        JP      NZ, WX1_BAD_MISSING
        LD      HL, WX1_STAGE_MODEL
        LD      DE, WX1_MODEL
        LD      BC, WM_MODEL_SIZE
        LDIR
        LD      A, 1
        LD      (WX1_MODEL + WM_VALID), A
        LD      A, WX1_OK
        LD      (WX1_RESULT), A
        OR      A
        RET

WX1_PARSE_SERVICE_CODE:
        LD      A, 2
        CALL    WX1_REQUIRE_FIELDS
        RET     C
        LD      HL, (WX1_FIELD_PTRS)
        LD      DE, WX1_TEXT_ERROR
        CALL    WX1_STREQ
        JR      Z, .TYPE_OK
        LD      A, WXE_ORDER
        JP      WX1_FAIL_A
.TYPE_OK:
        LD      HL, (WX1_FIELD_PTRS + 2)
        LD      DE, WX1_SERVICE_CODE
        LD      B, WX1_SERVICE_CODE_SIZE
        CALL    WX1_COPY_ASCII_TOKEN
        JP      C, WX1_BAD_TEXT
        LD      A, WXS_ERR_DOT
        LD      (WX1_STATE), A
        OR      A
        RET

WX1_PARSE_ERR_DOT:
        CALL    WX1_REQUIRE_DOT
        RET     C
        LD      A, WX1_SERVICE_ERROR
        LD      (WX1_RESULT), A
        OR      A
        RET

WX1_REQUIRE_DOT:
        LD      A, 1
        CALL    WX1_REQUIRE_FIELDS
        RET     C
        LD      HL, (WX1_FIELD_PTRS)
        LD      DE, WX1_TEXT_DOT
        CALL    WX1_STREQ
        RET     Z
        LD      A, WXE_ORDER
        JP      WX1_FAIL_A

; Tokenize the current ASCIIZ line in place. Up to eight fields are allowed.
WX1_TOKENIZE:
        LD      HL, WX1_LINE_BUFFER
        LD      DE, WX1_FIELD_PTRS
        LD      B, 1
        LD      A, L
        LD      (DE), A
        INC     DE
        LD      A, H
        LD      (DE), A
        INC     DE
.LOOP:
        LD      A, (HL)
        OR      A
        JR      Z, .DONE
        CP      '|'
        JR      NZ, .NEXT
        XOR     A
        LD      (HL), A
        INC     HL
        LD      A, B
        CP      8
        JR      NC, .TOO_MANY
        INC     B
        LD      A, L
        LD      (DE), A
        INC     DE
        LD      A, H
        LD      (DE), A
        INC     DE
        JR      .LOOP
.NEXT:
        INC     HL
        JR      .LOOP
.DONE:
        LD      A, B
        LD      (WX1_FIELD_COUNT), A
        OR      A
        RET
.TOO_MANY:
        LD      A, WXE_FIELD_COUNT
        JP      WX1_FAIL_A

; A expected fields.
WX1_REQUIRE_FIELDS:
        LD      B, A
        LD      A, (WX1_FIELD_COUNT)
        CP      B
        RET     Z
        LD      A, WXE_FIELD_COUNT
        JP      WX1_FAIL_A

; HL source, DE destination, B destination size including NUL.
WX1_COPY_FIELD:
        LD      A, B
        DEC     A
        LD      (WX1_COPY_LEFT), A
        LD      C, 0
.LOOP:
        LD      A, (HL)
        OR      A
        JR      Z, .DONE
        CP      20h
        JR      C, .BAD
        CP      7Fh
        JR      Z, .BAD
        LD      B, A
        LD      A, (WX1_COPY_LEFT)
        OR      A
        JR      Z, .BAD
        LD      A, B
        LD      (DE), A
        INC     HL
        INC     DE
        LD      A, (WX1_COPY_LEFT)
        DEC     A
        LD      (WX1_COPY_LEFT), A
        INC     C
        JR      .LOOP
.DONE:
        LD      A, C
        OR      A
        JR      Z, .BAD
        XOR     A
        LD      (DE), A
        OR      A
        RET
.BAD:
        SCF
        RET

; Like COPY_FIELD, plus ASCII token validation (A-Z, 0-9, underscore only).
WX1_COPY_ASCII_TOKEN:
        LD      A, B
        DEC     A
        LD      (WX1_COPY_LEFT), A
        LD      C, 0
.LOOP:
        LD      A, (HL)
        OR      A
        JR      Z, .DONE
        CP      'A'
        JR      C, .BAD
        CP      'Z' + 1
        JR      C, .STORE
        CP      '0'
        JR      C, .CHECK_UNDERSCORE
        CP      '9' + 1
        JR      C, .STORE
.CHECK_UNDERSCORE:
        CP      '_'
        JR      NZ, .BAD
.STORE:
        LD      B, A
        LD      A, (WX1_COPY_LEFT)
        OR      A
        JR      Z, .BAD
        LD      A, B
        LD      (DE), A
        INC     HL
        INC     DE
        LD      A, (WX1_COPY_LEFT)
        DEC     A
        LD      (WX1_COPY_LEFT), A
        INC     C
        JR      .LOOP
.DONE:
        LD      A, C
        OR      A
        JR      Z, .BAD
        XOR     A
        LD      (DE), A
        OR      A
        RET
.BAD:
        SCF
        RET

; HL country field. Accept AA..ZZ or the server's -- placeholder.
WX1_COUNTRY_OK:
        LD      A, (HL)
        CP      '-'
        JR      NZ, .LETTER1
        INC     HL
        LD      A, (HL)
        CP      '-'
        JR      NZ, .BAD
        INC     HL
        LD      A, (HL)
        OR      A
        RET     Z
        JR      .BAD
.LETTER1:
        CP      'A'
        JR      C, .BAD
        CP      'Z' + 1
        JR      NC, .BAD
        INC     HL
        LD      A, (HL)
        CP      'A'
        JR      C, .BAD
        CP      'Z' + 1
        JR      NC, .BAD
        INC     HL
        LD      A, (HL)
        OR      A
        RET     Z
.BAD:
        SCF
        RET

; HL decimal ASCIIZ -> DE unsigned 16-bit. No signs, whitespace or overflow.
WX1_PARSE_U16:
        PUSH    IX
        PUSH    HL
        POP     IX
        LD      DE, 0
        XOR     A
        LD      (WX1_DIGITS), A
.LOOP:
        LD      A, (IX)
        OR      A
        JR      Z, .DONE
        SUB     '0'
        JR      C, .BAD
        CP      10
        JR      NC, .BAD
        LD      (WX1_DIGIT), A
        LD      HL, DE
        ADD     HL, HL
        JR      C, .BAD
        LD      (WX1_TMP16), HL
        ADD     HL, HL
        JR      C, .BAD
        ADD     HL, HL
        JR      C, .BAD
        LD      BC, (WX1_TMP16)
        ADD     HL, BC
        JR      C, .BAD
        LD      A, (WX1_DIGIT)
        LD      C, A
        LD      B, 0
        ADD     HL, BC
        JR      C, .BAD
        EX      DE, HL
        LD      A, (WX1_DIGITS)
        INC     A
        LD      (WX1_DIGITS), A
        INC     IX
        JR      .LOOP
.DONE:
        LD      A, (WX1_DIGITS)
        OR      A
        JR      Z, .BAD
        POP     IX
        RET
.BAD:
        POP     IX
        SCF
        RET

; HL signed decimal ASCIIZ -> DE signed 16-bit.
WX1_PARSE_S16:
        LD      A, (HL)
        CP      '-'
        JR      NZ, .POSITIVE
        INC     HL
        CALL    WX1_PARSE_U16
        RET     C
        LD      HL, 08000h
        OR      A
        SBC     HL, DE
        JR      C, .BAD
        LD      HL, 0
        OR      A
        SBC     HL, DE
        EX      DE, HL
        OR      A
        RET
.POSITIVE:
        CALL    WX1_PARSE_U16
        RET     C
        BIT     7, D
        JR      NZ, .BAD
        OR      A
        RET
.BAD:
        SCF
        RET

; HL decimal ASCIIZ -> A u8.
WX1_PARSE_U8:
        CALL    WX1_PARSE_U16
        RET     C
        LD      A, D
        OR      A
        JR      NZ, .BAD
        LD      A, E
        OR      A
        RET
.BAD:
        SCF
        RET

; Parse an exact YYYYMMDD field into the destination supplied in DE.
WX1_PARSE_DATE:
        CALL    WX1_PARSE_DATE_PREFIX
        RET     C
        LD      A, (HL)
        OR      A
        RET     Z
        SCF
        RET

; Parse YYYYMMDD prefix into DE (year word, month/day bytes); HL advances.
WX1_PARSE_DATE_PREFIX:
        PUSH    DE
        POP     IX
        LD      B, 4
        CALL    WX1_PARSE_FIXED
        RET     C
        LD      A, D
        OR      E
        JR      Z, .BAD
        LD      (WX1_DATE_YEAR), DE
        LD      (IX + 0), E
        LD      (IX + 1), D
        LD      B, 2
        CALL    WX1_PARSE_FIXED
        RET     C
        LD      A, E
        OR      A
        JR      Z, .BAD
        CP      13
        JR      NC, .BAD
        LD      (IX + 2), A
        LD      (WX1_DATE_MONTH), A
        LD      B, 2
        CALL    WX1_PARSE_FIXED
        RET     C
        LD      A, E
        OR      A
        JR      Z, .BAD
        LD      (WX1_DATE_DAY), A
        LD      (IX + 3), A
        LD      DE, (WX1_DATE_YEAR)
        CALL    WX1_DATE_VALID
        RET
.BAD:
        SCF
        RET

; Parse YYYYMMDDTHHMM into current destination DE. HL must end at NUL.
WX1_PARSE_DATETIME:
        CALL    WX1_PARSE_DATE_PREFIX
        RET     C
        LD      A, (HL)
        CP      'T'
        JR      NZ, .BAD
        INC     HL
        LD      B, 2
        CALL    WX1_PARSE_FIXED
        RET     C
        LD      A, E
        CP      24
        JR      NC, .BAD
        LD      (IX + WC_HOUR), A
        LD      B, 2
        CALL    WX1_PARSE_FIXED
        RET     C
        LD      A, E
        CP      60
        JR      NC, .BAD
        LD      (IX + WC_MINUTE), A
        LD      A, (HL)
        OR      A
        RET     Z
.BAD:
        SCF
        RET

; HL exact decimal prefix of B digits -> DE. HL advances after the digits.
WX1_PARSE_FIXED:
        LD      DE, 0
.LOOP:
        LD      A, B
        OR      A
        RET     Z
        LD      A, (HL)
        SUB     '0'
        JR      C, .BAD
        CP      10
        JR      NC, .BAD
        LD      C, A
        PUSH    HL
        LD      HL, DE
        ADD     HL, HL
        LD      (WX1_TMP16), HL
        ADD     HL, HL
        ADD     HL, HL
        LD      DE, (WX1_TMP16)
        ADD     HL, DE
        LD      D, 0
        LD      E, C
        ADD     HL, DE
        EX      DE, HL
        POP     HL
        INC     HL
        DEC     B
        JR      .LOOP
.BAD:
        SCF
        RET

; Date components are in WX1_DATE_MONTH/DAY and DE is the numeric year.
WX1_DATE_VALID:
        LD      A, (WX1_DATE_MONTH)
        CP      2
        JR      Z, .FEBRUARY
        CP      4
        JR      Z, .THIRTY
        CP      6
        JR      Z, .THIRTY
        CP      9
        JR      Z, .THIRTY
        CP      11
        JR      Z, .THIRTY
        LD      A, 31
        JR      .COMPARE
.THIRTY:
        LD      A, 30
        JR      .COMPARE
.FEBRUARY:
        ; Gregorian leap year: divisible by 4, except centuries not by 400.
        LD      HL, DE
        LD      A, L
        AND     3
        JR      NZ, .FEB_28
        LD      A, H
        OR      L
        JR      Z, .FEB_28
        LD      HL, DE
        LD      BC, 100
        CALL    WX1_MOD16
        LD      A, H
        OR      L
        JR      NZ, .FEB_29
        LD      HL, DE
        LD      BC, 400
        CALL    WX1_MOD16
        LD      A, H
        OR      L
        JR      NZ, .FEB_28
.FEB_29:
        LD      A, 29
        JR      .COMPARE
.FEB_28:
        LD      A, 28
.COMPARE:
        LD      B, A
        LD      A, (WX1_DATE_DAY)
        INC     B
        CP      B
        JR      NC, .BAD
        OR      A
        RET
.BAD:
        SCF
        RET

; HL modulo BC, enough for the tiny year values used by date validation.
WX1_MOD16:
.LOOP:
        OR      A
        SBC     HL, BC
        JR      NC, .LOOP
        ADD     HL, BC
        RET

WX1_STREQ:
.LOOP:
        LD      A, (DE)
        LD      C, A
        LD      A, (HL)
        CP      C
        RET     NZ
        OR      A
        RET     Z
        INC     HL
        INC     DE
        JR      .LOOP

WX1_BAD_NUMBER:
        LD      A, WXE_NUMBER
        JP      WX1_FAIL_A
WX1_BAD_RANGE:
        LD      A, WXE_RANGE
        JP      WX1_FAIL_A
WX1_BAD_DATETIME:
        LD      A, WXE_DATE_TIME
        JP      WX1_FAIL_A
WX1_BAD_TEXT:
        LD      A, WXE_TEXT
        JP      WX1_FAIL_A
WX1_BAD_MISSING:
        LD      A, WXE_MISSING
        JP      WX1_FAIL_A

; A parser code. First error wins for the current attempt.
WX1_FAIL_A:
        LD      (WX1_ERROR_CODE), A
        LD      A, (WX1_LINE_COUNT)
        LD      (WX1_ERROR_LINE), A
        SCF
        RET

WX1_TEXT_VERSION:      DB      "WX1", 0
WX1_TEXT_OK:           DB      "OK", 0
WX1_TEXT_ERR:          DB      "ERR", 0
WX1_TEXT_LOCATION:     DB      "L", 0
WX1_TEXT_NOW:          DB      "N", 0
WX1_TEXT_DAY:          DB      "D", 0
WX1_TEXT_ATTRIBUTION:  DB      "A", 0
WX1_TEXT_ERROR:        DB      "E", 0
WX1_TEXT_DOT:          DB      ".", 0
