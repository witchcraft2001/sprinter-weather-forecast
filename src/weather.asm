; ============================================================================
; WEATHER.EXE - text WX1 forecast client for Sprinter DSS.
;
; Reads NET from the DSS environment, selects a prebuilt UNET backend, loads
; it through current libman, validates ABI/capabilities, receives WX1 and
; renders a validated text forecast after network cleanup.
; ============================================================================

EXE_VERSION             EQU 1
EXE_HEADER_SIZE         EQU 0200h
EXE_LOAD_ADDRESS        EQU 08100h

FLAG_DLL_LOADED         EQU 00000001b
FLAG_NET_INITIALIZED    EQU 00000010b
FLAG_CHANNEL_OPEN        EQU 00000100b

BACKEND_NONE            EQU 0
BACKEND_WIFI            EQU 1
BACKEND_RTL             EQU 2

EXIT_OK                 EQU 0
EXIT_DLL                EQU 2
EXIT_NETWORK            EQU 3
EXIT_CONFIG             EQU 4
EXIT_TRANSPORT          EQU 5

        DEVICE  NOSLOT64K

        INCLUDE "dss.inc"
        INCLUDE "unet.inc"

        DEFINE  LIBMAN_MAX_LIBS 1
        ; Keep the successful loader path compact, but publish the exact
        ; loading stage and a DLL INIT status when a real machine rejects it.
        DEFINE  LIBMAN_DIAGNOSTICS
        DEFINE  LIBMAN_NO_LEGACY_API

        MODULE  MAIN

; DSS EXE v1 header. The code starts at file offset 0x200 and is loaded into
; WIN2 at 0x8100. OFFCOD is a little-endian 32-bit value.
        ORG     EXE_LOAD_ADDRESS - EXE_HEADER_SIZE
EXE_HEADER:
        DB      "EXE", EXE_VERSION
        DD      EXE_HEADER_SIZE
        DW      0                       ; no primary loader
        DS      6, 0                    ; reserved
        DW      START                   ; load address
        DW      START                   ; entry point
        DW      STACK_TOP               ; initial stack
        DB      0                       ; unused byte at offset 22
        DS      EXE_HEADER_SIZE - ($ - EXE_HEADER), 0

        ASSERT  $ = EXE_LOAD_ADDRESS
        ORG     EXE_LOAD_ADDRESS

START:
        LD      SP, STACK_TOP
        CALL    CLEAR_BSS

        LD      HL, MSG_BANNER
        CALL    PUTS_LN
        LD      HL, MSG_STAGE
        CALL    PUTS_LN

ATTEMPT_START:
        CALL    ATTEMPT_RESET
        CALL    CONFIG_LOAD
        JP      C, ERROR_CONFIG_FILE
        LD      HL, (CFG_WARNING_LINE)
        LD      A, H
        OR      L
        JR      Z, .NO_CFG_WARNING
        LD      HL, MSG_CONFIG_WARNING
        CALL    PUTS
        LD      A, (CFG_WARNING_LINE + 1)
        CALL    PUT_HEX8
        LD      A, (CFG_WARNING_LINE)
        CALL    PUT_HEX8
        CALL    CRLF
