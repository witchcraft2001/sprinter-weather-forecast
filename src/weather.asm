; ============================================================================
; WEATHER.EXE - stage 1 network bootstrap for Sprinter DSS.
;
; Reads NET from the DSS environment, selects a prebuilt UNET backend, loads
; it through the current libman, validates ABI/capabilities and brings the
; selected interface up. No weather request is made at this stage.
; ============================================================================

EXE_VERSION             EQU 1
EXE_HEADER_SIZE         EQU 0200h
EXE_LOAD_ADDRESS        EQU 08100h

FLAG_DLL_LOADED         EQU 00000001b
FLAG_NET_INITIALIZED    EQU 00000010b

BACKEND_NONE            EQU 0
BACKEND_WIFI            EQU 1
BACKEND_RTL             EQU 2

EXIT_OK                 EQU 0
EXIT_DLL                EQU 2
EXIT_NETWORK            EQU 3
EXIT_CONFIG             EQU 4

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
        LD      HL, MSG_NEXT
        CALL    PUTS_LN

        LD      B, EXIT_OK
        JP      EXIT_PROGRAM

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
        LD      HL, MSG_NET_NOT_CONFIGURED
        CALL    PUTS_LN
        CALL    PRINT_CONFIG_HINT
        LD      B, EXIT_CONFIG
        JP      EXIT_PROGRAM

ERROR_LOAD:
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
        JP      EXIT_PROGRAM

ERROR_INFO:
        LD      HL, MSG_INFO_ERROR
        CALL    PUTS_LN
        LD      B, EXIT_DLL
        JP      EXIT_PROGRAM

ERROR_INFO_NAME:
        LD      HL, MSG_INFO_NAME_ERROR
        CALL    PUTS
        LD      HL, DLL_INFO + 16
        CALL    PUTS_LN
        LD      B, EXIT_DLL
        JP      EXIT_PROGRAM

ERROR_ABI:
        LD      HL, MSG_ABI_ERROR
        CALL    PUTS
        LD      DE, (UNET_ABI)
        CALL    PUT_HEX16
        CALL    CRLF
        LD      B, EXIT_DLL
        JP      EXIT_PROGRAM

ERROR_TCP_CAP:
        LD      HL, MSG_TCP_ERROR
        CALL    PUTS_LN
        LD      B, EXIT_DLL
        JP      EXIT_PROGRAM

ERROR_CALL:
        LD      HL, MSG_CALL_ERROR
        CALL    PUTS_LN
        LD      B, EXIT_DLL
        JP      EXIT_PROGRAM

ERROR_UNET_STATUS:
        LD      (LAST_UNET_STATUS), A
        LD      HL, MSG_UNET_ERROR
        CALL    PUTS
        LD      A, (LAST_UNET_STATUS)
        CALL    PUT_HEX8
        CALL    CRLF
        LD      B, EXIT_NETWORK
        JP      EXIT_PROGRAM

ERROR_NETINIT:
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
        JP      EXIT_PROGRAM

.CONFIG:
        LD      HL, MSG_BACKEND_NOT_CONFIGURED
        CALL    PUTS_LN
        CALL    PRINT_CONFIG_HINT
        LD      B, EXIT_CONFIG
        JP      EXIT_PROGRAM

.HARDWARE:
        LD      HL, MSG_HARDWARE_ERROR
        CALL    PUTS_LN
        CALL    PRINT_CONFIG_HINT
        LD      B, EXIT_DLL
        JP      EXIT_PROGRAM

.BUSY:
        LD      HL, MSG_BUSY_ERROR
        CALL    PUTS_LN
        LD      B, EXIT_NETWORK
        JP      EXIT_PROGRAM

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

; ---------------------------------------------------------------------------
; Idempotent cleanup and DSS exit.
; ---------------------------------------------------------------------------
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

IMAGE_END       EQU $

; Application BSS is not emitted into the EXE. The header-provided stack lies
; after it, while all caller-owned UNET buffers remain in WIN2.
BSS_BASE        EQU IMAGE_END
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
BSS_END         EQU DLL_INFO + DLL_INFO_SIZE
BSS_SIZE        EQU BSS_END - BSS_BASE

STACK_SIZE      EQU 0600h
STACK_BOTTOM    EQU BSS_END
STACK_TOP       EQU STACK_BOTTOM + STACK_SIZE

        ASSERT  IMAGE_END < 0C000h
        ASSERT  BSS_BASE >= 08100h
        ASSERT  BSS_END < STACK_TOP
        ASSERT  STACK_TOP <= 0C000h
        ASSERT  ENV_VALUE + ENV_VALUE_SIZE <= 0C000h
        ASSERT  DLL_INFO + DLL_INFO_SIZE <= 0C000h

        ENDMODULE

        END     MAIN.START
