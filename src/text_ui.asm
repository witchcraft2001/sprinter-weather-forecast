; Text-only WeatherModel renderer. Included inside MODULE MAIN after wx1.asm.

; Print a complete validated forecast. Network/DLL cleanup must have completed.
TEXT_RENDER_FORECAST:
        LD      HL, MSG_FORECAST
        CALL    PUTS_LN
        LD      HL, MSG_LOCATION
        CALL    PUTS
        LD      HL, WX1_MODEL + WM_LOCATION
        CALL    TEXT_PUTS_TRUNC25
        LD      HL, MSG_COMMA_SPACE
        CALL    PUTS
        LD      HL, WX1_MODEL + WM_COUNTRY
        CALL    PUTS_LN

        LD      HL, MSG_UPDATED
        CALL    PUTS
        LD      HL, WX1_MODEL + WM_CURRENT
        CALL    TEXT_PRINT_DATE
        LD      A, ' '
        CALL    PUT_CHAR
        LD      HL, WX1_MODEL + WM_CURRENT + WC_HOUR
        CALL    TEXT_PRINT_TIME
        CALL    CRLF

        LD      HL, MSG_NOW
        CALL    PUTS
        LD      DE, (WX1_MODEL + WM_CURRENT + WC_TEMPERATURE)
        CALL    TEXT_PRINT_SIGNED_TENTHS
        LD      HL, MSG_CELSIUS
        CALL    PUTS
        LD      HL, MSG_FEELS
        CALL    PUTS
        LD      DE, (WX1_MODEL + WM_CURRENT + WC_APPARENT)
        CALL    TEXT_PRINT_SIGNED_TENTHS
        LD      HL, MSG_CELSIUS
        CALL    PUTS_LN

        LD      A, (WX1_MODEL + WM_CURRENT + WC_CODE)
        CALL    TEXT_WMO_DESCRIPTION
        CALL    PUTS
        LD      HL, MSG_WMO_OPEN
        CALL    PUTS
        LD      A, (WX1_MODEL + WM_CURRENT + WC_CODE)
        LD      E, A
        LD      D, 0
        CALL    TEXT_PRINT_U16
        LD      HL, MSG_WMO_CLOSE
        CALL    PUTS_LN

        LD      HL, MSG_HUMIDITY
        CALL    PUTS
        LD      A, (WX1_MODEL + WM_CURRENT + WC_HUMIDITY)
        LD      E, A
        LD      D, 0
        CALL    TEXT_PRINT_U16
        LD      HL, MSG_PERCENT
        CALL    PUTS_LN

        LD      HL, MSG_WIND
        CALL    PUTS
        LD      DE, (WX1_MODEL + WM_CURRENT + WC_WIND)
        CALL    TEXT_PRINT_UNSIGNED_TENTHS
        LD      HL, MSG_METERS_PER_SECOND
        CALL    PUTS
        LD      A, ','
        CALL    PUT_CHAR
        LD      A, ' '
        CALL    PUT_CHAR
        LD      DE, (WX1_MODEL + WM_CURRENT + WC_DIRECTION)
        CALL    TEXT_DIRECTION
        CALL    PUTS_LN
        CALL    CRLF

        LD      IX, WX1_MODEL + WM_DAYS
        LD      A, (WX1_MODEL + WM_DAY_COUNT)
        LD      (TEXT_DAYS_LEFT), A
.DAY_LOOP:
        PUSH    IX
        POP     HL
        CALL    TEXT_PRINT_DATE
        LD      A, ':'
        CALL    PUT_CHAR
        LD      A, ' '
        CALL    PUT_CHAR
        LD      E, (IX + WD_MIN)
        LD      D, (IX + WD_MIN + 1)
        CALL    TEXT_PRINT_SIGNED_TENTHS
        LD      HL, MSG_RANGE
        CALL    PUTS
        LD      E, (IX + WD_MAX)
        LD      D, (IX + WD_MAX + 1)
        CALL    TEXT_PRINT_SIGNED_TENTHS
        LD      HL, MSG_CELSIUS
        CALL    PUTS_LN

        LD      A, (IX + WD_CODE)
        CALL    TEXT_WMO_DESCRIPTION
        CALL    PUTS
        LD      HL, MSG_WMO_OPEN
        CALL    PUTS
        LD      A, (IX + WD_CODE)
        LD      E, A
        LD      D, 0
        CALL    TEXT_PRINT_U16
        LD      HL, MSG_WMO_CLOSE
        CALL    PUTS
        LD      HL, MSG_PRECIPITATION
        CALL    PUTS
        LD      A, (IX + WD_PRECIPITATION)
        LD      E, A
        LD      D, 0
        CALL    TEXT_PRINT_U16
        LD      HL, MSG_PERCENT
        CALL    PUTS_LN

        LD      HL, MSG_WIND_MAX
        CALL    PUTS
        LD      E, (IX + WD_WIND)
        LD      D, (IX + WD_WIND + 1)
        CALL    TEXT_PRINT_UNSIGNED_TENTHS
        LD      HL, MSG_METERS_PER_SECOND
        CALL    PUTS_LN

        LD      DE, WM_DAY_SIZE
        ADD     IX, DE
        LD      A, (TEXT_DAYS_LEFT)
        DEC     A
        LD      (TEXT_DAYS_LEFT), A
        JP      NZ, .DAY_LOOP

        LD      HL, MSG_SOURCE
        CALL    PUTS
        LD      HL, WX1_MODEL + WM_SOURCE
        CALL    PUTS_LN
        LD      HL, WX1_MODEL + WM_SOURCE_URL
        CALL    TEXT_PUTS_WRAP39
        RET