.NO_CFG_WARNING:

        CALL    SELECT_BACKEND
        JP      C, ERROR_CONFIG

        LD      HL, MSG_LOADING
        CALL    PUTS
        LD      HL, (DLL_NAME_PTR)
        CALL    PUTS_LN

        LD      HL, (DLL_NAME_PTR)
        LD      A, 1                    ; UNET owns WIN1 (0x4000..0x7fff)
        CALL    LIBMAN.l_load
        JP      C, ERROR_LOAD

        LD      (DLL_HANDLE), HL
        LD      A, (STATE_FLAGS)
        OR      FLAG_DLL_LOADED
        LD      (STATE_FLAGS), A

        LD      HL, (DLL_HANDLE)
        LD      DE, DLL_INFO
        CALL    LIBMAN.l_info
        JP      C, ERROR_INFO
        CALL    VALIDATE_DLL_INFO
        JP      C, ERROR_INFO_NAME

        LD      HL, MSG_DLL
        CALL    PUTS
        LD      HL, DLL_INFO + 16
        CALL    PUTS_LN

        LD      B, UNET_FN_GETCAPS
        CALL    CALL_UNET
        JP      C, ERROR_CALL
        OR      A
        JP      NZ, ERROR_UNET_STATUS
        LD      (UNET_CAPS), DE
        LD      (UNET_ABI), IX

        LD      A, (UNET_ABI + 1)
        CP      HIGH UNET_ABI_VERSION
        JP      NZ, ERROR_ABI

        LD      A, (UNET_CAPS)
        AND     UNET_CAP_TCP
        JP      Z, ERROR_TCP_CAP

        LD      A, UNET_OPT_CANCELKEYS
        LD      DE, 1
        LD      B, UNET_FN_SETOPT
        CALL    CALL_UNET
        JP      C, ERROR_CALL
        OR      A
        JP      NZ, ERROR_UNET_STATUS

        ; STATUS(0xff) is intentionally non-hardware: it checks that the
        ; backend-specific environment has been published before NETINIT.
        LD      A, 0FFh
        LD      B, UNET_FN_STATUS
        CALL    CALL_UNET
        JP      C, ERROR_CALL
        LD      (LAST_UNET_STATUS), A
        CP      NERR_OK
        JR      Z, .STATUS_ACCEPTED
        CP      NERR_NONET
        JP      NZ, ERROR_UNET_STATUS

.STATUS_ACCEPTED:
        LD      B, UNET_FN_NETINIT
        CALL    CALL_UNET
        JP      C, ERROR_CALL
        OR      A
        JP      NZ, ERROR_NETINIT

        LD      A, (STATE_FLAGS)
        OR      FLAG_NET_INITIALIZED
        LD      (STATE_FLAGS), A

        LD      HL, MSG_READY
        CALL    PUTS
        LD      HL, DLL_INFO + 16
        CALL    PUTS_LN
        LD      HL, MSG_LOADING_WEATHER
        CALL    PUTS_LN

        CALL    GOPHER_FETCH
        JP      C, ERROR_TRANSPORT

        ; The ESP backend may still be draining UART data.  Finish the UNET
        ; session before any potentially slow console output.
        CALL    CLEANUP

        LD      A, (WX1_RESULT)
        CP      WX1_SERVICE_ERROR
        JP      Z, ERROR_SERVICE
        CP      WX1_OK
        JP      NZ, ERROR_WX1
        CALL    TEXT_RENDER_FORECAST

        LD      B, EXIT_OK
        JP      ATTEMPT_FINISH

; ---------------------------------------------------------------------------
; Environment/backend selection.
; Out: CF=0 and DLL_NAME_PTR/BACKEND selected, CF=1 otherwise.
; ---------------------------------------------------------------------------
SELECT_BACKEND:
        XOR     A
        LD      (ENV_VALUE), A
        LD      HL, ENV_NET
        LD      DE, ENV_VALUE
        LD      B, ENV_GET
        LD      C, DSS_ENVIRON
        RST     DSS
        JR      C, .NOT_CONFIGURED
        OR      A
        JR      Z, .NOT_CONFIGURED

        LD      A, (ENV_VALUE)
        OR      A
        JR      Z, .NOT_CONFIGURED

        LD      HL, ENV_VALUE
        LD      DE, VALUE_WIFI
        CALL    STREQ
        JR      Z, .WIFI

        LD      HL, ENV_VALUE
        LD      DE, VALUE_RTL
        CALL    STREQ
        JR      Z, .RTL

        LD      HL, MSG_NET_UNKNOWN
        CALL    PUTS
        LD      HL, ENV_VALUE
        CALL    PUTS_LN
        SCF
        RET

.WIFI:
        LD      A, BACKEND_WIFI
        LD      (BACKEND), A
        LD      HL, DLL_ESP
        LD      (DLL_NAME_PTR), HL
        LD      HL, MSG_BACKEND_WIFI
        CALL    PUTS_LN
        OR      A
        RET

