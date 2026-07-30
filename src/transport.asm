; Bounded Gopher request/response transport. Included inside MODULE MAIN.

TST_NONE                EQU 0
TST_REQUEST             EQU 1
TST_CONNECT             EQU 2
TST_SEND                EQU 3
TST_RECV                EQU 4
TST_RESPONSE            EQU 5
TST_LIBMAN              EQU 6

TERR_SHORT_SEND         EQU 080h
TERR_IDLE_TIMEOUT        EQU 081h
TERR_DATA_LOST          EQU 082h
TERR_RESPONSE_OVERFLOW  EQU 083h
TERR_PREMATURE_CLOSE    EQU 084h
TERR_INVALID_RECV       EQU 085h
TERR_LIBMAN             EQU 086h

RESP_CONTINUE           EQU 0
RESP_COMPLETE           EQU 1

TRESP_NONE              EQU 0
TRESP_PARSER            EQU 1
TRESP_TRANSPORT         EQU 2

; Uses the selected, NETINIT-ed UNET DLL and the completed configuration.
; Out: CF=0 after a complete Gopher response; CF=1 with transport diagnostic.
GOPHER_FETCH:
        CALL    TRANSPORT_RESET
        CALL    GOPHER_BUILD_REQUEST
        JP      C, .FAIL

        IFDEF WEATHER_GRAPHICS
        LD      HL, MSG_GRAPHICS_CONNECT
        CALL    PUTS_LN
        ENDIF
        XOR     A
        LD      DE, CFG_HOST
        LD      IX, CFG_PORT
        LD      B, UNET_FN_CONNECT
        CALL    CALL_UNET
        JP      C, .LIBMAN_CONNECT
        OR      A
        JP      NZ, .UNET_CONNECT
        LD      A, (STATE_FLAGS)
        OR      FLAG_CHANNEL_OPEN
        LD      (STATE_FLAGS), A

        IFDEF WEATHER_GRAPHICS
        LD      HL, MSG_GRAPHICS_SENDING
        CALL    PUTS_LN
        ENDIF
        XOR     A
        LD      DE, REQUEST_BUFFER
        LD      IX, (REQUEST_SIZE)
        LD      B, UNET_FN_SEND
        CALL    CALL_UNET
        JP      C, .LIBMAN_SEND
        OR      A
        JP      NZ, .UNET_SEND
        PUSH    DE
        POP     HL
        LD      DE, (REQUEST_SIZE)
        OR      A
        SBC     HL, DE
        JR      Z, .SEND_OK
        LD      A, TST_SEND
        LD      B, TERR_SHORT_SEND
        JP      TRANSPORT_FAIL

.SEND_OK:
        IFDEF WEATHER_GRAPHICS
        LD      HL, MSG_GRAPHICS_SEND
        CALL    PUTS_LN
        ENDIF
.RECV_LOOP:
        XOR     A
        LD      DE, RECV_BUFFER
        LD      IX, RECV_BUFFER_SIZE
        LD      IY, 5000
        LD      B, UNET_FN_RECV
        CALL    CALL_UNET
        JP      C, .LIBMAN_RECV
        CP      NERR_OK
        JR      Z, .RECV_OK
        CP      NERR_CLOSED
        JR      Z, .RECV_CLOSED
        CP      NERR_CANCEL
        JP      Z, .UNET_RECV
        JP      .UNET_RECV

.RECV_OK:
        LD      (LAST_RECV_LENGTH), DE
        LD      HL, RECV_BUFFER_SIZE
        OR      A
        SBC     HL, DE
        JP      NC, .RECV_LENGTH_OK
        LD      A, TST_RECV
        LD      B, TERR_INVALID_RECV
        JP      TRANSPORT_FAIL
.RECV_LENGTH_OK:
        PUSH    DE
        PUSH    IX
        POP     HL
        BIT     2, L
        JR      NZ, .DATA_LOST
        POP     BC
        LD      A, B
        OR      C
        JR      Z, .IDLE
        LD      HL, RECV_BUFFER
        CALL    RESPONSE_FEED
        JR      C, .RESPONSE_ERROR
        CP      RESP_COMPLETE
        JP      Z, .SUCCESS
        XOR     A
        LD      (TRANSPORT_IDLE_COUNT), A
        JR      .RECV_LOOP
.DATA_LOST:
        POP     DE
        LD      A, TST_RECV
        LD      B, TERR_DATA_LOST
        JP      TRANSPORT_FAIL
