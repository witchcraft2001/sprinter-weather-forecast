        DEVICE  NOSLOT64K
        ORG     0000h
        JP      START

        INCLUDE "harness.inc"

        DEFINE  WEATHER_GRAPHICS

WX1_LINE_BUFFER         EQU 07000h
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
WX1_STAGE_MODEL         EQU 07400h
WX1_MODEL               EQU 07600h
GRAPHICS_SHOWN          EQU 07800h

        MODULE  MAIN
        INCLUDE "wx1.asm"
        ENDMODULE

START:
        LD      SP, 0FF00h
        CALL    T_BEGIN
        LD      HL, WX1_MODEL
        LD      DE, WX1_MODEL + 1
        LD      BC, MAIN.WM_MODEL_SIZE - 1
        LD      (HL), 0A5h
        LDIR
        LD      A, 1
        LD      (GRAPHICS_SHOWN), A
        CALL    MAIN.WX1_RESET

        LD      HL, WX1_MODEL
        LD      BC, MAIN.WM_MODEL_SIZE
.MODEL:
        LD      A, (HL)
        CP      0A5h
        JR      NZ, .MODEL_FAIL
        INC     HL
        DEC     BC
        LD      A, B
        OR      C
        JR      NZ, .MODEL
        JR      .SHOWN
.MODEL_FAIL:
        OR      1
        LD      A, 1
        CALL    T_EXPECT_Z
.SHOWN:
        LD      A, (GRAPHICS_SHOWN)
        CP      1
        LD      A, 2
        CALL    T_EXPECT_Z
        CALL    T_END
        HALT