.RTL:
        LD      A, BACKEND_RTL
        LD      (BACKEND), A
        LD      HL, DLL_RTL
        LD      (DLL_NAME_PTR), HL
        LD      HL, MSG_BACKEND_RTL
        CALL    PUTS_LN
        OR      A
        RET

.NOT_CONFIGURED:
        SCF
        RET

; Compare ASCIIZ HL and DE. Returns Z when equal.
STREQ:
        LD      A, (DE)
        LD      C, A
        LD      A, (HL)
        CP      C
        RET     NZ
        AND     A
        RET     Z
        INC     HL
        INC     DE
        JR      STREQ

; Call the currently loaded DLL. Carry denotes a libman dispatcher failure;
; the UNET function's status remains in A and must be checked separately.
CALL_UNET:
        LD      HL, (DLL_HANDLE)
        JP      LIBMAN.l_call

; Confirm that the library selected by NET has the corresponding L1 name.
; The version suffix is intentionally not fixed here; the pinned file hash is
; the build-time identity, while runtime accepts a compatible package update.
VALIDATE_DLL_INFO:
        LD      A, (BACKEND)
        CP      BACKEND_WIFI
        LD      DE, INFO_ESP_TAG
        JR      Z, .COMPARE
        CP      BACKEND_RTL
        LD      DE, INFO_RTL_TAG
        JR      NZ, .FAIL
.COMPARE:
        LD      HL, DLL_INFO + 16
.LOOP:
        LD      A, (DE)
        OR      A
        RET     Z
        CP      (HL)
        JR      NZ, .FAIL
        INC     DE
        INC     HL
        JR      .LOOP
.FAIL:
        SCF
        RET

; ---------------------------------------------------------------------------
; Errors.
; ---------------------------------------------------------------------------
ERROR_CONFIG:
        CALL    CLEANUP
        LD      HL, MSG_NET_NOT_CONFIGURED
        CALL    PUTS_LN
        CALL    PRINT_CONFIG_HINT
        LD      B, EXIT_CONFIG
        JP      ATTEMPT_FINISH

ERROR_CONFIG_FILE:
        CALL    CLEANUP
        LD      HL, MSG_CONFIG_ERROR
        CALL    PUTS
        LD      A, (CFG_ERROR_LINE + 1)
        CALL    PUT_HEX8
        LD      A, (CFG_ERROR_LINE)
        CALL    PUT_HEX8
        LD      HL, MSG_CONFIG_CODE
        CALL    PUTS
        LD      A, (CFG_ERROR_CODE)
        CALL    PUT_HEX8
        CALL    CRLF
        LD      B, EXIT_CONFIG
        JP      ATTEMPT_FINISH

ERROR_LOAD:
        CALL    CLEANUP
        LD      HL, MSG_LOAD_ERROR
        CALL    PUTS
        LD      HL, (DLL_NAME_PTR)
        CALL    PUTS_LN
        LD      HL, MSG_REASON
        CALL    PUTS
        LD      A, (LIBMAN.l_reason)
        CALL    PUT_HEX8
        LD      HL, MSG_DSS_CODE
        CALL    PUTS
        LD      A, (LIBMAN.l_dss_error)
        CALL    PUT_HEX8
        LD      HL, MSG_LOAD_STAGE
        CALL    PUTS
        LD      A, (LIBMAN.l_load_stage)
        CALL    PUT_HEX8
        LD      HL, MSG_INIT_STATUS
        CALL    PUTS
        LD      A, (LIBMAN.l_init_status)
        CALL    PUT_HEX8
        CALL    CRLF
        LD      HL, MSG_DLL_HINT
        CALL    PUTS_LN
        LD      B, EXIT_DLL
        JP      ATTEMPT_FINISH

ERROR_INFO:
        CALL    CLEANUP
        LD      HL, MSG_INFO_ERROR
        CALL    PUTS_LN
        LD      B, EXIT_DLL
        JP      ATTEMPT_FINISH

