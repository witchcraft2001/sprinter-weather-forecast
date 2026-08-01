; WEATHER.EXE primary PRELOAD loader.
;
; It is the only code that knows the WFG2 file tail and Hrust.  It loads the
; runtime into a fresh WIN2 page, expands each packed asset directly into the
; five-page asset block, then transfers A=asset_block to MAIN.START at #8100.

EXE_HEADER_SIZE          EQU 0200h
EXE_VERSION              EQU 1
EXE_LOAD_ADDRESS         EQU 08100h
LOADER_STACK_TOP         EQU 0BFF0h

WFG_MANIFEST_SIZE        EQU 24
WFG_PAGE_COUNT           EQU 5
WFG_PAGE_SIZE            EQU 04000h
WFG_RUNTIME_OFFSET       EQU 00100h
WFG_PSP_SIZE             EQU WFG_RUNTIME_OFFSET
WFG_RUNTIME_CAPACITY     EQU WFG_PAGE_SIZE - WFG_RUNTIME_OFFSET
WFG_RUNTIME_SIZE         EQU 10
WFG_STREAM_SIZES         EQU 14

        DEVICE  NOSLOT64K
        INCLUDE "dss.inc"

        ORG     EXE_LOAD_ADDRESS - EXE_HEADER_SIZE
LOADER_HEADER:
        DB      "EXE", EXE_VERSION
        DD      EXE_HEADER_SIZE
        DW      WEATHER_LOADER_SIZE
        DS      6, 0
        DW      LOADER_START
        DW      LOADER_START
        DW      LOADER_STACK_TOP
        DB      0
        DS      EXE_HEADER_SIZE - ($ - LOADER_HEADER), 0

        ASSERT  $ = EXE_LOAD_ADDRESS
        ORG     EXE_LOAD_ADDRESS

LOADER_START:
        LD      SP, LOADER_STACK_TOP
        LD      A, (IX - 3)             ; DSS PRELOAD file handle
        LD      (L_FILE_HANDLE), A
        LD      HL, L_BANNER
        LD      C, DSS_PCHARS
        RST     DSS

        ; WFG2 manifest immediately follows the primary loader in the file.
        LD      HL, L_MANIFEST
        LD      DE, WFG_MANIFEST_SIZE
        CALL    L_READ_EXACT
        JP      C, L_FAIL
        LD      HL, L_MANIFEST
        LD      DE, L_MAGIC
        LD      B, 4
.MAGIC: LD      A, (DE)
        CP      (HL)
        JP      NZ, L_FAIL
        INC     DE
        INC     HL
        DJNZ    .MAGIC
        LD      A, (L_MANIFEST + 4)
        CP      2
        JP      NZ, L_FAIL
        LD      A, (L_MANIFEST + 5)
        CP      WFG_PAGE_COUNT
        JP      NZ, L_FAIL
        LD      HL, (L_MANIFEST + 6)
        LD      DE, WFG_PAGE_SIZE
        OR      A
        SBC     HL, DE
        JP      NZ, L_FAIL
        LD      HL, (L_MANIFEST + WFG_RUNTIME_SIZE)
        LD      DE, WFG_RUNTIME_CAPACITY + 1
        OR      A
        SBC     HL, DE
        JP      NC, L_FAIL              ; runtime must fit at page offset #100
        LD      A, H
        OR      L
        JP      Z, L_FAIL

        ; One page for the resident runtime, five expanded asset pages and one
        ; reusable packed-stream page.
        LD      B, 1
        LD      C, DSS_GETMEM
        RST     DSS
        JP      C, L_FAIL
        LD      (L_RUNTIME_BLOCK), A
        LD      A, 1
        LD      (L_RUNTIME_ALLOC), A
        LD      B, WFG_PAGE_COUNT
        LD      C, DSS_GETMEM
        RST     DSS
        JP      C, L_FAIL
        LD      (L_ASSET_BLOCK), A
        LD      A, 1
        LD      (L_ASSET_ALLOC), A
        LD      B, 1
        LD      C, DSS_GETMEM
        RST     DSS
        JP      C, L_FAIL
        LD      (L_SCRATCH_BLOCK), A
        LD      A, 1
        LD      (L_SCRATCH_ALLOC), A

        ; Load the runtime in WIN3 while this primary loader remains in WIN2.
        LD      A, (L_RUNTIME_BLOCK)
        LD      B, 0
        LD      C, DSS_SETWIN3
        RST     DSS
        JP      C, L_FAIL
        IN      A, (0E2h)
        LD      (L_RUNTIME_PAGE), A
        ; DSS keeps the 256-byte PSP immediately below the EXE load address,
        ; at #8000..#80FF for an application loaded at #8100. APPINFO retains a
        ; pointer into that virtual range. Preserve it in the replacement WIN2
        ; page or APPINFO will parse uninitialised bytes as the EXE path.
        LD      HL, 08000h
        LD      DE, 0C000h
        LD      BC, WFG_PSP_SIZE
        LDIR
        ; The raw runtime starts at ORG #8100.  A DSS page mapped into WIN2
        ; begins at #8000, so load at physical offset #0100 (#C100 in WIN3).
        LD      HL, 0C000h + WFG_RUNTIME_OFFSET
        LD      DE, (L_MANIFEST + WFG_RUNTIME_SIZE)
        CALL    L_READ_EXACT
        JP      C, L_FAIL

        XOR     A
        LD      (L_PAGE_INDEX), A
