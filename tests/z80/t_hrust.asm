; Hrust depack harness.
;
; Reproduces the address layout WEATHER.EXE really uses: packed streams at
; #C000 (WIN3 on hardware), destination at #8000 (WIN2) and the caller stack
; just below #8000 (WIN1).  All five streams are unpacked back to back, the
; same way GRAPHICS_BOOT walks them.
;
; Two things are asserted per page: HRUST_DEPACK must restore SP exactly, and
; the 16 KiB result must match the checksum of the original page.  Checksums
; are compared by tools/run_z80_tests.sh against the unpacked .bin files.

        DEVICE  NOSLOT64K
        ORG     0
        JP      START

        INCLUDE "hrust_depack.asm"
        INCLUDE "hrust_sizes.inc"

PAGE_COUNT      EQU 5
STACK_TOP       EQU 07FF0h
DEST            EQU 08000h
DEST_SIZE       EQU 04000h

STATUS_OK       EQU 0
STATUS_SP       EQU 1

START:
        LD      SP, STACK_TOP
        LD      HL, PACKED
        LD      (SRC_PTR), HL
        LD      HL, 0E010h
        LD      (SUM_PTR), HL
        XOR     A
        LD      (PAGE_INDEX), A

.NEXT_PAGE:
        LD      A, (PAGE_INDEX)
        LD      (0E002h), A

        LD      HL, (SRC_PTR)
        LD      DE, DEST
        LD      (SP_BEFORE), SP
        CALL    HRUST_DEPACK
        LD      (SP_AFTER), SP
        ; The depacker parks SP inside the packed stream and hands it back only
        ; on its normal exit path.  Recover unconditionally before comparing,
        ; otherwise a regression takes the harness down with it.
        LD      SP, STACK_TOP
        EI

        LD      HL, (SP_AFTER)
        LD      DE, (SP_BEFORE)
        OR      A
        SBC     HL, DE
        JR      NZ, .FAIL_SP

        CALL    CHECKSUM_DEST
        LD      DE, (SUM_PTR)
        EX      DE, HL
        LD      (HL), E
        INC     HL
        LD      (HL), D
        INC     HL
        LD      (SUM_PTR), HL

        LD      A, (PAGE_INDEX)
        ADD     A, A
        LD      E, A
        LD      D, 0
        LD      HL, GRAPHICS_PACKED_SIZES
        ADD     HL, DE
        LD      E, (HL)
        INC     HL
        LD      D, (HL)
        LD      HL, (SRC_PTR)
        ADD     HL, DE
        LD      (SRC_PTR), HL

        LD      A, (PAGE_INDEX)
        INC     A
        LD      (PAGE_INDEX), A
        CP      PAGE_COUNT
        JR      C, .NEXT_PAGE

        LD      A, STATUS_OK
        JR      .DONE

.FAIL_SP:
        LD      HL, (SP_AFTER)
        LD      (0E004h), HL
        LD      HL, (SP_BEFORE)
        LD      (0E006h), HL
        LD      A, STATUS_SP

.DONE:
        LD      (0E000h), A
        LD      A, 0A5h
        LD      (0E001h), A
        HALT

; Rolling checksum over DEST: HL = rotate_left(HL) + byte, per byte.
; Out: HL = checksum.  Trashes A, BC, DE.
CHECKSUM_DEST:
        LD      HL, 0
        LD      DE, DEST
        LD      BC, DEST_SIZE
.BYTE:
        PUSH    BC
        ADD     HL, HL
        LD      BC, 0
        ADC     HL, BC
        LD      A, (DE)
        LD      C, A
        ADD     HL, BC
        INC     DE
        POP     BC
        DEC     BC
        LD      A, B
        OR      C
        JR      NZ, .BYTE
        RET

SRC_PTR:        DW 0
SUM_PTR:        DW 0
SP_BEFORE:      DW 0
SP_AFTER:       DW 0
PAGE_INDEX:     DB 0

        DS      0C000h - $, 0
PACKED:
        INCBIN  "page00.hst"
        INCBIN  "page01.hst"
        INCBIN  "page02.hst"
        INCBIN  "page03.hst"
        INCBIN  "page04.hst"

        DS      0E000h - $, 0
        DS      026, 0