ERROR_INFO_NAME:
        CALL    CLEANUP
        LD      HL, MSG_INFO_NAME_ERROR
        CALL    PUTS
        LD      HL, DLL_INFO + 16
        CALL    PUTS_LN
        LD      B, EXIT_DLL
        JP      ATTEMPT_FINISH

ERROR_ABI:
        CALL    CLEANUP
        LD      HL, MSG_ABI_ERROR
        CALL    PUTS
        LD      DE, (UNET_ABI)
        CALL    PUT_HEX16
        CALL    CRLF
        LD      B, EXIT_DLL
        JP      ATTEMPT_FINISH

ERROR_TCP_CAP:
        CALL    CLEANUP
        LD      HL, MSG_TCP_ERROR
        CALL    PUTS_LN
        LD      B, EXIT_DLL
        JP      ATTEMPT_FINISH

ERROR_CALL:
        CALL    CLEANUP
        LD      HL, MSG_CALL_ERROR
        CALL    PUTS_LN
        LD      B, EXIT_DLL
        JP      ATTEMPT_FINISH

ERROR_UNET_STATUS:
        PUSH    AF
        CALL    CLEANUP
        POP     AF
        LD      (LAST_UNET_STATUS), A
        LD      HL, MSG_UNET_ERROR
        CALL    PUTS
        LD      A, (LAST_UNET_STATUS)
        CALL    PUT_HEX8
        CALL    CRLF
        LD      B, EXIT_NETWORK
        JP      ATTEMPT_FINISH

ERROR_NETINIT:
        PUSH    AF
        CALL    CLEANUP
        POP     AF
        LD      (LAST_UNET_STATUS), A
        CP      NERR_NONET
        JR      Z, .CONFIG
        CP      NERR_HW
        JR      Z, .HARDWARE
        CP      NERR_BUSY
        JR      Z, .BUSY

        LD      HL, MSG_NETINIT_ERROR
        CALL    PUTS
        LD      A, (LAST_UNET_STATUS)
        CALL    PUT_HEX8
        CALL    CRLF
        LD      B, EXIT_NETWORK
        JP      ATTEMPT_FINISH

.CONFIG:
        LD      HL, MSG_BACKEND_NOT_CONFIGURED
        CALL    PUTS_LN
        CALL    PRINT_CONFIG_HINT
        LD      B, EXIT_CONFIG
        JP      ATTEMPT_FINISH

.HARDWARE:
        LD      HL, MSG_HARDWARE_ERROR
        CALL    PUTS_LN
        CALL    PRINT_CONFIG_HINT
        LD      B, EXIT_DLL
        JP      ATTEMPT_FINISH

.BUSY:
        LD      HL, MSG_BUSY_ERROR
        CALL    PUTS_LN
        LD      B, EXIT_NETWORK
        JP      ATTEMPT_FINISH

ERROR_TRANSPORT:
        CALL    CLEANUP
        LD      A, (TRANSPORT_STAGE)
        CP      TST_RESPONSE
        JR      NZ, .TRANSPORT
        LD      A, (TRANSPORT_RESPONSE_ERROR)
        CP      TRESP_PARSER
        JR      NZ, .TRANSPORT
        CALL    TEXT_RENDER_WX1_ERROR
        LD      B, EXIT_TRANSPORT
        JP      ATTEMPT_FINISH
.TRANSPORT:
        LD      HL, MSG_TRANSPORT_ERROR
        CALL    PUTS_LN
        LD      HL, MSG_TRANSPORT_STAGE
        CALL    PUTS
        LD      A, (TRANSPORT_STAGE)
        CALL    PUT_HEX8
        LD      HL, MSG_TRANSPORT_CODE
        CALL    PUTS
        LD      A, (TRANSPORT_CODE)
        CALL    PUT_HEX8
        CALL    CRLF
        LD      HL, MSG_TRANSPORT_RESPONSE_SIZE
        CALL    PUTS
        LD      DE, (TRANSPORT_RESPONSE_SIZE)
        CALL    PUT_HEX16
        CALL    CRLF
        LD      HL, MSG_TRANSPORT_RECV_LENGTH
        CALL    PUTS
        LD      DE, (LAST_RECV_LENGTH)
        CALL    PUT_HEX16
        CALL    CRLF
        LD      HL, MSG_TRANSPORT_TAIL
        CALL    PUTS
        CALL    PRINT_RESPONSE_TAIL
        CALL    CRLF
        LD      A, (TRANSPORT_HAS_DETAIL)
        OR      A
        JR      Z, .DETAIL_STATUS
        LD      HL, MSG_TRANSPORT_DETAIL
        CALL    PUTS
        LD      HL, TRANSPORT_DETAIL
        CALL    PUTS_LN
