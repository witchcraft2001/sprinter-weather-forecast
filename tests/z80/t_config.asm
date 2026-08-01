        DEVICE  NOSLOT64K
        ORG     0
        JP      START

        INCLUDE "harness.inc"

; DSS symbols are needed to assemble CONFIG_LOAD, although this harness calls
; the parser directly and performs no DSS I/O.
DSS                     EQU 010h
DSS_OPEN_FILE           EQU 011h
DSS_CLOSE_FILE          EQU 012h
DSS_READ_FILE           EQU 013h
DSS_MOVE_FP             EQU 015h
DSS_APPINFO             EQU 047h
APPINFO_EXE_HOMEDIR     EQU 1
FM_READ                 EQU 1
SEEK_END                EQU 2
E_FILE_NOT_FOUND        EQU 3

; Production-sized configuration workspace.
CFG_PATH                EQU 07000h
CFG_PATH_SIZE           EQU 272
CFG_FILE_BUFFER         EQU CFG_PATH + CFG_PATH_SIZE
CFG_FILE_MAX            EQU 1024
CFG_FILE_SIZE           EQU CFG_FILE_BUFFER + CFG_FILE_MAX
CFG_FILE_HANDLE         EQU CFG_FILE_SIZE + 2
CFG_LINE_BUFFER         EQU CFG_FILE_HANDLE + 1
CFG_LINE_MAX            EQU 255
CFG_LINE_LEN            EQU CFG_LINE_BUFFER + CFG_LINE_MAX + 1
CFG_LINE_NO             EQU CFG_LINE_LEN + 1
CFG_ERROR_LINE          EQU CFG_LINE_NO + 2
CFG_ERROR_CODE          EQU CFG_ERROR_LINE + 2
CFG_WARNING_LINE        EQU CFG_ERROR_CODE + 1
CFG_HOST                EQU CFG_WARNING_LINE + 2
CFG_HOST_SIZE           EQU 129
CFG_PORT                EQU CFG_HOST + CFG_HOST_SIZE
CFG_PORT_SIZE           EQU 6
CFG_PORT_NUMBER         EQU CFG_PORT + CFG_PORT_SIZE
CFG_SELECTOR            EQU CFG_PORT_NUMBER + 2
CFG_SELECTOR_SIZE       EQU 97
CFG_LOCATION            EQU CFG_SELECTOR + CFG_SELECTOR_SIZE
CFG_LOCATION_SIZE       EQU 97
REQUEST_MAX             EQU 192

START:
        CALL    T_BEGIN
        CALL    TEST_HOST_LF
        CALL    TEST_HOST_CRLF
        CALL    TEST_HOST_NO_EOL
        CALL    TEST_MULTILINE
        CALL    TEST_SPACES_AND_CASE
        CALL    T_END
        HALT

TEST_HOST_LF:
        LD      HL, CFG_HOST_LF
        LD      BC, CFG_HOST_LF_END - CFG_HOST_LF
        CALL    PARSE_FIXTURE
        LD      A, 1
        CALL    T_EXPECT_NC
        LD      HL, CFG_HOST
        LD      DE, EXPECTED_HOST
        CALL    STREQ
        LD      A, 2
        CALL    T_EXPECT_Z
        RET

TEST_HOST_CRLF:
        LD      HL, CFG_HOST_CRLF
        LD      BC, CFG_HOST_CRLF_END - CFG_HOST_CRLF
        CALL    PARSE_FIXTURE
        LD      A, 3
        CALL    T_EXPECT_NC
        LD      HL, CFG_HOST
        LD      DE, EXPECTED_HOST
        CALL    STREQ
        LD      A, 4
        CALL    T_EXPECT_Z
        RET

TEST_HOST_NO_EOL:
        LD      HL, CFG_HOST_NO_EOL
        LD      BC, CFG_HOST_NO_EOL_END - CFG_HOST_NO_EOL
        CALL    PARSE_FIXTURE
        LD      A, 5
        CALL    T_EXPECT_NC
        LD      HL, CFG_HOST
        LD      DE, EXPECTED_HOST
        CALL    STREQ
        LD      A, 6
        CALL    T_EXPECT_Z
        RET

TEST_MULTILINE:
        LD      HL, CFG_MULTILINE
        LD      BC, CFG_MULTILINE_END - CFG_MULTILINE
        CALL    PARSE_FIXTURE
        LD      A, 7
        CALL    T_EXPECT_NC
        LD      HL, (CFG_PORT_NUMBER)
        LD      DE, 7070
        OR      A
        SBC     HL, DE
        LD      A, 8
        CALL    T_EXPECT_Z
        LD      HL, CFG_SELECTOR
        LD      DE, EXPECTED_SELECTOR
        CALL    STREQ
        LD      A, 9
        CALL    T_EXPECT_Z
        LD      HL, CFG_LOCATION
        LD      DE, EXPECTED_LOCATION
        CALL    STREQ
        LD      A, 10
        CALL    T_EXPECT_Z
        RET

TEST_SPACES_AND_CASE:
        LD      HL, CFG_SPACES
        LD      BC, CFG_SPACES_END - CFG_SPACES
        CALL    PARSE_FIXTURE
        LD      A, 11
        CALL    T_EXPECT_NC
        LD      HL, CFG_HOST
        LD      DE, EXPECTED_HOST
        CALL    STREQ
        LD      A, 12
        CALL    T_EXPECT_Z
        RET

; HL=fixture, BC=size.
PARSE_FIXTURE:
        PUSH    BC
        LD      DE, CFG_FILE_BUFFER
        LDIR
        POP     HL
        LD      (CFG_FILE_SIZE), HL
        CALL    MAIN.CFG_SET_DEFAULTS
        XOR     A
        LD      (CFG_ERROR_CODE), A
        LD      (CFG_WARNING_LINE), A
        LD      (CFG_WARNING_LINE + 1), A
        JP      MAIN.CFG_PARSE_FILE

STREQ:
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

        MODULE  MAIN
        INCLUDE "config.asm"
        ENDMODULE

EXPECTED_HOST:          DB "go.sprinter.ru", 0
EXPECTED_SELECTOR:      DB "/weather/zx", 0
EXPECTED_LOCATION:      DB "Almaty,KZ", 0

CFG_HOST_LF:
        DB "HOST=go.sprinter.ru", 10
CFG_HOST_LF_END:
CFG_HOST_CRLF:
        DB "HOST=go.sprinter.ru", 13, 10
CFG_HOST_CRLF_END:
CFG_HOST_NO_EOL:
        DB "HOST=go.sprinter.ru"
CFG_HOST_NO_EOL_END:
CFG_MULTILINE:
        DB "# test", 13, 10
        DB "HOST=go.sprinter.ru", 13, 10
        DB "PORT=7070", 13, 10
        DB "SELECTOR=/weather/zx", 13, 10
        DB "LOCATION=Almaty,KZ", 13, 10
CFG_MULTILINE_END:
CFG_SPACES:
        DB "  host = go.sprinter.ru  ", 10
CFG_SPACES_END:
