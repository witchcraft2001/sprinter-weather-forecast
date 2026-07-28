; WEATHER.CFG loader and bounded INI parser.  Included inside MODULE MAIN.

CFGERR_NONE             EQU 0
CFGERR_APPINFO           EQU 1
CFGERR_OPEN              EQU 2
CFGERR_SIZE              EQU 3
CFGERR_SEEK              EQU 4
CFGERR_READ              EQU 5
CFGERR_CLOSE             EQU 6
CFGERR_LINE              EQU 7
CFGERR_KEY               EQU 8
CFGERR_VALUE             EQU 9
CFGERR_REQUEST           EQU 10

; Out: CF=0 configuration is ready (defaults are valid when the file is
; absent); CF=1 with CFG_ERROR_LINE/CFG_ERROR_CODE filled on a hard error.
CONFIG_LOAD:
        CALL    CFG_SET_DEFAULTS
        XOR     A
        LD      (CFG_ERROR_CODE), A
        LD      (CFG_ERROR_LINE), A
        LD      (CFG_ERROR_LINE + 1), A
        LD      (CFG_WARNING_LINE), A
        LD      (CFG_WARNING_LINE + 1), A

        LD      HL, CFG_PATH
        LD      B, APPINFO_EXE_HOMEDIR
        LD      C, DSS_APPINFO
        RST     DSS
        JR      C, .BARE_PATH
        CALL    CFG_APPEND_SEPARATOR
        JP      C, .APPINFO_ERROR
        LD      HL, CFG_PATH
        CALL    CFG_APPEND_NAME
        JP      C, .APPINFO_ERROR
        JR      .OPEN
.BARE_PATH:
        LD      HL, CFG_PATH
        LD      DE, CFG_FILE_NAME
        CALL    CFG_COPY_Z
.OPEN:
        LD      HL, CFG_PATH
        LD      A, FM_READ
        LD      C, DSS_OPEN_FILE
        RST     DSS
        JR      NC, .OPENED
        CP      E_FILE_NOT_FOUND
        JR      Z, .DEFAULTS
        LD      (CFG_ERROR_CODE), A
        LD      A, CFGERR_OPEN
        JP      CFG_FAIL_CODE
.OPENED:
        LD      (CFG_FILE_HANDLE), A
        LD      B, SEEK_END
        LD      HL, 0
        LD      IX, 0
        LD      C, DSS_MOVE_FP
        RST     DSS
        JR      C, .SEEK_ERROR
        LD      A, H
        OR      L
        JR      NZ, .SIZE_ERROR
        PUSH    IX
        POP     HL
        LD      DE, CFG_FILE_MAX
        OR      A
        SBC     HL, DE
        JR      C, .SIZE_OK
        JR      Z, .SIZE_OK
.SIZE_ERROR:
        LD      A, CFGERR_SIZE
        JP      .CLOSE_AND_FAIL
.SIZE_OK:
        ; IX still contains the file size after the comparison above.
        LD      (CFG_FILE_SIZE), IX
        LD      A, (CFG_FILE_HANDLE)
        LD      B, 0
        LD      HL, 0
        LD      IX, 0
        LD      C, DSS_MOVE_FP
        RST     DSS
        JR      C, .SEEK_ERROR
        LD      DE, (CFG_FILE_SIZE)
        LD      A, D
        OR      E
        JR      Z, .CLOSE_PARSE
        LD      HL, CFG_FILE_BUFFER
        LD      A, (CFG_FILE_HANDLE)
        LD      C, DSS_READ_FILE
        RST     DSS
        JR      C, .READ_ERROR
.CLOSE_PARSE:
        CALL    CFG_CLOSE
        JR      C, .CLOSE_ERROR
        LD      HL, (CFG_FILE_SIZE)
        LD      DE, CFG_FILE_BUFFER
        ADD     HL, DE
        XOR     A
        LD      (HL), A
        CALL    CFG_PARSE_FILE
        RET
.DEFAULTS:
        OR      A
        RET
.APPINFO_ERROR:
        LD      A, CFGERR_APPINFO
        JP      CFG_FAIL_CODE