.DETAIL_STATUS:
        LD      HL, MSG_TRANSPORT_DETAIL_STATUS
        CALL    PUTS
        LD      A, (TRANSPORT_DETAIL_STATUS)
        CALL    PUT_HEX8
        CALL    CRLF
        IFDEF   WEATHER_DEBUG_RAW
        LD      HL, MSG_DEBUG_REQUEST
        CALL    PUTS
        LD      HL, REQUEST_BUFFER
        CALL    PUTS_LN
        ENDIF
        LD      B, EXIT_TRANSPORT
        JP      ATTEMPT_FINISH

ERROR_SERVICE:
        CALL    TEXT_RENDER_SERVICE_ERROR
        LD      B, EXIT_TRANSPORT
        JP      ATTEMPT_FINISH

ERROR_WX1:
        CALL    TEXT_RENDER_WX1_ERROR
        LD      B, EXIT_TRANSPORT
        JP      ATTEMPT_FINISH

PRINT_CONFIG_HINT:
        LD      A, (BACKEND)
        CP      BACKEND_WIFI
        JR      Z, .WIFI
        CP      BACKEND_RTL
        JR      Z, .RTL
        LD      HL, MSG_HINT_BOTH
        JP      PUTS_LN
.WIFI:
        LD      HL, MSG_HINT_WIFI
        JP      PUTS_LN
.RTL:
        LD      HL, MSG_HINT_RTL
        JP      PUTS_LN

        INCLUDE "config.asm"
        INCLUDE "wx1.asm"
        INCLUDE "text_ui.asm"
        INCLUDE "transport.asm"

; ---------------------------------------------------------------------------
; Attempt lifecycle, idempotent cleanup and DSS exit.
; ---------------------------------------------------------------------------
ATTEMPT_RESET:
        ; ATTEMPT_FINISH always cleaned the preceding run. Clear only state
        ; that is deliberately re-discovered from CFG/ENV on every refresh.
        XOR     A
        LD      (BACKEND), A
        LD      (DLL_HANDLE), A
        LD      (DLL_HANDLE + 1), A
        LD      (DLL_NAME_PTR), A
        LD      (DLL_NAME_PTR + 1), A
        LD      (LAST_UNET_STATUS), A
        LD      (STATE_FLAGS), A
        CALL    WX1_RESET
        RET

; B is the exit category of the completed attempt. Retry reloads both CFG and
; NET, while Esc returns the category of an unrecovered error (or 0 on success).
ATTEMPT_FINISH:
        LD      A, B
        LD      (LAST_ATTEMPT_EXIT), A
        CALL    CLEANUP
        CALL    TEXT_RENDER_PROMPT
.WAIT:
        LD      C, DSS_KCLEAR
        RST     DSS
        LD      C, DSS_WAITKEY
        RST     DSS
        CP      27
        JR      Z, .EXIT
        CP      13
        JP      Z, ATTEMPT_START
        CP      'R'
        JP      Z, ATTEMPT_START
        CP      'r'
        JP      Z, ATTEMPT_START
        JR      .WAIT
.EXIT:
        LD      A, (LAST_ATTEMPT_EXIT)
        LD      B, A
        JP      EXIT_PROGRAM

EXIT_PROGRAM:
        LD      A, B
        LD      (EXIT_CODE), A
        CALL    CLEANUP
        LD      A, (EXIT_CODE)
        LD      B, A
        LD      C, DSS_EXIT
        RST     DSS
        RET                             ; defensive: DSS EXIT does not return