.IDLE:
        LD      A, (TRANSPORT_IDLE_COUNT)
        INC     A
        LD      (TRANSPORT_IDLE_COUNT), A
        CP      2
        JR      C, .RECV_LOOP
        LD      A, TST_RECV
        LD      B, TERR_IDLE_TIMEOUT
        JP      TRANSPORT_FAIL

.RECV_CLOSED:
        PUSH    IX
        POP     HL
        BIT     2, L
        JR      NZ, .CLOSED_DATA_LOST
        LD      A, D
        OR      E
        JR      Z, .EOF
        PUSH    DE
        POP     BC
        LD      HL, RECV_BUFFER
        CALL    RESPONSE_FEED
        JR      C, .RESPONSE_ERROR
.EOF:
        CALL    RESPONSE_EOF
        JR      C, .RESPONSE_ERROR
        JR      .SUCCESS
.CLOSED_DATA_LOST:
        LD      A, TST_RECV
        LD      B, TERR_DATA_LOST
        JP      TRANSPORT_FAIL

.UNET_CONNECT:
        LD      B, A
        LD      A, TST_CONNECT
        JR      .UNET_FAILURE
.UNET_SEND:
        LD      B, A
        LD      A, TST_SEND
        JR      .UNET_FAILURE
.UNET_RECV:
        LD      B, A
        LD      A, TST_RECV
.UNET_FAILURE:
        CALL    TRANSPORT_FAIL
        CALL    TRANSPORT_CAPTURE_DETAIL
        SCF
        RET
.LIBMAN_CONNECT:
        LD      A, TST_LIBMAN
        JR      .LIBMAN_FAILURE
.LIBMAN_SEND:
        LD      A, TST_LIBMAN
        JR      .LIBMAN_FAILURE
.LIBMAN_RECV:
        LD      A, TST_LIBMAN
.LIBMAN_FAILURE:
        LD      B, TERR_LIBMAN
        JP      TRANSPORT_FAIL
.RESPONSE_ERROR:
        LD      A, (TRANSPORT_RESPONSE_ERROR)
        CP      TRESP_PARSER
        JR      NZ, .RESPONSE_TRANSPORT_CODE
        LD      A, (WX1_ERROR_CODE)
        OR      A
        JR      NZ, .RESPONSE_CODE_READY
        LD      A, WXE_PREMATURE_EOF
        JR      .RESPONSE_CODE_READY
.RESPONSE_TRANSPORT_CODE:
        LD      A, TERR_RESPONSE_OVERFLOW
.RESPONSE_CODE_READY:
        LD      B, A
        LD      A, TST_RESPONSE
        JP      TRANSPORT_FAIL
.SUCCESS:
        OR      A
        RET
.FAIL:
        SCF
        RET

; Build selector[ TAB location ] CR LF. The config parser already checked the
; upper bound; this routine remains bounded so future callers cannot bypass it.
GOPHER_BUILD_REQUEST:
        LD      HL, CFG_SELECTOR
        LD      DE, REQUEST_BUFFER
        CALL    REQUEST_COPY_Z_EXCEPT_NUL
        JR      C, .OVERFLOW
        LD      A, (CFG_LOCATION)
        OR      A
        JR      Z, .CRLF
        LD      A, 9
        CALL    REQUEST_PUT_A
        JR      C, .OVERFLOW
        LD      HL, CFG_LOCATION
        CALL    REQUEST_COPY_Z_EXCEPT_NUL
        JR      C, .OVERFLOW
.CRLF:
        LD      A, 13
        CALL    REQUEST_PUT_A
        JR      C, .OVERFLOW
        LD      A, 10
        CALL    REQUEST_PUT_A
        JR      C, .OVERFLOW
        XOR     A
        LD      (DE), A
        LD      HL, DE
        LD      DE, REQUEST_BUFFER
        OR      A
        SBC     HL, DE
        LD      (REQUEST_SIZE), HL
        OR      A
        RET
.OVERFLOW:
        LD      A, TST_REQUEST
        LD      B, TERR_RESPONSE_OVERFLOW
        JP      TRANSPORT_FAIL

REQUEST_COPY_Z_EXCEPT_NUL:
        LD      A, (HL)
        OR      A
        RET     Z
        CALL    REQUEST_PUT_A
        RET     C
        INC     HL
        JR      REQUEST_COPY_Z_EXCEPT_NUL

; A byte goes to DE; DE advances. CF means REQUEST_MAX bytes would be crossed.
REQUEST_PUT_A:
        PUSH    HL
        LD      HL, DE
        LD      BC, REQUEST_BUFFER + REQUEST_MAX
        OR      A
        SBC     HL, BC
        POP     HL
        JR      NC, .FULL
        LD      (DE), A
        INC     DE
        OR      A
        RET