.SEEK_ERROR:
        LD      A, CFGERR_SEEK
        JR      .CLOSE_AND_FAIL
.READ_ERROR:
        LD      A, CFGERR_READ
        JR      .CLOSE_AND_FAIL
.CLOSE_ERROR:
        LD      A, CFGERR_CLOSE
        JP      CFG_FAIL_CODE
.CLOSE_AND_FAIL:
        PUSH    AF
        CALL    CFG_CLOSE
        POP     AF
        JP      CFG_FAIL_CODE

CFG_CLOSE:
        LD      A, (CFG_FILE_HANDLE)
        LD      C, DSS_CLOSE_FILE
        RST     DSS
        RET

; Start every load from canonical defaults.
CFG_SET_DEFAULTS:
        LD      HL, CFG_DEFAULT_HOST
        LD      DE, CFG_HOST
        CALL    CFG_COPY_Z
        LD      HL, CFG_DEFAULT_PORT
        LD      DE, CFG_PORT
        CALL    CFG_COPY_Z
        LD      HL, CFG_DEFAULT_SELECTOR
        LD      DE, CFG_SELECTOR
        CALL    CFG_COPY_Z
        XOR     A
        LD      (CFG_LOCATION), A
        LD      HL, 70
        LD      (CFG_PORT_NUMBER), HL
        RET

; Append a separator only when APPINFO did not already provide one.
CFG_APPEND_SEPARATOR:
        LD      HL, CFG_PATH
        LD      BC, CFG_PATH_SIZE - 1
.FIND_END:
        LD      A, (HL)
        OR      A
        JR      Z, .END
        INC     HL
        DEC     BC
        LD      A, B
        OR      C
        JR      NZ, .FIND_END
        SCF
        RET
.END:
        LD      A, H
        CP      HIGH CFG_PATH
        JR      NZ, .CHECK_LAST
        LD      A, L
        CP      LOW CFG_PATH
        JR      Z, .ADD
.CHECK_LAST:
        DEC     HL
        LD      A, (HL)
        INC     HL
        CP      92
        JR      Z, .OK
        CP      '/'
        JR      Z, .OK
.ADD:
        LD      (HL), 92
        INC     HL
        XOR     A
        LD      (HL), A
.OK:
        OR      A
        RET

CFG_APPEND_NAME:
        LD      HL, CFG_PATH
        LD      BC, CFG_PATH_SIZE - 1
.FIND:
        LD      A, (HL)
        OR      A
        JR      Z, .COPY
        INC     HL
        DEC     BC
        LD      A, B
        OR      C
        JR      NZ, .FIND
        SCF
        RET
.COPY:
        EX      DE, HL
        LD      HL, CFG_FILE_NAME
        ; DE points at the NUL; room was reserved by the fixed 8.3 name.
        CALL    CFG_COPY_Z
        OR      A
        RET

; Parse CFG_FILE_BUFFER[0..CFG_FILE_SIZE).  CR is ignored, LF ends a line;
; a final line without LF is accepted.
CFG_PARSE_FILE:
        LD      HL, 1
        LD      (CFG_LINE_NO), HL
        XOR     A
        LD      (CFG_LINE_LEN), A
        LD      HL, CFG_FILE_BUFFER
        LD      BC, (CFG_FILE_SIZE)
.BYTE:
        LD      A, B
        OR      C
        JR      Z, .EOF
        LD      A, (HL)
        INC     HL
        DEC     BC
        CP      13
        JR      Z, .BYTE
        CP      10
        JR      Z, .FLUSH
        CALL    CFG_LINE_APPEND
        JR      C, .LINE_ERROR
        JR      .BYTE
.FLUSH:
        CALL    CFG_PROCESS_LINE
        RET     C
        CALL    CFG_NEXT_LINE
        JR      .BYTE
.EOF:
        LD      A, (CFG_LINE_LEN)
        OR      A
        JR      Z, .VALIDATE
        CALL    CFG_PROCESS_LINE
        RET     C
.VALIDATE:
        CALL    CFG_VALIDATE_REQUEST
        RET
