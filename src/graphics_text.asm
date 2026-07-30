; Small text-only error layer used by WEATHER.EXE before the graphics runtime
; is available.  The console frontend keeps the richer text_ui.asm renderer.

TEXT_RENDER_SERVICE_ERROR:
        LD      HL, MSG_SERVICE_ERROR
        CALL    PUTS
        LD      HL, WX1_SERVICE_CODE
        JP      PUTS_LN

TEXT_RENDER_WX1_ERROR:
        LD      HL, MSG_WX1_ERROR
        CALL    PUTS_LN
        LD      HL, MSG_WX1_LINE
        CALL    PUTS
        LD      A, (WX1_ERROR_LINE)
        CALL    PUT_HEX8
        LD      HL, MSG_WX1_CODE
        CALL    PUTS
        LD      A, (WX1_ERROR_CODE)
        CALL    PUT_HEX8
        JP      CRLF

TEXT_RENDER_PROMPT:
        CALL    CRLF
        LD      HL, MSG_RETRY_PROMPT
        JP      PUTS_LN
