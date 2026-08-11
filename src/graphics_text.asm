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

; DE direction degrees -> HL CP866 compass sector.
GRAPHICS_DIRECTION:
        EX      DE, HL
        LD      DE, 22
        ADD     HL, DE
        LD      B, 0
.DIVIDE:
        LD      DE, 45
        OR      A
        SBC     HL, DE
        JR      C, .DONE
        INC     B
        JR      .DIVIDE
.DONE:
        LD      A, B
        AND     7
        ADD     A, A
        LD      E, A
        LD      D, 0
        LD      HL, GRAPHICS_DIRECTION_TABLE
        ADD     HL, DE
        LD      E, (HL)
        INC     HL
        LD      D, (HL)
        EX      DE, HL
        RET

; A WMO code -> HL CP866 description.
GRAPHICS_WMO_DESCRIPTION:
        OR      A
        LD      HL, MSG_WMO_CLEAR
        RET     Z
        CP      1
        LD      HL, MSG_WMO_MAINLY_CLEAR
        RET     Z
        CP      2
        LD      HL, MSG_WMO_PARTLY_CLOUDY
        RET     Z
        CP      3
        LD      HL, MSG_WMO_OVERCAST
        RET     Z
        CP      45
        JR      Z, .FOG
        CP      48
        JR      Z, .FOG
        CP      51
        JR      C, .UNKNOWN
        CP      56
        JR      C, .DRIZZLE
        CP      58
        JR      C, .FREEZING_DRIZZLE
        CP      61
        JR      C, .UNKNOWN
        CP      66
        JR      C, .RAIN
        CP      68
        JR      C, .FREEZING_RAIN
        CP      71
        JR      C, .UNKNOWN
        CP      76
        JR      C, .SNOW
        CP      78
        JR      C, .SNOW_GRAINS
        CP      80
        JR      C, .UNKNOWN
        CP      83
        JR      C, .RAIN_SHOWERS
        CP      87
        JR      C, .SNOW_SHOWERS
        CP      95
        JR      C, .UNKNOWN
        CP      100
        LD      HL, MSG_WMO_THUNDERSTORM
        RET     C
.UNKNOWN:
        LD      HL, MSG_WMO_UNKNOWN
        RET
.FOG:  LD      HL, MSG_WMO_FOG
        RET
.DRIZZLE:
        LD      HL, MSG_WMO_DRIZZLE
        RET
.FREEZING_DRIZZLE:
        LD      HL, MSG_WMO_FREEZING_DRIZZLE
        RET
.RAIN: LD      HL, MSG_WMO_RAIN
        RET
.FREEZING_RAIN:
        LD      HL, MSG_WMO_FREEZING_RAIN
        RET
.SNOW: LD      HL, MSG_WMO_SNOW
        RET
.SNOW_GRAINS:
        LD      HL, MSG_WMO_SNOW_GRAINS
        RET
.RAIN_SHOWERS:
        LD      HL, MSG_WMO_RAIN_SHOWERS
        RET
.SNOW_SHOWERS:
        LD      HL, MSG_WMO_SNOW_SHOWERS
        RET

GRAPHICS_DIRECTION_TABLE:
        DW      MSG_DIR_N, MSG_DIR_NE, MSG_DIR_E, MSG_DIR_SE
        DW      MSG_DIR_S, MSG_DIR_SW, MSG_DIR_W, MSG_DIR_NW