.LINE_ERROR:
        LD      A, CFGERR_LINE
        JP      CFG_FAIL_CODE

CFG_LINE_APPEND:
        PUSH    AF
        LD      A, (CFG_LINE_LEN)
        CP      CFG_LINE_MAX
        JR      NC, .FULL
        LD      E, A
        LD      D, 0
        PUSH    HL
        LD      HL, CFG_LINE_BUFFER
        ADD     HL, DE
        POP     DE
        POP     AF
        LD      (HL), A
        EX      DE, HL                ; restore file cursor in HL
        LD      A, (CFG_LINE_LEN)
        INC     A
        LD      (CFG_LINE_LEN), A
        OR      A
        RET
.FULL:
        POP     AF
        SCF
        RET

CFG_NEXT_LINE:
        XOR     A
        LD      (CFG_LINE_LEN), A
        LD      HL, (CFG_LINE_NO)
        INC     HL
        LD      (CFG_LINE_NO), HL
        RET

; Make a NUL-terminated line, trim it, split at '=', and dispatch the value.
CFG_PROCESS_LINE:
        LD      A, (CFG_LINE_LEN)
        LD      E, A
        LD      D, 0
        LD      HL, CFG_LINE_BUFFER
        ADD     HL, DE
        XOR     A
        LD      (HL), A
        LD      HL, CFG_LINE_BUFFER
        CALL    CFG_SKIP_SPACE
        LD      A, (HL)
        OR      A
        RET     Z
        CP      '#'
        RET     Z
        CP      ';'
        RET     Z
        LD      DE, HL
.FIND_EQ:
        LD      A, (DE)
        OR      A
        JP      Z, .KEY_ERROR
        CP      '='
        JR      Z, .GOT_EQ
        INC     DE
        JR      .FIND_EQ
.GOT_EQ:
        XOR     A
        LD      (DE), A
        PUSH    DE
        CALL    CFG_TRIM_RIGHT
        POP     DE
        INC     DE
        EX      DE, HL
        CALL    CFG_SKIP_SPACE
        CALL    CFG_TRIM_RIGHT
        LD      (CFG_VALUE_PTR), HL
        LD      HL, CFG_LINE_BUFFER
        CALL    CFG_SKIP_SPACE
        LD      DE, CFG_KEY_HOST
        CALL    CFG_KEY_EQUALS
        JR      Z, .HOST
        LD      HL, CFG_LINE_BUFFER
        CALL    CFG_SKIP_SPACE
        LD      DE, CFG_KEY_PORT
        CALL    CFG_KEY_EQUALS
        JR      Z, .PORT
        LD      HL, CFG_LINE_BUFFER
        CALL    CFG_SKIP_SPACE
        LD      DE, CFG_KEY_SELECTOR
        CALL    CFG_KEY_EQUALS
        JR      Z, .SELECTOR
        LD      HL, CFG_LINE_BUFFER
        CALL    CFG_SKIP_SPACE
        LD      DE, CFG_KEY_LOCATION
        CALL    CFG_KEY_EQUALS
        JR      Z, .LOCATION
        LD      HL, (CFG_WARNING_LINE)
        LD      A, H
        OR      L
        RET     NZ
        LD      HL, (CFG_LINE_NO)
        LD      (CFG_WARNING_LINE), HL
        OR      A
        RET
.HOST:
        LD      HL, (CFG_VALUE_PTR)
        LD      DE, CFG_HOST
        LD      B, CFG_HOST_SIZE
        LD      A, 1
        CALL    CFG_COPY_VALUE
        JR      C, .VALUE_ERROR
        OR      A
        RET
.PORT:
        LD      HL, (CFG_VALUE_PTR)
        LD      DE, CFG_PORT
        LD      B, CFG_PORT_SIZE
        LD      A, 2
        CALL    CFG_COPY_VALUE
        JR      C, .VALUE_ERROR
        LD      HL, CFG_PORT
        CALL    CFG_PARSE_PORT
        JR      C, .VALUE_ERROR
        OR      A
        RET