; Display known weather errors. Unknown server codes remain visible.
TEXT_RENDER_SERVICE_ERROR:
        LD      HL, MSG_SERVICE_ERROR
        CALL    PUTS
        LD      HL, WX1_SERVICE_CODE
        CALL    PUTS_LN
        LD      HL, WX1_SERVICE_CODE
        LD      DE, TEXT_ERR_BAD_LOCATION
        CALL    TEXT_STREQ
        JR      Z, .BAD_LOCATION
        LD      HL, WX1_SERVICE_CODE
        LD      DE, TEXT_ERR_NOT_FOUND
        CALL    TEXT_STREQ
        JR      Z, .NOT_FOUND
        LD      HL, WX1_SERVICE_CODE
        LD      DE, TEXT_ERR_GEO
        CALL    TEXT_STREQ
        JR      Z, .GEO
        LD      HL, WX1_SERVICE_CODE
        LD      DE, TEXT_ERR_WEATHER
        CALL    TEXT_STREQ
        RET     NZ
        LD      HL, MSG_SERVICE_WEATHER
        JP      PUTS_LN
.BAD_LOCATION:
        LD      HL, MSG_SERVICE_BAD_LOCATION
        JP      PUTS_LN
.NOT_FOUND:
        LD      HL, MSG_SERVICE_NOT_FOUND
        JP      PUTS_LN
.GEO:
        LD      HL, MSG_SERVICE_GEO
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

; HL points to [year:u16, month:u8, day:u8].
TEXT_PRINT_DATE:
        LD      E, (HL)
        INC     HL
        LD      D, (HL)
        PUSH    HL
        CALL    TEXT_PRINT_U16
        POP     HL
        INC     HL
        LD      A, '.'
        CALL    PUT_CHAR
        LD      A, (HL)
        CALL    TEXT_PRINT_2
        INC     HL
        LD      A, '.'
        CALL    PUT_CHAR
        LD      A, (HL)
        JP      TEXT_PRINT_2

; HL points to hour, minute.
TEXT_PRINT_TIME:
        LD      A, (HL)
        CALL    TEXT_PRINT_2
        LD      A, ':'
        CALL    PUT_CHAR
        INC     HL
        LD      A, (HL)
        JP      TEXT_PRINT_2

; A=0..99.
TEXT_PRINT_2:
        LD      B, 0
.TENS:
        CP      10
        JR      C, .OUT
        SUB     10
        INC     B
        JR      .TENS
.OUT:
        LD      C, A
        LD      A, B
        ADD     A, '0'
        CALL    PUT_CHAR
        LD      A, C
        ADD     A, '0'
        JP      PUT_CHAR

; DE signed tenths. A sign is always emitted.
TEXT_PRINT_SIGNED_TENTHS:
        BIT     7, D
        JR      Z, .POSITIVE
        LD      A, '-'
        CALL    PUT_CHAR
        LD      HL, 0
        OR      A
        SBC     HL, DE
        EX      DE, HL
        JP      TEXT_PRINT_UNSIGNED_TENTHS
.POSITIVE:
        LD      A, '+'
        CALL    PUT_CHAR
        JP      TEXT_PRINT_UNSIGNED_TENTHS

; DE unsigned tenths; print the decimal digit only when nonzero.
TEXT_PRINT_UNSIGNED_TENTHS:
        PUSH    DE
        POP     HL
        CALL    TEXT_DIV10
        LD      (TEXT_DECIMAL), A
        EX      DE, HL
        CALL    TEXT_PRINT_U16
        LD      A, (TEXT_DECIMAL)
        OR      A
        RET     Z
        PUSH    AF
        LD      A, '.'
        CALL    PUT_CHAR
        POP     AF
        ADD     A, '0'
        JP      PUT_CHAR

