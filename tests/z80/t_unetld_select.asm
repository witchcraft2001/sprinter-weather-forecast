        DEVICE  NOSLOT64K
        ORG     0000h
        JP      START
        DS      000Dh, 0

; UNETLD uses the real DSS entry point. The harness supplies a tiny ENV_GET
; vector at RST #10 and returns each fixture selected below.
        JP      DSS_STUB
        DS      000Dh, 0

        INCLUDE "harness.inc"

UNETLD_STATE_BASE      EQU 07000h

START:
        CALL    T_BEGIN
        CALL    UNETLD.RESET
        CALL    TEST_WIFI_ALIAS
        CALL    TEST_DIRECT_TAG
        CALL    TEST_NO_ENV
        CALL    TEST_BAD_LENGTHS
        CALL    TEST_BAD_CHARACTER
        CALL    TEST_LOAD_MISSING
        CALL    TEST_WRONG_DLL_NAME
        CALL    TEST_BAD_ABI
        CALL    TEST_NO_TCP
        CALL    TEST_NETSTART_SUCCESS
        CALL    TEST_NETSTART_STATUS
        CALL    TEST_UNLOAD_IDEMPOTENT
        CALL    T_END
        HALT

TEST_WIFI_ALIAS:
        LD      HL, VALUE_WIFI_LOWER
        LD      (DSS_ENV_PTR), HL
        LD      A, 1
        LD      (DSS_ENV_MODE), A
        CALL    UNETLD.SELECT
        LD      A, 1
        CALL    T_EXPECT_NC
        LD      HL, UNETLD.NET_TAG
        LD      DE, EXPECTED_ESP
        CALL    T_STREQ
        LD      A, 2
        CALL    T_EXPECT_Z
        LD      HL, UNETLD.DLL_NAME
        LD      DE, EXPECTED_ESP_DLL
        CALL    T_STREQ
        LD      A, 3
        CALL    T_EXPECT_Z
        RET

TEST_DIRECT_TAG:
        LD      HL, VALUE_509B_LOWER
        LD      (DSS_ENV_PTR), HL
        LD      A, 1
        LD      (DSS_ENV_MODE), A
        CALL    UNETLD.SELECT
        LD      A, 4
        CALL    T_EXPECT_NC
        LD      HL, UNETLD.NET_TAG
        LD      DE, EXPECTED_509B
        CALL    T_STREQ
        LD      A, 5
        CALL    T_EXPECT_Z
        LD      HL, UNETLD.DLL_NAME
        LD      DE, EXPECTED_509B_DLL
        CALL    T_STREQ
        LD      A, 6
        CALL    T_EXPECT_Z
        RET

TEST_NO_ENV:
        XOR     A
        LD      (DSS_ENV_MODE), A
        CALL    UNETLD.SELECT
        LD      A, 7
        CALL    T_EXPECT_C
        LD      A, (UNETLD.ERROR)
        CP      UNETLD_E_NOENV
        LD      A, 8
        CALL    T_EXPECT_Z
        RET

TEST_BAD_LENGTHS:
        LD      HL, VALUE_SHORT
        CALL    TEST_BAD_VALUE
        LD      HL, VALUE_LONG
        CALL    TEST_BAD_VALUE
        RET

TEST_BAD_CHARACTER:
        LD      HL, VALUE_BAD_CHAR
        CALL    TEST_BAD_VALUE
        RET

TEST_LOAD_MISSING:
        CALL    SELECT_509B
        LD      A, 1
        LD      (LIBMAN_LOAD_FAIL), A
        LD      A, 1
        CALL    UNETLD.LOAD
        LD      A, 11
        CALL    T_EXPECT_C
        LD      A, (UNETLD.ERROR)
        CP      UNETLD_E_LOAD
        LD      A, 12
        CALL    T_EXPECT_Z
        CALL    UNETLD.UNLOAD
        XOR     A
        LD      (LIBMAN_LOAD_FAIL), A
        RET

TEST_WRONG_DLL_NAME:
        CALL    SELECT_509B
        LD      HL, WRONG_DLL_L1_NAME
        LD      (LIBMAN_NAME_PTR), HL
        LD      DE, UNET_CAP_TCP
        LD      (LIBMAN_CAPS), DE
        LD      HL, UNET_ABI_VERSION
        LD      (LIBMAN_ABI), HL
        LD      A, 1
        CALL    UNETLD.LOAD
        LD      A, 31
        CALL    T_EXPECT_C
        LD      A, (UNETLD.ERROR)
        CP      UNETLD_E_NAME
        LD      A, 32
        CALL    T_EXPECT_Z
        CALL    UNETLD.UNLOAD
        LD      HL, TEST_DLL_NAME
        LD      (LIBMAN_NAME_PTR), HL
        RET