.PAGE:
        ; Obtain the destination's physical page through DSS and leave the
        ; packed source in WIN3. WIN0 is switched only after the file read.
        LD      A, (L_PAGE_INDEX)
        LD      B, A
        LD      A, (L_ASSET_BLOCK)
        LD      C, DSS_SETWIN1
        RST     DSS
        JP      C, L_FAIL
        IN      A, (0A2h)
        LD      (L_DEST_PAGE), A
        LD      A, (L_SCRATCH_BLOCK)
        LD      B, 0
        LD      C, DSS_SETWIN3
        RST     DSS
        JP      C, L_FAIL
        LD      A, (L_PAGE_INDEX)
        ADD     A, A
        LD      E, A
        LD      D, 0
        LD      HL, L_MANIFEST + WFG_STREAM_SIZES
        ADD     HL, DE
        LD      E, (HL)
        INC     HL
        LD      D, (HL)
        LD      A, D
        OR      E
        JP      Z, L_FAIL
        LD      HL, WFG_PAGE_SIZE
        OR      A
        SBC     HL, DE
        JP      C, L_FAIL
        LD      HL, 0C000h
        CALL    L_READ_EXACT
        JP      C, L_FAIL

        ; WIN0 contains the DSS/BIOS RST vectors and must stay mapped while
        ; L_READ_EXACT calls RST DSS. Expose the asset page only for the
        ; interrupt-free depack itself, then restore WIN0 before the next DSS
        ; operation. Leaving the asset mapped here makes RST #10 execute image
        ; bytes as Z80 code.
        DI
        IN      A, (082h)
        LD      (L_WIN0_PAGE), A
        LD      A, (L_DEST_PAGE)
        OUT     (082h), A
        LD      HL, 0C000h
        LD      DE, 0
        CALL    HRUST_DEPACK
        LD      A, (L_WIN0_PAGE)
        OUT     (082h), A
        EI
        LD      A, (L_PAGE_INDEX)
        INC     A
        LD      (L_PAGE_INDEX), A
        CP      WFG_PAGE_COUNT
        JR      C, .PAGE

        LD      A, (L_FILE_HANDLE)
        LD      C, DSS_CLOSE_FILE
        RST     DSS
        LD      A, 0FFh
        LD      (L_FILE_HANDLE), A
        LD      A, (L_SCRATCH_BLOCK)
        LD      C, DSS_FREEMEM
        RST     DSS
        XOR     A
        LD      (L_SCRATCH_ALLOC), A

        ; Copy a tiny handoff trampoline into WIN1. It remains executable when
        ; it maps the runtime over this loader's WIN2 page.
        LD      A, (L_RUNTIME_PAGE)
        LD      (L_TRAMPOLINE + 1), A
        LD      A, (L_ASSET_BLOCK)
        LD      (L_TRAMPOLINE + 5), A
        DI
        IN      A, (0C2h)
        OUT     (0A2h), A
        LD      HL, L_TRAMPOLINE
        LD      DE, 04000h
        LD      BC, L_TRAMPOLINE_END - L_TRAMPOLINE
        LDIR
        JP      04000h

; HL=destination, DE=expected bytes. Carry on DSS error or any size mismatch.
L_READ_EXACT:
        LD      (L_EXPECTED), DE
        LD      A, (L_FILE_HANDLE)
        LD      C, DSS_READ_FILE
        RST     DSS
        RET     C
        LD      HL, (L_EXPECTED)
        OR      A
        SBC     HL, DE
        RET     Z
        SCF
        RET

L_FAIL:
        EI
        LD      A, (L_FILE_HANDLE)
        CP      0FFh
        JR      Z, .SCRATCH
        LD      C, DSS_CLOSE_FILE
        RST     DSS
.SCRATCH:
        LD      A, (L_SCRATCH_ALLOC)
        OR      A
        JR      Z, .ASSETS
        LD      A, (L_SCRATCH_BLOCK)
        LD      C, DSS_FREEMEM
        RST     DSS
.ASSETS:
        LD      A, (L_ASSET_ALLOC)
        OR      A
        JR      Z, .RUNTIME
        LD      A, (L_ASSET_BLOCK)
        LD      C, DSS_FREEMEM
        RST     DSS
.RUNTIME:
        LD      A, (L_RUNTIME_ALLOC)
        OR      A
        JR      Z, .EXIT
        LD      A, (L_RUNTIME_BLOCK)
        LD      C, DSS_FREEMEM
        RST     DSS
.EXIT:
        LD      B, 2
        LD      C, DSS_EXIT
        RST     DSS

; This code executes from WIN1 after it replaces WIN2 with the runtime page.
L_TRAMPOLINE:
        LD      A, 0
        OUT     (0C2h), A
        LD      A, 0
        JP      08100h
L_TRAMPOLINE_END:

        INCLUDE "hrust_depack.asm"

L_MAGIC:                DB "WFG2"
L_BANNER:
        DB      "Weather Forecast v.0.1.0 by Dmitry Mikhalchenkov.", 13, 10, 0
L_FILE_HANDLE:          DB 0FFh
L_RUNTIME_BLOCK:        DB 0
L_ASSET_BLOCK:          DB 0
L_SCRATCH_BLOCK:        DB 0
L_RUNTIME_ALLOC:        DB 0
L_ASSET_ALLOC:          DB 0
L_SCRATCH_ALLOC:        DB 0
L_RUNTIME_PAGE:         DB 0
L_DEST_PAGE:            DB 0
L_WIN0_PAGE:            DB 0
L_PAGE_INDEX:           DB 0
L_EXPECTED:             DW 0
L_MANIFEST:             DS WFG_MANIFEST_SIZE, 0

WEATHER_LOADER_SIZE     EQU $ - EXE_LOAD_ADDRESS
        ASSERT  WEATHER_LOADER_SIZE < 04000h
        END     LOADER_START