.FULL:
        SCF
        RET

TRANSPORT_RESET:
        CALL    WX1_RESET
        XOR     A
        LD      (TRANSPORT_STAGE), A
        LD      (TRANSPORT_CODE), A
        LD      (TRANSPORT_RESPONSE_ERROR), A
        LD      (TRANSPORT_HAS_DETAIL), A
        LD      A, 0FFh
        LD      (TRANSPORT_DETAIL_STATUS), A
        XOR     A
        LD      (TRANSPORT_IDLE_COUNT), A
        LD      (LAST_RECV_LENGTH), A
        LD      (LAST_RECV_LENGTH + 1), A
        LD      (RESPONSE_SIZE), A
        LD      (RESPONSE_SIZE + 1), A
        LD      (RESPONSE_TAIL), A
        LD      (RESPONSE_TAIL + 1), A
        LD      (RESPONSE_TAIL + 2), A
        LD      (RESPONSE_TAIL + 3), A
        LD      (TRANSPORT_DETAIL), A
        RET

; HL points to received data, BC is its byte count.
; A=RESP_CONTINUE/RESP_COMPLETE, CF on response/parser error.
RESPONSE_FEED:
        LD      (TRANSPORT_INPUT_PTR), HL
        LD      (TRANSPORT_INPUT_SIZE), BC
        LD      HL, (RESPONSE_SIZE)
        ADD     HL, BC
        JR      C, .OVERFLOW
        PUSH    HL
        LD      DE, RESPONSE_MAX
        OR      A
        SBC     HL, DE
        POP     HL
        JR      C, .SIZE_OK
        JR      Z, .SIZE_OK
        JR      .OVERFLOW
.SIZE_OK:
        LD      (RESPONSE_SIZE), HL
        LD      HL, (TRANSPORT_INPUT_PTR)
        LD      BC, (TRANSPORT_INPUT_SIZE)
        CALL    RESPONSE_TAIL_FEED
        LD      HL, (TRANSPORT_INPUT_PTR)
        LD      BC, (TRANSPORT_INPUT_SIZE)
        CALL    WX1_FEED
        JR      NC, .PARSED
        LD      A, TRESP_PARSER
        LD      (TRANSPORT_RESPONSE_ERROR), A
        SCF
        RET
.PARSED:
        OR      A
        JR      Z, .CONTINUE
        LD      A, RESP_COMPLETE
        OR      A
        RET
.CONTINUE:
        XOR     A
        RET
.OVERFLOW:
        LD      A, TRESP_TRANSPORT
        LD      (TRANSPORT_RESPONSE_ERROR), A
        SCF
        RET

; Keep only the final four bytes for diagnostics; raw WX1 is parsed in flight.
RESPONSE_TAIL_FEED:
.BYTE:
        LD      A, B
        OR      C
        RET     Z
        LD      A, (HL)
        LD      D, A
        LD      A, (RESPONSE_TAIL + 1)
        LD      (RESPONSE_TAIL), A
        LD      A, (RESPONSE_TAIL + 2)
        LD      (RESPONSE_TAIL + 1), A
        LD      A, (RESPONSE_TAIL + 3)
        LD      (RESPONSE_TAIL + 2), A
        LD      A, D
        LD      (RESPONSE_TAIL + 3), A
        INC     HL
        DEC     BC
        JR      .BYTE

RESPONSE_EOF:
        CALL    WX1_EOF
        RET     NC
        LD      A, TRESP_PARSER
        LD      (TRANSPORT_RESPONSE_ERROR), A
        SCF
        RET

; A=stage, B=code. The first failure is retained until the next attempt.
TRANSPORT_FAIL:
        LD      (TRANSPORT_STAGE), A
        LD      A, B
        LD      (TRANSPORT_CODE), A
        LD      HL, (RESPONSE_SIZE)
        LD      (TRANSPORT_RESPONSE_SIZE), HL
        SCF
        RET

TRANSPORT_CAPTURE_DETAIL:
        XOR     A
        LD      (TRANSPORT_DETAIL), A
        LD      DE, TRANSPORT_DETAIL
        LD      IX, TRANSPORT_DETAIL_SIZE
        LD      B, UNET_FN_LASTERR
        CALL    CALL_UNET
        JR      C, .DONE
        LD      (TRANSPORT_DETAIL_STATUS), A
        OR      A
        JR      NZ, .DONE
        LD      A, (TRANSPORT_DETAIL)
        OR      A
        RET     Z
        LD      A, 1
        LD      (TRANSPORT_HAS_DETAIL), A
.DONE:
        RET

TRANSPORT_IDLE_COUNT:  DB      0