TEST_BAD_ABI:
        CALL    SELECT_509B
        LD      DE, UNET_CAP_TCP
        LD      (LIBMAN_CAPS), DE
        LD      HL, 0200h
        LD      (LIBMAN_ABI), HL
        LD      A, 1
        CALL    UNETLD.LOAD
        LD      A, 13
        CALL    T_EXPECT_C
        LD      A, (UNETLD.ERROR)
        CP      UNETLD_E_ABI
        LD      A, 14
        CALL    T_EXPECT_Z
        CALL    UNETLD.UNLOAD
        RET

TEST_NO_TCP:
        CALL    SELECT_509B
        LD      DE, 0
        LD      (LIBMAN_CAPS), DE
        LD      HL, UNET_ABI_VERSION
        LD      (LIBMAN_ABI), HL
        LD      A, 1
        CALL    UNETLD.LOAD
        LD      A, 15
        CALL    T_EXPECT_NC
        LD      DE, UNET_CAP_TCP
        CALL    UNETLD.REQUIRE
        LD      A, 16
        CALL    T_EXPECT_C
        CALL    UNETLD.UNLOAD
        RET

TEST_NETSTART_STATUS:
        CALL    SELECT_509B
        LD      DE, UNET_CAP_TCP
        LD      (LIBMAN_CAPS), DE
        LD      HL, UNET_ABI_VERSION
        LD      (LIBMAN_ABI), HL
        LD      A, NERR_HW
        LD      (LIBMAN_NETINIT_STATUS), A
        LD      A, 1
        CALL    UNETLD.LOAD
        LD      A, 17
        CALL    T_EXPECT_NC
        CALL    UNETLD.NETSTART
        LD      A, 18
        CALL    T_EXPECT_C
        LD      A, (UNETLD.ERROR)
        CP      UNETLD_E_NETINIT
        LD      A, 19
        CALL    T_EXPECT_Z
        LD      A, (UNETLD.LAST_STATUS)
        CP      NERR_HW
        LD      A, 20
        CALL    T_EXPECT_Z
        CALL    UNETLD.UNLOAD
        XOR     A
        LD      (LIBMAN_NETINIT_STATUS), A
        RET

TEST_NETSTART_SUCCESS:
        CALL    SELECT_509B
        LD      DE, UNET_CAP_TCP
        LD      (LIBMAN_CAPS), DE
        LD      HL, UNET_ABI_VERSION
        LD      (LIBMAN_ABI), HL
        LD      A, NERR_NONET
        LD      (LIBMAN_STATUS), A
        XOR     A
        LD      (LIBMAN_NETINIT_STATUS), A
        LD      A, 1
        CALL    UNETLD.LOAD
        LD      A, 21
        CALL    T_EXPECT_NC

        ; Mirror the application's SETOPT(CANCELKEYS) call.
        LD      A, UNET_OPT_CANCELKEYS
        LD      DE, 1
        LD      B, UNET_FN_SETOPT
        CALL    UNETLD.CALL
        LD      A, 22
        CALL    T_EXPECT_NC
        LD      A, (LIBMAN_CANCELKEYS_SEEN)
        CP      1
        LD      A, 23
        CALL    T_EXPECT_Z

        CALL    UNETLD.NETSTART
        LD      A, 24
        CALL    T_EXPECT_NC
        LD      A, (UNETLD.FLAGS)
        AND     UNETLD_F_NETINIT
        LD      A, 25
        CALL    T_EXPECT_NZ
        CALL    UNETLD.UNLOAD
        LD      A, (LIBMAN_NETDONE_COUNT)
        CP      1
        LD      A, 26
        CALL    T_EXPECT_Z
        LD      A, (UNETLD.FLAGS)
        OR      A
        LD      A, 27
        CALL    T_EXPECT_Z
        RET

TEST_UNLOAD_IDEMPOTENT:
        CALL    UNETLD.UNLOAD
        LD      A, 28
        CALL    T_EXPECT_NC
        CALL    UNETLD.UNLOAD
        LD      A, 29
        CALL    T_EXPECT_NC
        LD      A, (LIBMAN_NETDONE_COUNT)
        CP      1
        LD      A, 30
        CALL    T_EXPECT_Z
        RET

SELECT_509B:
        CALL    UNETLD.RESET
        LD      HL, VALUE_509B_LOWER
        LD      (DSS_ENV_PTR), HL
        LD      A, 1
        LD      (DSS_ENV_MODE), A
        JP      UNETLD.SELECT

; HL=environment value. Expect BADVALUE and a set carry from SELECT.
TEST_BAD_VALUE:
        LD      (DSS_ENV_PTR), HL
        LD      A, 1
        LD      (DSS_ENV_MODE), A
        CALL    UNETLD.SELECT
        LD      A, 9
        CALL    T_EXPECT_C
        LD      A, (UNETLD.ERROR)
        CP      UNETLD_E_BADVALUE
        LD      A, 10
        CALL    T_EXPECT_Z
        RET