; DE unsigned integer.
TEXT_PRINT_U16:
        PUSH    IX
        LD      IX, TEXT_NUMBER_BUFFER + 7
        XOR     A
        LD      (IX + 0), A
        LD      A, D
        OR      E
        JR      NZ, .LOOP
        DEC     IX
        LD      A, '0'
        LD      (IX + 0), A
        JR      .OUT
.LOOP:
        PUSH    DE
        POP     HL
        CALL    TEXT_DIV10
        PUSH    HL
        POP     DE
        ADD     A, '0'
        DEC     IX
        LD      (IX + 0), A
        LD      A, D
        OR      E
        JR      NZ, .LOOP
.OUT:
        PUSH    IX
        POP     HL
        CALL    PUTS
        POP     IX
        RET

; HL dividend -> HL quotient, A remainder. Preserves IX.
TEXT_DIV10:
        PUSH    IX
        PUSH    HL
        POP     IX
        LD      HL, 0
        LD      DE, 0
        LD      B, 16
.LOOP:
        ADD     IX, IX
        RL      E
        RL      D
        ADD     HL, HL
        LD      A, D
        OR      A
        JR      NZ, .SUBTRACT
        LD      A, E
        CP      10
        JR      C, .NEXT
.SUBTRACT:
        OR      A
        LD      A, E
        SUB     10
        LD      E, A
        LD      A, D
        SBC     A, 0
        LD      D, A
        INC     HL
.NEXT:
        DJNZ    .LOOP
        LD      A, E
        POP     IX
        RET

; DE direction degrees -> HL CP866 sector ASCIIZ.
TEXT_DIRECTION:
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
        CP      8
        JR      C, .INDEX_OK
        XOR     A
.INDEX_OK:
        ADD     A, A
        LD      E, A
        LD      D, 0
        LD      HL, TEXT_DIRECTION_TABLE
        ADD     HL, DE
        LD      E, (HL)
        INC     HL
        LD      D, (HL)
        EX      DE, HL
        RET

; A WMO code -> HL description.
TEXT_WMO_DESCRIPTION:
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
        JR      C, .THUNDERSTORM
.UNKNOWN:
        LD      HL, MSG_WMO_UNKNOWN
        RET
.FOG:
        LD      HL, MSG_WMO_FOG
        RET
.DRIZZLE:
        LD      HL, MSG_WMO_DRIZZLE
        RET
.FREEZING_DRIZZLE:
        LD      HL, MSG_WMO_FREEZING_DRIZZLE
        RET
.RAIN:
        LD      HL, MSG_WMO_RAIN
        RET
.FREEZING_RAIN:
        LD      HL, MSG_WMO_FREEZING_RAIN
        RET
.SNOW:
        LD      HL, MSG_WMO_SNOW
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
.THUNDERSTORM:
        LD      HL, MSG_WMO_THUNDERSTORM
        RET

; Print up to 25 bytes, adding ... only when truncated.
TEXT_PUTS_TRUNC25:
        LD      B, 25
.LOOP:
        LD      A, (HL)
        OR      A
        RET     Z
        CALL    PUT_CHAR
        INC     HL
        DJNZ    .LOOP
        LD      A, (HL)
        OR      A
        RET     Z
        LD      HL, MSG_ELLIPSIS
        JP      PUTS

; Print an ASCIIZ field as 39-byte physical lines.
TEXT_PUTS_WRAP39:
        LD      B, 39
.LOOP:
        LD      A, (HL)
        OR      A
        RET     Z
        CALL    PUT_CHAR
        INC     HL
        DJNZ    .LOOP
        CALL    CRLF
        LD      B, 39
        JR      .LOOP

TEXT_STREQ:
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

MSG_COMMA_SPACE:        DB      ", ", 0
MSG_RANGE:              DB      "..", 0
MSG_ELLIPSIS:           DB      "...", 0
TEXT_ERR_BAD_LOCATION:  DB      "BAD_LOCATION", 0
TEXT_ERR_NOT_FOUND:     DB      "LOCATION_NOT_FOUND", 0
TEXT_ERR_GEO:           DB      "GEO_UNAVAILABLE", 0
TEXT_ERR_WEATHER:       DB      "WEATHER_UNAVAILABLE", 0
TEXT_DIRECTION_TABLE:
        DW      MSG_DIR_N, MSG_DIR_NE, MSG_DIR_E, MSG_DIR_SE
        DW      MSG_DIR_S, MSG_DIR_SW, MSG_DIR_W, MSG_DIR_NW
