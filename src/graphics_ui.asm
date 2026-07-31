; WEATHER.EXE graphics frontend.  All dynamic drawing is delegated to
; GFX320.DLL and AFNT320.DLL; this module only owns UI layout and resources.

AFNT_APRINT             EQU 3
AFNT_SET_WINDOW         EQU 4
BIOS_GETMEMBLKPAGES     EQU 0C5h
GFX_REQUIRED_CAPS       EQU GFX_CAP_ACCEL | GFX_CAP_KEY_FF | GFX_CAP_PALETTE_RGB8 | GFX_CAP_FADE | GFX_CAP_TILES | GFX_CAP_WIN0_SOURCE
WFG_MANIFEST_SIZE       EQU 22

        INCLUDE "graphics_assets.inc"
        INCLUDE "hrust_sizes.inc"

; Stage the compact PRELOAD tail while its file handle is valid, then close the
; file before any UNET call.  The five Hrust streams live together in one DSS
; scratch page; their expanded form is deferred until the network session ends.
GRAPHICS_STAGE_ASSETS:
        IN      A, (082h)
        LD      (GRAPHICS_SAVED_WIN0), A
        IN      A, (0A2h)
        LD      (GRAPHICS_SAVED_WIN1), A
        IN      A, (0E2h)
        LD      (GRAPHICS_SAVED_WIN3), A
        LD      A, (GRAPHICS_FILE_HANDLE)
        LD      HL, ASSET_MANIFEST
        LD      DE, WFG_MANIFEST_SIZE
        LD      C, DSS_READ_FILE
        RST     DSS
        JP      C, .FAIL
        ; Verify the byte count DSS returns in DE, not its status byte.  See
        ; the page read below for why the status cannot be trusted.  OR A only
        ; clears carry for SBC; it leaves the status in A for the report.
        LD      HL, WFG_MANIFEST_SIZE
        OR      A
        SBC     HL, DE
        JP      NZ, .FAIL
        LD      HL, ASSET_MANIFEST
        LD      DE, WFG_MAGIC
        LD      B, 4
.MAGIC: LD      A, (DE)
        CP      (HL)
        JP      NZ, .FAIL
        INC     DE
        INC     HL
        DJNZ    .MAGIC
        LD      A, (ASSET_MANIFEST + 4)
        CP      1
        JP      NZ, .FAIL
        LD      A, (ASSET_MANIFEST + 5)
        CP      GRAPHICS_ASSET_PAGES
        JP      NZ, .FAIL
        LD      HL, (ASSET_MANIFEST + 6)
        LD      DE, 4000h
        OR      A
        SBC     HL, DE
        JP      NZ, .FAIL
        ; The manifest and generated table come from the same packed streams.
        ; Reject a stale/mismatched EXE before accepting any resource data.
        LD      HL, ASSET_MANIFEST + 12
        LD      DE, GRAPHICS_PACKED_SIZES
        LD      B, GRAPHICS_ASSET_PAGES * 2
.SIZES:
        LD      A, (DE)
        CP      (HL)
        JP      NZ, .FAIL
        INC     DE
        INC     HL
        DJNZ    .SIZES

        LD      B, GRAPHICS_ASSET_PAGES
        LD      C, DSS_GETMEM
        RST     DSS
        JP      C, .FAIL
        LD      (ASSET_BLOCK), A
        LD      A, 1
        LD      (ASSET_ALLOCATED), A
        LD      B, 1
        LD      C, DSS_GETMEM
        RST     DSS
        JR      C, .FAIL_FREE
        LD      (ASSET_SCRATCH_BLOCK), A
        LD      A, 1
        LD      (ASSET_SCRATCH_ALLOCATED), A
        ; Set the scratch page before building the read arguments: DSS SETWIN
        ; destroys HL and DE.
        LD      A, (ASSET_SCRATCH_BLOCK)
        LD      B, 0
        LD      C, DSS_SETWIN3
        RST     DSS
        JR      C, .FAIL_FREE
        LD      HL, 0C000h
        LD      DE, GRAPHICS_PACKED_TOTAL
        LD      A, (GRAPHICS_FILE_HANDLE)
        LD      C, DSS_READ_FILE
        RST     DSS
        JR      C, .FAIL_FREE
        ; At EOF DSS may return status #FF despite delivering every byte; DE is
        ; the only reliable length result.
        LD      HL, GRAPHICS_PACKED_TOTAL
        OR      A
        SBC     HL, DE
        JR      NZ, .FAIL_FREE
        CALL    GRAPHICS_CLOSE_PRIMARY
        ; Both the packed tail and all expanded pages now belong to DSS memory;
        ; do the one-time expansion before network code starts using WIN3.
        CALL    GRAPHICS_BOOT
        JR      C, .FAIL_EXIT
        CALL    GRAPHICS_RESTORE_WINDOWS
        OR      A
        RET