CLEANUP:
        LD      A, (STATE_FLAGS)
        AND     FLAG_CHANNEL_OPEN
        JR      Z, .NETDONE
        XOR     A
        LD      B, UNET_FN_CLOSE
        CALL    CALL_UNET               ; best effort during unwind
        LD      A, (STATE_FLAGS)
        AND     0FFh - FLAG_CHANNEL_OPEN
        LD      (STATE_FLAGS), A

.NETDONE:
        LD      A, (STATE_FLAGS)
        AND     FLAG_NET_INITIALIZED
        JR      Z, .FREE_DLL
        LD      B, UNET_FN_NETDONE
        CALL    CALL_UNET               ; best effort during unwind
        LD      A, (STATE_FLAGS)
        AND     0FFh - FLAG_NET_INITIALIZED
        LD      (STATE_FLAGS), A

.FREE_DLL:
        LD      A, (STATE_FLAGS)
        AND     FLAG_DLL_LOADED
        RET     Z
        LD      HL, (DLL_HANDLE)
        CALL    LIBMAN.l_free
        XOR     A
        LD      (STATE_FLAGS), A
        LD      (DLL_HANDLE), A
        LD      (DLL_HANDLE + 1), A
        RET

CLEAR_BSS:
        LD      HL, BSS_BASE
        LD      DE, BSS_BASE + 1
        LD      BC, BSS_SIZE - 1
        XOR     A
        LD      (HL), A
        LDIR
        RET

; ---------------------------------------------------------------------------
; Text output helpers. Static messages are generated as CP866 byte arrays.
; ---------------------------------------------------------------------------
PUTS:
        PUSH    AF
        PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      C, DSS_PCHARS
        RST     DSS
        POP     HL
        POP     DE
        POP     BC
        POP     AF
        RET

PUTS_LN:
        CALL    PUTS
CRLF:
        LD      HL, MSG_CRLF
        JR      PUTS

PUT_CHAR:
        PUSH    AF
        PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      C, DSS_PUTCHAR
        RST     DSS
        POP     HL
        POP     DE
        POP     BC
        POP     AF
        RET

PUT_HEX16:
        LD      A, D
        CALL    PUT_HEX8
        LD      A, E
PUT_HEX8:
        PUSH    AF
        RRCA
        RRCA
        RRCA
        RRCA
        CALL    PUT_NIBBLE
        POP     AF
PUT_NIBBLE:
        AND     0Fh
        ADD     A, 090h
        DAA
        ADC     A, 040h
        DAA
        JP      PUT_CHAR

; Print up to four final response bytes in stream order. This diagnostics-only
; helper makes a malformed or repeated network payload observable without
; dumping an unbounded buffer to the text screen.
PRINT_RESPONSE_TAIL:
        LD      HL, (RESPONSE_SIZE)
        LD      A, H
        OR      L
        RET     Z
        LD      A, H
        OR      A
        JR      NZ, .FOUR
        LD      A, L
        CP      4
        JR      NC, .FOUR
        LD      B, A
        LD      A, 4
        SUB     B
        LD      E, A
        LD      D, 0
        LD      HL, RESPONSE_TAIL
        ADD     HL, DE
        JR      .LOOP
.FOUR:
        LD      HL, RESPONSE_TAIL
        LD      B, 4
.LOOP:
        LD      A, (HL)
        CALL    PUT_HEX8
        INC     HL
        DJNZ    .LOOP
        RET

ENV_NET:
        DB      "NET", 0
VALUE_WIFI:
        DB      "WIFI", 0
VALUE_RTL:
        DB      "RTL", 0
DLL_ESP:
        DB      "UNETESP.DLL", 0
DLL_RTL:
        DB      "UNETRTL.DLL", 0
INFO_ESP_TAG:
        DB      "UNETESP", 0
INFO_RTL_TAG:
        DB      "UNETRTL", 0

        INCLUDE "messages.inc"

        ENDMODULE

; The current libman source is compiled into WEATHER.EXE. It uses WIN3 as
; scratch, restores it on return and loads the selected DLL into WIN1.
        INCLUDE "libman.asm"

        MODULE  MAIN