T_STREQ:
.LOOP:  LD      A, (DE)
        LD      C, A
        LD      A, (HL)
        CP      C
        RET     NZ
        OR      A
        RET     Z
        INC     HL
        INC     DE
        JR      .LOOP

; Minimal DSS ENV_GET. Other registers used by SELECT are preserved just as
; the production DSS call contract requires.
DSS_STUB:
        PUSH    HL
        PUSH    DE
        LD      A, (DSS_ENV_MODE)
        OR      A
        JR      Z, .NOT_FOUND
        LD      HL, (DSS_ENV_PTR)
        LD      DE, UNETLD.ENV_VALUE
.COPY:  LD      A, (HL)
        LD      (DE), A
        INC     HL
        INC     DE
        OR      A
        JR      NZ, .COPY
        POP     DE
        POP     HL
        LD      A, 0FFh
        OR      A
        RET
.NOT_FOUND:
        POP     DE
        POP     HL
        XOR     A
        RET

DSS_ENV_MODE:          DB 0
DSS_ENV_PTR:           DW 0
VALUE_WIFI_LOWER:      DB "wifi", 0
VALUE_509B_LOWER:      DB "509b", 0
VALUE_SHORT:           DB "AB", 0
VALUE_LONG:            DB "ABCDE", 0
VALUE_BAD_CHAR:        DB "AB-", 0
EXPECTED_ESP:          DB "ESP", 0
EXPECTED_ESP_DLL:      DB "UNETESP.DLL", 0
EXPECTED_509B:         DB "509B", 0
EXPECTED_509B_DLL:     DB "UNET509B.DLL", 0

        MODULE  LIBMAN
l_load:
        LD      A, (LIBMAN_LOAD_FAIL)
        OR      A
        JR      NZ, .LOAD_ERROR
        LD      HL, 1
        OR      A
        RET
.LOAD_ERROR:
        SCF
        RET
l_info:
        EX      DE, HL
        LD      BC, 16
        ADD     HL, BC
        EX      DE, HL
        LD      HL, (LIBMAN_NAME_PTR)
        LD      BC, 8
        LDIR
        XOR     A
        RET
l_call:
        LD      (LIBMAN_CALL_A), A
        LD      (LIBMAN_CALL_DE), DE
        LD      A, B
        CP      UNET_FN_GETCAPS
        JR      Z, .GETCAPS
        CP      UNET_FN_STATUS
        JR      Z, .STATUS
        CP      UNET_FN_NETINIT
        JR      Z, .NETINIT
        CP      UNET_FN_NETDONE
        JR      Z, .NETDONE
        CP      UNET_FN_SETOPT
        JR      Z, .SETOPT
        XOR     A
        RET
.GETCAPS:
        LD      DE, (LIBMAN_CAPS)
        LD      IX, (LIBMAN_ABI)
        XOR     A
        RET
.STATUS:
        LD      A, (LIBMAN_STATUS)
        OR      A
        RET
.NETINIT:
        LD      A, (LIBMAN_NETINIT_STATUS)
        OR      A
        RET
.NETDONE:
        LD      A, (LIBMAN_NETDONE_COUNT)
        INC     A
        LD      (LIBMAN_NETDONE_COUNT), A
        XOR     A
        RET
.SETOPT:
        LD      A, (LIBMAN_CALL_A)
        CP      UNET_OPT_CANCELKEYS
        JR      NZ, .SETOPT_DONE
        LD      HL, (LIBMAN_CALL_DE)
        LD      A, H
        OR      A
        JR      NZ, .SETOPT_DONE
        LD      A, L
        CP      1
        JR      NZ, .SETOPT_DONE
        LD      A, 1
        LD      (LIBMAN_CANCELKEYS_SEEN), A
.SETOPT_DONE:
        XOR     A
        RET
l_free:                 RET
        ENDMODULE

LIBMAN_LOAD_FAIL:      DB 0
LIBMAN_CAPS:           DW 0
LIBMAN_ABI:            DW 0
LIBMAN_CALL_A:         DB 0
LIBMAN_CALL_DE:        DW 0
LIBMAN_STATUS:         DB NERR_NONET
LIBMAN_NETINIT_STATUS: DB 0
LIBMAN_NETDONE_COUNT:  DB 0
LIBMAN_CANCELKEYS_SEEN: DB 0
LIBMAN_NAME_PTR:       DW TEST_DLL_NAME
TEST_DLL_NAME:         DB "UNET509B"
WRONG_DLL_L1_NAME:     DB "UNETRTL "

        INCLUDE "unetld.asm"