.FAIL_FREE:
        CALL    GRAPHICS_FREE_ASSETS
        JR      .FAIL_EXIT
.FAIL:
.FAIL_EXIT:
        CALL    GRAPHICS_RESTORE_WINDOWS
        SCF
        RET

; Expand the resident Hrust streams into the five dedicated asset pages. This
; runs once during startup, before network code starts using WIN3. WEATHER.EXE
; and its stack occupy WIN2, so source stays in WIN3 and each destination page
; is temporarily mirrored into WIN0 at address #0000.
GRAPHICS_BOOT:
        LD      A, (ASSET_ALLOCATED)
        OR      A
        JP      Z, .FAIL
        LD      A, (ASSET_SCRATCH_ALLOCATED)
        OR      A
        JR      Z, .PAGE_LIST           ; already expanded (R/Enter refresh)
        IN      A, (082h)
        LD      (GRAPHICS_BOOT_SAVED_WIN0), A
        IN      A, (0E2h)
        LD      (GRAPHICS_BOOT_SAVED_WIN3), A
        LD      HL, 0C000h
        LD      (ASSET_PACKED_PTR), HL
        XOR     A
        LD      (ASSET_PAGE_INDEX), A
.PAGE:
        ; DSS has no SETWIN0 shortcut.  Ask it to map the allocated page into
        ; WIN3, preserve its physical-page byte, then put that byte in WIN0
        ; after WIN3 is switched to the packed-stream scratch page.
        LD      A, (ASSET_PAGE_INDEX)
        LD      B, A
        LD      A, (ASSET_BLOCK)
        LD      C, DSS_SETWIN3
        RST     DSS
        JR      C, .FAIL_FREE
        IN      A, (0E2h)
        LD      (ASSET_DEST_PAGE), A
        LD      A, (ASSET_SCRATCH_BLOCK)
        LD      B, 0
        LD      C, DSS_SETWIN3
        RST     DSS
        JR      C, .FAIL_FREE
        LD      A, (ASSET_DEST_PAGE)
        OUT     (082h), A
        LD      HL, (ASSET_PACKED_PTR)
        PUSH    HL
        LD      A, (ASSET_PAGE_INDEX)
        ADD     A, A
        LD      E, A
        LD      D, 0
        LD      HL, GRAPHICS_PACKED_SIZES
        ADD     HL, DE
        LD      E, (HL)
        INC     HL
        LD      D, (HL)
        POP     HL
        PUSH    HL
        ADD     HL, DE
        LD      (ASSET_PACKED_PTR), HL
        POP     HL
        ; DE=#0000 writes through WIN0, HL is the current Hrust stream in
        ; WIN3. HRUST_DEPACK restores SP but leaves interrupts disabled.
        LD      DE, 0
        CALL    HRUST_DEPACK
        CALL    GRAPHICS_RESTORE_ASSET_WINDOWS
        EI
        LD      A, (ASSET_PAGE_INDEX)
        INC     A
        LD      (ASSET_PAGE_INDEX), A
        CP      GRAPHICS_ASSET_PAGES
        JR      C, .PAGE