; Reserve the complete caller-owned WIN2 workspace in the EXE image. DSS does
; not have a separate BSS-size header field: memory after the raw image may be
; reused by another allocation, so receive buffers must be emitted explicitly.
BSS_BASE        EQU $
DLL_HANDLE      EQU BSS_BASE
STATE_FLAGS     EQU DLL_HANDLE + 2
BACKEND         EQU STATE_FLAGS + 1
EXIT_CODE       EQU BACKEND + 1
LAST_UNET_STATUS EQU EXIT_CODE + 1
DLL_NAME_PTR    EQU LAST_UNET_STATUS + 1
UNET_CAPS       EQU DLL_NAME_PTR + 2
UNET_ABI        EQU UNET_CAPS + 2
ENV_VALUE       EQU UNET_ABI + 2
; DSS ENV_GET has no destination-capacity argument. ENV_SET limits a complete
; NAME=VALUE string to 255 bytes, so reserve 256 bytes for every returned value.
ENV_VALUE_SIZE  EQU 256
DLL_INFO        EQU ENV_VALUE + ENV_VALUE_SIZE
DLL_INFO_SIZE   EQU 32
CFG_PATH        EQU DLL_INFO + DLL_INFO_SIZE
CFG_PATH_SIZE   EQU 272
CFG_FILE_BUFFER EQU CFG_PATH + CFG_PATH_SIZE
CFG_FILE_MAX    EQU 1024
CFG_FILE_SIZE   EQU CFG_FILE_BUFFER + CFG_FILE_MAX
CFG_FILE_HANDLE EQU CFG_FILE_SIZE + 2
CFG_LINE_BUFFER EQU CFG_FILE_HANDLE + 1
CFG_LINE_MAX    EQU 255
CFG_LINE_LEN    EQU CFG_LINE_BUFFER + CFG_LINE_MAX + 1
CFG_LINE_NO     EQU CFG_LINE_LEN + 1
CFG_ERROR_LINE  EQU CFG_LINE_NO + 2
CFG_ERROR_CODE  EQU CFG_ERROR_LINE + 2
CFG_WARNING_LINE EQU CFG_ERROR_CODE + 1
CFG_HOST        EQU CFG_WARNING_LINE + 2
CFG_HOST_SIZE   EQU 129
CFG_PORT        EQU CFG_HOST + CFG_HOST_SIZE
CFG_PORT_SIZE   EQU 6
CFG_PORT_NUMBER EQU CFG_PORT + CFG_PORT_SIZE
CFG_SELECTOR    EQU CFG_PORT_NUMBER + 2
CFG_SELECTOR_SIZE EQU 97
CFG_LOCATION    EQU CFG_SELECTOR + CFG_SELECTOR_SIZE
CFG_LOCATION_SIZE EQU 97
REQUEST_BUFFER  EQU CFG_LOCATION + CFG_LOCATION_SIZE
REQUEST_MAX     EQU 192
REQUEST_SIZE    EQU REQUEST_BUFFER + REQUEST_MAX + 1
RECV_BUFFER     EQU REQUEST_SIZE + 2
RECV_BUFFER_SIZE EQU 512
RESPONSE_SIZE   EQU RECV_BUFFER + RECV_BUFFER_SIZE
RESPONSE_TAIL   EQU RESPONSE_SIZE + 2
TRANSPORT_INPUT_PTR EQU RESPONSE_TAIL + 4
TRANSPORT_INPUT_SIZE EQU TRANSPORT_INPUT_PTR + 2
; The parser limits total received bytes even though it no longer stores the
; complete response. This leaves room in WIN2 for two validated forecasts.
RESPONSE_MAX    EQU 4096
TRANSPORT_STAGE EQU TRANSPORT_INPUT_SIZE + 2
TRANSPORT_CODE  EQU TRANSPORT_STAGE + 1
TRANSPORT_RESPONSE_ERROR EQU TRANSPORT_CODE + 1
TRANSPORT_HAS_DETAIL EQU TRANSPORT_RESPONSE_ERROR + 1
TRANSPORT_DETAIL_STATUS EQU TRANSPORT_HAS_DETAIL + 1
TRANSPORT_DETAIL EQU TRANSPORT_DETAIL_STATUS + 1
TRANSPORT_DETAIL_SIZE EQU 128
LAST_RECV_LENGTH EQU TRANSPORT_DETAIL + TRANSPORT_DETAIL_SIZE
TRANSPORT_RESPONSE_SIZE EQU LAST_RECV_LENGTH + 2
WX1_LINE_BUFFER EQU TRANSPORT_RESPONSE_SIZE + 2
WX1_LINE_LEN    EQU WX1_LINE_BUFFER + WX1_LINE_MAX + 1
WX1_STATE       EQU WX1_LINE_LEN + 1
WX1_LINE_COUNT  EQU WX1_STATE + 1
WX1_EOL_MODE    EQU WX1_LINE_COUNT + 1
WX1_PENDING_CR  EQU WX1_EOL_MODE + 1
WX1_RESULT      EQU WX1_PENDING_CR + 1
WX1_ERROR_CODE  EQU WX1_RESULT + 1
WX1_ERROR_LINE  EQU WX1_ERROR_CODE + 1
WX1_DAYS_LEFT   EQU WX1_ERROR_LINE + 1
WX1_FIELD_COUNT EQU WX1_DAYS_LEFT + 1
WX1_FIELD_PTRS  EQU WX1_FIELD_COUNT + 1
WX1_NEXT_DAY_PTR EQU WX1_FIELD_PTRS + 16
WX1_SERVICE_CODE EQU WX1_NEXT_DAY_PTR + 2
WX1_SERVICE_CODE_SIZE EQU 33
WX1_COPY_LEFT   EQU WX1_SERVICE_CODE + WX1_SERVICE_CODE_SIZE
WX1_INPUT_BYTE  EQU WX1_COPY_LEFT + 1
WX1_EOL_CANDIDATE EQU WX1_INPUT_BYTE + 1
WX1_DIGIT       EQU WX1_EOL_CANDIDATE + 1
WX1_DIGITS      EQU WX1_DIGIT + 1
WX1_TMP16       EQU WX1_DIGITS + 1
WX1_DATE_MONTH  EQU WX1_TMP16 + 2
WX1_DATE_DAY    EQU WX1_DATE_MONTH + 1
WX1_DATE_YEAR   EQU WX1_DATE_DAY + 1
WX1_STAGE_MODEL EQU WX1_DATE_YEAR + 2
WX1_MODEL       EQU WX1_STAGE_MODEL + WM_MODEL_SIZE
TEXT_DAYS_LEFT  EQU WX1_MODEL + WM_MODEL_SIZE
TEXT_DECIMAL    EQU TEXT_DAYS_LEFT + 1
TEXT_NUMBER_BUFFER EQU TEXT_DECIMAL + 1
TEXT_NUMBER_BUFFER_SIZE EQU 8
LAST_ATTEMPT_EXIT EQU TEXT_NUMBER_BUFFER + TEXT_NUMBER_BUFFER_SIZE
BSS_END         EQU LAST_ATTEMPT_EXIT + 1
BSS_SIZE        EQU BSS_END - BSS_BASE

STACK_SIZE      EQU 0600h
STACK_BOTTOM    EQU BSS_END
STACK_TOP       EQU STACK_BOTTOM + STACK_SIZE

        ASSERT  BSS_BASE >= 08100h
        ASSERT  BSS_END < STACK_TOP

        DS      BSS_SIZE, 0
        DS      STACK_SIZE, 0
IMAGE_END       EQU $

        ASSERT  IMAGE_END = STACK_TOP
        ASSERT  IMAGE_END < 0C000h
        ASSERT  STACK_TOP <= 0C000h
        ASSERT  ENV_VALUE + ENV_VALUE_SIZE <= 0C000h
        ASSERT  DLL_INFO + DLL_INFO_SIZE <= 0C000h
        ASSERT  BSS_END < STACK_TOP

        ENDMODULE

        END     MAIN.START