.SELECTOR:
        LD      HL, (CFG_VALUE_PTR)
        LD      DE, CFG_SELECTOR
        LD      B, CFG_SELECTOR_SIZE
        LD      A, 3
        CALL    CFG_COPY_VALUE
        JR      C, .VALUE_ERROR
        LD      A, (CFG_SELECTOR)
        CP      '/'
        JR      NZ, .VALUE_ERROR
        OR      A
        RET
.LOCATION:
        LD      HL, (CFG_VALUE_PTR)
        LD      DE, CFG_LOCATION
        LD      B, CFG_LOCATION_SIZE
        XOR     A
        CALL    CFG_COPY_VALUE
        JR      C, .VALUE_ERROR
        OR      A
        RET
.KEY_ERROR:
        LD      A, CFGERR_KEY
        JP      CFG_FAIL_CODE
.VALUE_ERROR:
        LD      A, CFGERR_VALUE
        JP      CFG_FAIL_CODE

; A=rule (0 location, 1 host, 2 port, 3 selector); B=destination capacity.
; Copy HL ASCIIZ to DE and reject a value that is empty when rule != 0.
CFG_COPY_VALUE:
        LD      (CFG_COPY_RULE), A
        LD      A, B
        DEC     A
        LD      (CFG_COPY_LEFT), A
        XOR     A
        LD      (CFG_COPY_COUNT), A
.LOOP:
        LD      A, (HL)
        OR      A
        JR      Z, .END
        CALL    CFG_VALUE_CHAR_OK
        JR      C, .BAD
        LD      A, (CFG_COPY_LEFT)
        OR      A
        JR      Z, .BAD
        LD      A, (HL)
        LD      (DE), A
        INC     HL
        INC     DE
        LD      A, (CFG_COPY_LEFT)
        DEC     A
        LD      (CFG_COPY_LEFT), A
        LD      A, (CFG_COPY_COUNT)
        INC     A
        LD      (CFG_COPY_COUNT), A
        JR      .LOOP
.END:
        XOR     A
        LD      (DE), A
        LD      A, (CFG_COPY_RULE)
        OR      A
        JR      Z, .OK
        LD      A, (CFG_COPY_COUNT)
        OR      A
        JR      Z, .BAD
.OK:
        OR      A
        RET
.BAD:
        SCF
        RET

CFG_VALUE_CHAR_OK:
        PUSH    AF
        LD      A, (CFG_COPY_RULE)
        CP      1
        JR      Z, .HOST
        CP      2
        JR      Z, .PORT
        ; selector/location reject controls and TAB only.
        POP     AF
        CP      32
        JR      C, .BAD
        CP      127
        JR      NC, .BAD
        OR      A
        RET
.HOST:
        POP     AF
        CP      33
        JR      C, .BAD
        CP      127
        JR      NC, .BAD
        OR      A
        RET
.PORT:
        POP     AF
        CP      '0'
        JR      C, .BAD
        CP      '9' + 1
        JR      NC, .BAD
        OR      A
        RET
.BAD:
        SCF
        RET

CFG_PARSE_PORT:
        LD      DE, 0
.LOOP:
        LD      A, (HL)
        OR      A
        JR      Z, .DONE
        SUB     '0'
        LD      (CFG_DIGIT), A
        PUSH    HL
        EX      DE, HL
        ADD     HL, HL
        JR      C, .POP_BAD
        PUSH    HL
        ADD     HL, HL
        JR      C, .POP2_BAD
        ADD     HL, HL
        JR      C, .POP2_BAD
        POP     BC
        ADD     HL, BC
        JR      C, .POP_BAD
        LD      A, (CFG_DIGIT)
        LD      C, A
        LD      B, 0
        ADD     HL, BC
        JR      C, .POP_BAD
        EX      DE, HL
        POP     HL
        INC     HL
        JR      .LOOP
.POP2_BAD:
        POP     BC
.POP_BAD:
        POP     HL
        SCF
        RET
.DONE:
        LD      A, D
        OR      E
        JR      Z, .BAD
        LD      (CFG_PORT_NUMBER), DE
        OR      A
        RET
.BAD:
        SCF
        RET