.PAGE_LIST:
        ; BIOS EMM_FN5 documents a destination that must accept up to 256 bytes
        ; (one byte per page of the block plus a #FF terminator), and there is
        ; no room for that in this WIN2-resident image.  Borrow the
        ; config file buffer: CONFIG_LOAD finished before the network phase, so
        ; the buffer is dead here.  Only the five page numbers are retained.
        ;
        ; Writing the list straight into a GRAPHICS_ASSET_PAGES-sized field
        ; overruns it into GRAPHICS_SAVED_WIN0/WIN1/WIN3, and those bytes are
        ; then pushed into the page ports by GRAPHICS_RESTORE_WINDOWS.
        ; GFX_SET_PAGE_TABLE copies the list into the DLL immediately, so the
        ; buffer only has to survive until GRAPHICS_LOAD_LIBRARIES runs - which
        ; GRAPHICS_RENDER_FORECAST calls directly after GRAPHICS_BOOT.
        ASSERT  CFG_FILE_MAX >= 256
        LD      A, (ASSET_BLOCK)
        LD      HL, CFG_FILE_BUFFER
        LD      C, BIOS_GETMEMBLKPAGES
        RST     08h
        JR      C, .FAIL
        LD      A, B                    ; EMM_FN5 reports the page count in B
        CP      GRAPHICS_ASSET_PAGES
        JR      NZ, .FAIL
        LD      A, (ASSET_SCRATCH_BLOCK)
        LD      C, DSS_FREEMEM
        RST     DSS
        XOR     A
        LD      (ASSET_SCRATCH_ALLOCATED), A
        OR      A
        RET
.FAIL_FREE:
        ; A failed depack has IFF cleared. Restore the ports before any DSS
        ; cleanup, then restore normal interrupt delivery.
        CALL    GRAPHICS_RESTORE_ASSET_WINDOWS
        EI
        CALL    GRAPHICS_FREE_ASSETS
        SCF
        RET
.FAIL:
        SCF
        RET

GRAPHICS_RESTORE_WINDOWS:
        LD      A, (GRAPHICS_SAVED_WIN0)
        OUT     (082h), A
        LD      A, (GRAPHICS_SAVED_WIN1)
        OUT     (0A2h), A
        LD      A, (GRAPHICS_SAVED_WIN3)
        OUT     (0E2h), A
        RET

; GRAPHICS_BOOT never changes WIN1: it may contain a live libman handle until
; the normal refresh cleanup.  Only restore the two ports borrowed by Hrust.
GRAPHICS_RESTORE_ASSET_WINDOWS:
        LD      A, (GRAPHICS_BOOT_SAVED_WIN0)
        OUT     (082h), A
        LD      A, (GRAPHICS_BOOT_SAVED_WIN3)
        OUT     (0E2h), A
        RET

GRAPHICS_CLOSE_PRIMARY:
        LD      A, (GRAPHICS_FILE_HANDLE)
        CP      0FFh
        JR      Z, .CLEAR
        LD      C, DSS_CLOSE_FILE
        RST     DSS
.CLEAR:
        LD      A, 0FFh
        LD      (GRAPHICS_FILE_HANDLE), A
        RET

GRAPHICS_BOOT_ERROR:
        CALL    GRAPHICS_FREE_ASSETS
        LD      HL, MSG_GRAPHICS_BOOT_ERROR
        CALL    PUTS_LN
        LD      B, EXIT_DLL
        JP      EXIT_PROGRAM

GRAPHICS_FREE_ASSETS:
        CALL    GRAPHICS_CLOSE_PRIMARY
.SCRATCH:
        LD      A, (ASSET_SCRATCH_ALLOCATED)
        OR      A
        JR      Z, .ASSETS
        LD      A, (ASSET_SCRATCH_BLOCK)
        LD      C, DSS_FREEMEM
        RST     DSS
        XOR     A
        LD      (ASSET_SCRATCH_ALLOCATED), A
.ASSETS:
        LD      A, (ASSET_ALLOCATED)
        OR      A
        RET     Z
        LD      A, (ASSET_BLOCK)
        LD      C, DSS_FREEMEM
        RST     DSS
        XOR     A
        LD      (ASSET_ALLOCATED), A
        RET

; Called once from the process exit path, after the network session unwind.
GRAPHICS_FINALIZE:
        ; Handle 0 is valid (see GRAPHICS_LOAD_LIBRARIES), so the pair is freed
        ; on the loaded flag.  Both handles are always set together.
        LD      A, (GRAPHICS_LIBS_LOADED)
        OR      A
        JR      Z, .ASSETS
        XOR     A
        LD      (GRAPHICS_LIBS_LOADED), A
        LD      HL, (AFNT_HANDLE)
        CALL    LIBMAN.l_free
        LD      HL, (GFX_HANDLE)
        CALL    LIBMAN.l_free
.ASSETS:
        CALL    FREE_UNET
        JP      GRAPHICS_FREE_ASSETS

; Z means that the validated backend already occupies its libman handle.
; NZ means that the normal loader path must load (or replace) it.
GRAPHICS_REUSE_UNET:
        LD      A, (STATE_FLAGS)
        AND     FLAG_DLL_LOADED
        JR      Z, .LOAD
        LD      A, (LOADED_BACKEND)
        LD      C, A
        LD      A, (BACKEND)
        CP      C
        RET     Z
        CALL    FREE_UNET
.LOAD:  OR      1
        RET

GRAPHICS_RENDER_FORECAST:
        ; Keep startup and all network traffic independent from graphics
        ; resource mapping. On refresh GRAPHICS_BOOT only rebuilds GFX's page
        ; list because the startup expansion already released its scratch page.
        CALL    GRAPHICS_BOOT
        JR      C, .BOOT_FAIL
        CALL    GRAPHICS_LOAD_LIBRARIES
        RET     C
        ; Compose the entire frame BEFORE switching the screen.  GFX320 renders
        ; into VIDEO_PAGE through its own window, and GFX_TARGET_BUF0 takes
        ; resolve_target's fixed path, which never reads RGMOD - so drawing does
        ; not depend on the current video mode.  Doing it first means the screen
        ; switches to a finished frame instead of a half-composed one.
        CALL    GRAPHICS_DRAW
        RET     C
        ; Preserve desktop state and enter the sole graphics mode used here.
        LD      C, DSS_GETVMOD
        RST     DSS
        LD      (GRAPHICS_OLD_MODE), A
        LD      A, B
        LD      (GRAPHICS_OLD_SCREEN), A
        LD      BC, 0050h
        LD      A, DSS_VMOD_G320
        LD      C, DSS_SETVMOD
        RST     DSS
        ; Never proceed on a failed mode switch: drawing 8bpp graphics through a
        ; text-mode screen layout is how a stray write reaches whatever the text
        ; mode has mapped there.
        JR      C, .MODE_FAIL
        CALL    GRAPHICS_FADE_IN
        ; WAITKEY spins on the keyboard ring buffer, which only the 50 Hz
        ; handler refills.  Entering it with interrupts disabled hangs the
        ; machine outright, so never take the caller's IFF on trust here.
.WAIT:  EI
        LD      C, DSS_KCLEAR
        RST     DSS
        LD      C, DSS_WAITKEY
        RST     DSS
        CP      27
        JR      Z, .EXIT
        CP      13
        JR      Z, .REFRESH
        CP      'R'
        JR      Z, .REFRESH
        CP      'r'
        JR      NZ, .WAIT
.REFRESH:
        CALL    GRAPHICS_FADE_OUT
        CALL    GRAPHICS_RESTORE_MODE
        JP      ATTEMPT_START
.EXIT:  CALL    GRAPHICS_FADE_OUT
        CALL    GRAPHICS_RESTORE_MODE
        LD      B, EXIT_OK
        JP      EXIT_PROGRAM
.MODE_FAIL:
        SCF
        RET
.BOOT_FAIL:
        LD      HL, MSG_GRAPHICS_BOOT_ERROR
        CALL    PUTS_LN
        SCF
        RET

GRAPHICS_LOAD_LIBRARIES:
        ; Not "is the handle zero": libman hands back a table index in L with
        ; H forced to 0, so the first library loaded owns handle 0 and testing
        ; the handle reloads GFX320 on every refresh, leaking a table slot and
        ; a two-page block each time.
        LD      A, (GRAPHICS_LIBS_LOADED)
        OR      A
        JR      NZ, .WINDOWS
        LD      HL, GFX_NAME
        LD      A, 1
        CALL    LIBMAN.l_load
        JR      C, .FAIL
        LD      (GFX_HANDLE), HL
        ; libman runs entry 0 as its load hook, but the library's own reference
        ; consumer (gfx320/test.asm) still calls GFX_INIT explicitly and checks
        ; the status.  Doing the same turns a rejected window layout into a
        ; reported code instead of a library left half-configured.
        LD      B, GFX_INIT
        CALL    LIBMAN.l_call
        JR      C, .FAIL
        OR      A
        JR      NZ, .FAIL_STATUS
        ; GFX320 copies the table into its own storage, so this consumes the
        ; list GRAPHICS_BOOT just collected in the borrowed config buffer.
        LD      DE, CFG_FILE_BUFFER
        LD      IX, GRAPHICS_ASSET_PAGES
        LD      B, GFX_SET_PAGE_TABLE
        CALL    LIBMAN.l_call
        JR      C, .FAIL
        OR      A
        JR      NZ, .FAIL
        LD      HL, AFNT_NAME
        LD      A, 1
        CALL    LIBMAN.l_load
        JR      C, .FAIL
        LD      (AFNT_HANDLE), HL
        LD      A, 1
        LD      (GRAPHICS_LIBS_LOADED), A
.WINDOWS:
        LD      HL, (GFX_HANDLE)
        LD      E, 3
        LD      B, GFX_SET_VRAM_WINDOW
        CALL    LIBMAN.l_call
        JR      C, .FAIL
        OR      A
        JR      NZ, .FAIL
        LD      HL, (AFNT_HANDLE)
        LD      E, 3
        LD      B, AFNT_SET_WINDOW
        CALL    LIBMAN.l_call
        JR      C, .FAIL
        XOR     A
        RET
.FAIL_STATUS:
.FAIL:  SCF
        RET

GRAPHICS_DRAW:
        ; black first, then compose and fade the final palette in.
        LD      HL, (GFX_HANDLE)
        LD      A, 0
        LD      E, GFX_TARGET_BUF0
        LD      B, GFX_CLEAR
        CALL    LIBMAN.l_call
        JP      C, .FAIL
        OR      A
        JP      NZ, .FAIL
        ; The palette sits at GRAPHICS_PALETTE_OFFSET inside asset page 4 and
        ; is mapped into WIN3: WIN0 is GFX320's tile source window, WIN1 is
        ; where libman maps the DLL for every l_call, and WIN2 holds this
        ; program and its stack.
        ; gfx_palette_load256 copies its 768 bytes out before it opens the VRAM
        ; window, and GFX320 saves/restores that window around every operation,
        ; so the asset page may stay mapped here.
        ;
        ; SETWIN3 (#3B), not the generic SETWIN (#38): the latter treats H=0 as
        ; an error and silently substitutes WIN1, which would page this program
        ; out from under itself.
        LD      A, (ASSET_BLOCK)
        LD      B, GRAPHICS_PALETTE_PAGE
        LD      C, DSS_SETWIN3
        RST     DSS
        JP      C, .FAIL
        LD      HL, (GFX_HANDLE)
        LD      DE, 0C000h + GRAPHICS_PALETTE_OFFSET
        LD      A, GFX_PAL_BUFFER0
        LD      B, GFX_PALETTE_LOAD256
        CALL    LIBMAN.l_call
        JP      C, .FAIL
        OR      A
        JP      NZ, .FAIL
        CALL    GRAPHICS_DRAW_CURRENT_ICON
        JP      C, .FAIL
        CALL    GRAPHICS_DRAW_DAY_ICONS
        JP      C, .FAIL
        CALL    GRAPHICS_DRAW_DAY_VALUES
        LD      DE, MSG_GRAPHICS_TITLE
        LD      IX, 12
        LD      IY, 8
        LD      A, 0Fh
        CALL    GRAPHICS_PRINT
        CALL    GRAPHICS_FORMAT_LOCATION
        LD      DE, CFG_FILE_BUFFER
        LD      IX, 12
        LD      IY, 28
        LD      A, 0Eh
        CALL    GRAPHICS_PRINT
        LD      DE, MSG_GRAPHICS_NOW
        LD      IX, 100
        LD      IY, 61
        LD      A, 0Bh
        CALL    GRAPHICS_PRINT
        LD      DE, (WX1_MODEL + WM_CURRENT + WC_TEMPERATURE)
        LD      IX, 100
        LD      IY, 80
        CALL    GRAPHICS_FORMAT_SIGNED_TENTHS
        CALL    GRAPHICS_APPEND_CELSIUS
        LD      DE, GRAPHICS_NUMBER
        LD      A, 0Fh
        CALL    GRAPHICS_PRINT
        LD      DE, MSG_GRAPHICS_HINT
        LD      IX, 12
        LD      IY, 238
        LD      A, 07h
        CALL    GRAPHICS_PRINT
        OR      A
        RET
.FAIL:
        SCF
        RET

; Days actually parsed, clamped to the six the layout has columns for.  Both
; day loops used to assume six unconditionally and would render whatever the
; model happened to hold past the end.  Z means there is nothing to draw.
GRAPHICS_DAY_COUNT:
        LD      A, (WX1_MODEL + WM_DAY_COUNT)
        CP      7
        JR      C, .CLAMPED
        LD      A, 6
.CLAMPED:
        OR      A
        RET

GRAPHICS_DRAW_CURRENT_ICON:
        LD      A, (WX1_MODEL + WM_CURRENT + WC_CODE)
        CALL    GRAPHICS_WMO_ICON
        LD      IX, 20
        LD      IY, 56
        LD      B, 16                   ; 64px icon
        LD      C, 4                    ; ...as 4x4 tiles
        JP      GRAPHICS_DRAW_TILES

GRAPHICS_DRAW_DAY_ICONS:
        LD      IX, WX1_MODEL + WM_DAYS
        LD      HL, DAY_ICON_X
        LD      (GRAPHICS_DAY_X_PTR), HL
        CALL    GRAPHICS_DAY_COUNT
        LD      (GRAPHICS_DAY_LEFT), A
        RET     Z
.NEXT:  LD      A, (IX + WD_CODE)
        LD      (GRAPHICS_DAY_MODEL_PTR), IX
        CALL    GRAPHICS_WMO_SMALL_ICON
        ; GRAPHICS_DRAW_TILES takes the TileRef array in HL, so the pointer
        ; GRAPHICS_WMO_SMALL_ICON just returned has to survive the X lookup
        ; below - which builds its own value in HL on the way to IX.
        PUSH    HL
        LD      IY, 158
        LD      DE, (GRAPHICS_DAY_X_PTR)
        LD      A, (DE)
        LD      L, A
        INC     DE
        LD      A, (DE)
        LD      H, A
        PUSH    HL
        POP     IX
        INC     DE
        LD      (GRAPHICS_DAY_X_PTR), DE
        POP     HL
        LD      B, 4                    ; 32px icon
        LD      C, 2                    ; ...as 2x2 tiles
        CALL    GRAPHICS_DRAW_TILES
        RET     C
        LD      IX, (GRAPHICS_DAY_MODEL_PTR)
        LD      DE, WM_DAY_SIZE
        ADD     IX, DE
        LD      A, (GRAPHICS_DAY_LEFT)
        DEC     A
        LD      (GRAPHICS_DAY_LEFT), A
        JR      NZ, .NEXT
        OR      A
        RET

; Each 32x32 pictogram has its low/high temperature directly underneath.
GRAPHICS_DRAW_DAY_VALUES:
        LD      IX, WX1_MODEL + WM_DAYS
        LD      HL, DAY_ICON_X
        LD      (GRAPHICS_DAY_X_PTR), HL
        CALL    GRAPHICS_DAY_COUNT
        LD      (GRAPHICS_DAY_LEFT), A
        RET     Z
.NEXT:  LD      (GRAPHICS_DAY_MODEL_PTR), IX
        LD      DE, (GRAPHICS_DAY_X_PTR)
        LD      A, (DE)
        LD      (GRAPHICS_NUMBER), A
        INC     DE
        LD      A, (DE)
        LD      H, A
        LD      A, (GRAPHICS_NUMBER)
        LD      L, A
        PUSH    HL
        POP     IX
        LD      IY, 198
        ; WD_MIN, not offset 0: the record starts with WD_YEAR, so reading from
        ; the base printed the year as tenths of a degree ("+202.6" for 2026).
        LD      HL, (GRAPHICS_DAY_MODEL_PTR)
        LD      DE, WD_MIN
        ADD     HL, DE
        LD      E, (HL)
        INC     HL
        LD      D, (HL)
        CALL    GRAPHICS_PRINT_SIGNED_TENTHS
        LD      IX, (GRAPHICS_DAY_MODEL_PTR)
        LD      DE, (GRAPHICS_DAY_X_PTR)
        LD      A, (DE)
        LD      (GRAPHICS_NUMBER), A
        INC     DE
        LD      A, (DE)
        LD      H, A
        LD      A, (GRAPHICS_NUMBER)
        LD      L, A
        PUSH    HL
        POP     IX
        LD      IY, 214
        LD      HL, (GRAPHICS_DAY_MODEL_PTR)
        LD      DE, WD_MAX
        ADD     HL, DE
        LD      E, (HL)
        INC     HL
        LD      D, (HL)
        CALL    GRAPHICS_PRINT_SIGNED_TENTHS
        LD      IX, (GRAPHICS_DAY_MODEL_PTR)
        LD      DE, WM_DAY_SIZE
        ADD     IX, DE
        LD      (GRAPHICS_DAY_MODEL_PTR), IX
        LD      HL, (GRAPHICS_DAY_X_PTR)
        INC     HL
        INC     HL
        LD      (GRAPHICS_DAY_X_PTR), HL
        LD      A, (GRAPHICS_DAY_LEFT)
        DEC     A
        LD      (GRAPHICS_DAY_LEFT), A
        JR      NZ, .NEXT
        OR      A
        RET

; HL = TileRef array, B = count, IX/IY = first tile position.
; Tile pages are 64 tiles wide, therefore every fourth item wraps a 64px row.
; HL = TileRef array, B = tile count, C = tiles per row, IX/IY = top-left.
; The row width used to be hardcoded to 4, which is right for the 64px icons
; but laid the 32px day icons out as a single 4-wide strip.
GRAPHICS_DRAW_TILES:
        LD      (GRAPHICS_TILE_REFS), HL
        LD      A, B
        LD      (GRAPHICS_TILE_LEFT), A
        LD      A, C
        LD      (GRAPHICS_TILE_WIDTH), A
        LD      (GRAPHICS_TILE_COLUMN), A
.NEXT:  LD      HL, (GRAPHICS_TILE_REFS)
        LD      E, (HL)
        INC     HL
        LD      D, (HL)
        INC     HL
        LD      (GRAPHICS_TILE_REFS), HL
        PUSH    IX
        PUSH    IY
        LD      HL, (GFX_HANDLE)
        LD      A, GFX_TARGET_BUF0 | GFX_KEY_FF
        LD      B, GFX_DRAW_TILE
        CALL    LIBMAN.l_call
        POP     IY
        POP     IX
        RET     C
        OR      A
        RET     NZ
        LD      DE, 16
        ADD     IX, DE
        LD      A, (GRAPHICS_TILE_LEFT)
        DEC     A
        LD      (GRAPHICS_TILE_LEFT), A
        JR      Z, .DONE
        LD      A, (GRAPHICS_TILE_COLUMN)
        DEC     A
        LD      (GRAPHICS_TILE_COLUMN), A
        JR      NZ, .NEXT
        LD      A, (GRAPHICS_TILE_WIDTH)
        LD      (GRAPHICS_TILE_COLUMN), A
        ADD     A, A                    ; row width in pixels = tiles * 16
        ADD     A, A
        ADD     A, A
        ADD     A, A
        LD      E, A
        LD      D, 0
        PUSH    IX
        POP     HL
        OR      A
        SBC     HL, DE
        PUSH    HL
        POP     IX
        LD      DE, 16
        ADD     IY, DE
        JR      .NEXT
.DONE:  OR      A
        RET

; A WMO code maps to one of the 15 asset icon families.  The index is
; deliberately conservative: an unknown code receives the generic cloud.
GRAPHICS_WMO_ICON:
        LD      HL, GRAPHICS_ICON_LARGE_REFS
        CP      1
        JR      C, .OFFSET
        CP      4
        JR      C, .SET1
        CP      45
        JR      C, .SET3
        CP      49
        JR      C, .SET4
        CP      58
        JR      C, .SET5
        CP      68
        JR      C, .SET7
        CP      78
        JR      C, .SET9
        CP      87
        JR      C, .SET12
        CP      95
        JR      C, .SET3
        LD      A, 13
        JR      .OFFSET
.SET1:  LD      A, 1
        JR      .OFFSET
.SET3:  LD      A, 3
        JR      .OFFSET
.SET4:  LD      A, 4
        JR      .OFFSET
.SET5:  LD      A, 5
        JR      .OFFSET
.SET7:  LD      A, 9
        JR      .OFFSET
.SET9:  LD      A, 11
        JR      .OFFSET
.SET12: LD      A, 12
.OFFSET:
        ; A 64px icon is 4x4 tiles, so GRAPHICS_ICON_LARGE_REFS holds 16 refs
        ; = 32 bytes per icon.  Stepping by 8 (the small-icon stride) only
        ; happened to look right for icon 0, whose offset is zero either way.
        LD      (GRAPHICS_ICON_INDEX), A
        LD      E, A
        LD      D, 0
        LD      B, 5                    ; index * 32
.STRIDE:
        SLA     E
        RL      D
        DJNZ    .STRIDE
        ADD     HL, DE
        RET

GRAPHICS_WMO_SMALL_ICON:
        CALL    GRAPHICS_WMO_ICON
        LD      A, (GRAPHICS_ICON_INDEX)
        LD      E, A
        LD      D, 0
        LD      HL, GRAPHICS_ICON_SMALL_REFS
        ADD     HL, DE
        ADD     HL, DE
        ADD     HL, DE
        ADD     HL, DE
        ADD     HL, DE
        ADD     HL, DE
        ADD     HL, DE
        ADD     HL, DE
        RET

GRAPHICS_PRINT:
        LD      HL, (AFNT_HANDLE)
        LD      B, AFNT_APRINT
        JP      LIBMAN.l_call

GRAPHICS_PRINT_SIGNED_TENTHS:
        CALL    GRAPHICS_FORMAT_SIGNED_TENTHS
        LD      DE, GRAPHICS_NUMBER
        LD      A, 0Fh
        JP      GRAPHICS_PRINT

; DE = signed tenths. Writes an ASCIIZ number into GRAPHICS_NUMBER.
GRAPHICS_FORMAT_SIGNED_TENTHS:
        LD      A, '+'
        BIT     7, D
        JR      Z, .SIGN
        LD      A, '-'
        LD      HL, 0
        OR      A
        SBC     HL, DE
        EX      DE, HL
.SIGN:  LD      (GRAPHICS_NUMBER), A
        EX      DE, HL
        CALL    GRAPHICS_DIV10
        LD      (GRAPHICS_NUMBER + 6), A
        LD      B, 0
.HUNDREDS:
        LD      DE, 100
        OR      A
        SBC     HL, DE
        JR      C, .TENS_START
        INC     B
        JR      .HUNDREDS
.TENS_START:
        ADD     HL, DE
        LD      C, 0
.TENS:  LD      DE, 10
        OR      A
        SBC     HL, DE
        JR      C, .WRITE
        INC     C
        JR      .TENS
.WRITE: ADD     HL, DE
        LD      A, B
        OR      A
        JR      Z, .NO_HUNDREDS
        ADD     A, '0'
        LD      (GRAPHICS_NUMBER + 1), A
        LD      A, C
        ADD     A, '0'
        LD      (GRAPHICS_NUMBER + 2), A
        LD      A, L
        ADD     A, '0'
        LD      (GRAPHICS_NUMBER + 3), A
        LD      A, '.'
        LD      (GRAPHICS_NUMBER + 4), A
        LD      A, (GRAPHICS_NUMBER + 6)
        ADD     A, '0'
        LD      (GRAPHICS_NUMBER + 5), A
        XOR     A
        LD      (GRAPHICS_NUMBER + 6), A
        JR      .OUT
.NO_HUNDREDS:
        LD      A, C
        ADD     A, '0'
        LD      (GRAPHICS_NUMBER + 1), A
        LD      A, L
        ADD     A, '0'
        LD      (GRAPHICS_NUMBER + 2), A
        LD      A, '.'
        LD      (GRAPHICS_NUMBER + 3), A
        LD      A, (GRAPHICS_NUMBER + 6)
        ADD     A, '0'
        LD      (GRAPHICS_NUMBER + 4), A
        XOR     A
        LD      (GRAPHICS_NUMBER + 5), A
.OUT:
        RET

; Append the unit to the just-formatted current temperature. The day columns
; continue to use the number-only wrapper above.
GRAPHICS_APPEND_CELSIUS:
        LD      HL, GRAPHICS_NUMBER
.FIND_END:
        LD      A, (HL)
        OR      A
        JR      Z, .APPEND
        INC     HL
        JR      .FIND_END
.APPEND:
        LD      (HL), ' '
        INC     HL
        LD      (HL), 'C'
        INC     HL
        LD      (HL), 0
        RET

; Compose location and country as one string so AFNT320's variable-width font
; determines their spacing naturally instead of two unrelated fixed X values.
; CFG_FILE_BUFFER is free here: GRAPHICS_BOOT's temporary physical-page list
; has already been consumed by GFX_SET_PAGE_TABLE.
GRAPHICS_FORMAT_LOCATION:
        LD      HL, WX1_MODEL + WM_LOCATION
        LD      DE, CFG_FILE_BUFFER
        CALL    GRAPHICS_COPY_Z_BODY
        LD      A, (WX1_MODEL + WM_COUNTRY)
        OR      A
        JR      Z, .DONE
        LD      A, ','
        LD      (DE), A
        INC     DE
        LD      A, ' '
        LD      (DE), A
        INC     DE
        LD      HL, WX1_MODEL + WM_COUNTRY
        CALL    GRAPHICS_COPY_Z_BODY
.DONE:
        XOR     A
        LD      (DE), A
        RET

; Copy ASCIIZ HL to DE without its terminator; return DE at the append point.
GRAPHICS_COPY_Z_BODY:
.NEXT:
        LD      A, (HL)
        OR      A
        RET     Z
        LD      (DE), A
        INC     HL
        INC     DE
        JR      .NEXT

; HL dividend -> HL quotient, A remainder.  This is the same restoring
; 16-bit divide used by the console renderer, kept local to the graphics UI.
GRAPHICS_DIV10:
        PUSH    IX
        PUSH    HL
        POP     IX
        LD      HL, 0
        LD      DE, 0
        LD      B, 16
.LOOP:  ADD     IX, IX
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
.NEXT:  DJNZ    .LOOP
        LD      A, E
        POP     IX
        RET

GRAPHICS_FADE_IN:
        LD      HL, (GFX_HANDLE)
        LD      A, GFX_FADE_IN
        LD      D, 16
        LD      E, GFX_PAL_BUFFER0
        LD      B, GFX_FADE_BEGIN
        CALL    LIBMAN.l_call
        RET     C
        ; gfx_fade_begin reports ERR_PALETTE/ERR_BUSY/ERR_ARGUMENT in A with
        ; carry clear; ignoring it leaves fade_active at 0 and the loop below
        ; exits immediately on a fade that never ran.
        OR      A
        JR      NZ, .FADE_FAIL
.LOOP:  CALL    GRAPHICS_FADE_DELAY
        LD      HL, (GFX_HANDLE)
        LD      B, GFX_FADE_STEP
        CALL    LIBMAN.l_call
        RET     C
        LD      A, E
        OR      A
        JR      NZ, .LOOP
        RET
.FADE_FAIL:
        SCF
        RET

GRAPHICS_FADE_OUT:
        LD      HL, (GFX_HANDLE)
        LD      A, GFX_FADE_OUT
        LD      D, 16
        LD      E, GFX_PAL_BUFFER0
        LD      B, GFX_FADE_BEGIN
        CALL    LIBMAN.l_call
        RET     C
        ; gfx_fade_begin reports ERR_PALETTE/ERR_BUSY/ERR_ARGUMENT in A with
        ; carry clear; ignoring it leaves fade_active at 0 and the loop below
        ; exits immediately on a fade that never ran.
        OR      A
        JR      NZ, .FADE_FAIL
.LOOP:  CALL    GRAPHICS_FADE_DELAY
        LD      HL, (GFX_HANDLE)
        LD      B, GFX_FADE_STEP
        CALL    LIBMAN.l_call
        RET     C
        LD      A, E
        OR      A
        JR      NZ, .LOOP
        RET
.FADE_FAIL:
        SCF
        RET

GRAPHICS_FADE_DELAY:
        LD      BC, 1800h
.LOOP:  DEC     BC
        LD      A, B
        OR      C
        JR      NZ, .LOOP
        RET

GRAPHICS_RESTORE_MODE:
        LD      A, (GRAPHICS_OLD_SCREEN)
        LD      B, A
        LD      A, (GRAPHICS_OLD_MODE)
        LD      C, DSS_SETVMOD
        RST     DSS
        CALL    GRAPHICS_RESTORE_WINDOWS
        RET

WFG_MAGIC:              DB "WFG1"
GFX_NAME:               DB "GFX320.DLL",0
AFNT_NAME:              DB "AFNT320.DLL",0
DAY_ICON_X:             DW 8,60,112,164,216,268