CFG_VALIDATE_REQUEST:
        LD      HL, CFG_SELECTOR
        CALL    CFG_STRLEN
        INC     HL                    ; CR
        INC     HL                    ; LF
        LD      DE, CFG_LOCATION
        LD      A, (DE)
        OR      A
        JR      Z, .COMPARE
        INC     HL                    ; TAB
        PUSH    HL
        LD      HL, CFG_LOCATION
        CALL    CFG_STRLEN
        EX      DE, HL
        POP     HL
        ADD     HL, DE
.COMPARE:
        LD      DE, REQUEST_MAX
        OR      A
        SBC     HL, DE
        JR      C, .OK
        JR      Z, .OK
        LD      A, CFGERR_REQUEST
        JP      CFG_FAIL_CODE
.OK:
        OR      A
        RET

; HL ASCIIZ -> HL length.
CFG_STRLEN:
        LD      DE, 0
.COUNT:
        LD      A, (HL)
        OR      A
        JR      Z, .DONE
        INC     HL
        INC     DE
        JR      .COUNT
.DONE:
        EX      DE, HL
        RET

CFG_SKIP_SPACE:
        LD      A, (HL)
        CP      ' '
        JR      Z, .NEXT
        CP      9
        RET     NZ
.NEXT:
        INC     HL
        JR      CFG_SKIP_SPACE

; Trim spaces/tabs before the terminating NUL. HL points to the first char.
CFG_TRIM_RIGHT:
        LD      DE, HL
.FIND:
        LD      A, (HL)
        OR      A
        JR      Z, .BACK
        INC     HL
        JR      .FIND
.BACK:
        LD      A, H
        CP      D
        JR      NZ, .NOT_EMPTY
        LD      A, L
        CP      E
        RET     Z
.NOT_EMPTY:
        DEC     HL
.TRIM:
        LD      A, (HL)
        CP      ' '
        JR      Z, .ZERO
        CP      9
        JR      NZ, .DONE
.ZERO:
        XOR     A
        LD      (HL), A
        LD      A, H
        CP      D
        JR      NZ, .DEC
        LD      A, L
        CP      E
        JR      Z, .DONE
.DEC:
        DEC     HL
        LD      A, H
        CP      D
        JR      NZ, .TRIM
        LD      A, L
        CP      E
        JR      NZ, .TRIM
.DONE:
        EX      DE, HL
        RET

; Compare HL key with DE literal case-insensitively; Z means equal.
CFG_KEY_EQUALS:
.LOOP:
        LD      A, (HL)
        CALL    CFG_UPPER
        LD      C, A
        LD      A, (DE)
        CALL    CFG_UPPER
        CP      C
        RET     NZ
        OR      A
        RET     Z
        INC     HL
        INC     DE
        JR      .LOOP

CFG_UPPER:
        CP      'a'
        RET     C
        CP      'z' + 1
        RET     NC
        SUB     'a' - 'A'
        RET

; HL source, DE destination, includes NUL.
CFG_COPY_Z:
.COPY:
        LD      A, (HL)
        LD      (DE), A
        INC     HL
        INC     DE
        OR      A
        JR      NZ, .COPY
        RET

CFG_FAIL_CODE:
        LD      (CFG_ERROR_CODE), A
        LD      HL, (CFG_LINE_NO)
        LD      (CFG_ERROR_LINE), HL
        SCF
        RET

CFG_VALUE_PTR:          DW      0
CFG_COPY_RULE:          DB      0
CFG_COPY_LEFT:          DB      0
CFG_COPY_COUNT:         DB      0
CFG_DIGIT:              DB      0
CFG_FILE_NAME:          DB      "WEATHER.CFG", 0
CFG_DEFAULT_HOST:       DB      "go.sprinter.ru", 0
CFG_DEFAULT_PORT:       DB      "70", 0
CFG_DEFAULT_SELECTOR:   DB      "/weather/zx", 0
CFG_KEY_HOST:           DB      "HOST", 0
CFG_KEY_PORT:           DB      "PORT", 0
CFG_KEY_SELECTOR:       DB      "SELECTOR", 0
CFG_KEY_LOCATION:       DB      "LOCATION", 0
