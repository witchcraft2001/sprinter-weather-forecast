; WEATHER.EXE graphics frontend.  All dynamic drawing is delegated to
; GFX320.DLL and AFNT320.DLL; this module only owns UI layout and resources.

AFNT_APRINT             EQU 3
AFNT_SET_WINDOW         EQU 4
BIOS_GETMEMBLKPAGES     EQU 0C5h
GFX_REQUIRED_CAPS       EQU GFX_CAP_ACCEL | GFX_CAP_KEY_FF | GFX_CAP_PALETTE_RGB8 | GFX_CAP_FADE | GFX_CAP_TILES | GFX_CAP_WIN0_SOURCE

; Steps of GRAPHICS_BEGIN_ATTEMPT.  They all report the same text-mode message,
; because a failure here means there is no working AFNT320 to draw a graphical
; one; GRAPHICS_INIT_STEP records which of them was running.
GSTAGE_BOOT             EQU 1
GSTAGE_GFX_LOAD         EQU 2
GSTAGE_GFX_INIT         EQU 3
GSTAGE_GFX_PAGES        EQU 4
GSTAGE_AFNT_LOAD        EQU 5
GSTAGE_GFX_WINDOW       EQU 6
GSTAGE_AFNT_WINDOW      EQU 7
GSTAGE_PALETTE          EQU 8
GSTAGE_VMODE            EQU 9
GSTAGE_SCREEN           EQU 10

        INCLUDE "graphics_assets.inc"

; The primary loader has already allocated and expanded this block before it
; transfers control to START. The runtime only obtains the physical page list
; GFX320 needs; it has no knowledge of Hrust or the EXE resource tail.
GRAPHICS_BOOT:
        LD      A, (ASSET_ALLOCATED)
        OR      A
        JP      Z, .FAIL
        ; BIOS EMM_FN5 documents a destination that must accept up to 256 bytes
        ; (one byte per page of the block plus a #FF terminator), and there is
        ; no room for that in this WIN2-resident image.  Borrow the
        ; config file buffer before CONFIG_LOAD uses it. Only the five page
        ; numbers are retained.
        ;
        ; Writing the list straight into a GRAPHICS_ASSET_PAGES-sized field
        ; overruns it into GRAPHICS_SAVED_WIN0/WIN1/WIN3, and those bytes are
        ; then pushed into the page ports by GRAPHICS_RESTORE_WINDOWS.
        ; GFX_SET_PAGE_TABLE copies the list into the DLL immediately, so the
        ; buffer only has to survive until GRAPHICS_LOAD_LIBRARIES runs - which
        ; GRAPHICS_BEGIN_ATTEMPT calls directly after GRAPHICS_BOOT.
        ASSERT  CFG_FILE_MAX >= 256
        LD      A, (ASSET_BLOCK)
        LD      HL, CFG_FILE_BUFFER
        LD      C, BIOS_GETMEMBLKPAGES
        RST     08h
        JR      C, .FAIL
        LD      A, B                    ; EMM_FN5 reports the page count in B
        CP      GRAPHICS_ASSET_PAGES
        JR      NZ, .FAIL
        OR      A
        RET
.FAIL:
        SCF
        RET

GRAPHICS_FREE_ASSETS:
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
        LD      A, (GRAPHICS_MODE_ACTIVE)
        OR      A
        JR      Z, .LIBRARIES
        CALL    GRAPHICS_FADE_OUT
        CALL    GRAPHICS_RESTORE_MODE
        XOR     A
        LD      (GRAPHICS_MODE_ACTIVE), A
.LIBRARIES:
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

; Load the graphical frontend once, then redraw its progress screen for every
; retry without unloading the libraries or returning to text mode.
GRAPHICS_BEGIN_ATTEMPT:
        LD      A, (GRAPHICS_MODE_ACTIVE)
        OR      A
        JR      NZ, .STATUS
        CALL    GRAPHICS_INIT_STEP
        DB      GSTAGE_BOOT
        CALL    GRAPHICS_BOOT
        JR      C, .FAIL
        CALL    GRAPHICS_LOAD_LIBRARIES
        JR      C, .FAIL
        CALL    GRAPHICS_INIT_STEP
        DB      GSTAGE_PALETTE
        CALL    GRAPHICS_LOAD_PALETTE
        JR      C, .FAIL
        CALL    GRAPHICS_INIT_STEP
        DB      GSTAGE_VMODE
        LD      C, DSS_GETVMOD
        RST     DSS
        LD      (GRAPHICS_OLD_MODE), A
        LD      A, B
        LD      (GRAPHICS_OLD_SCREEN), A
        LD      BC, 0050h
        LD      A, DSS_VMOD_G320
        LD      C, DSS_SETVMOD
        RST     DSS
        JR      C, .FAIL
        LD      A, 1
        LD      (GRAPHICS_MODE_ACTIVE), A
        CALL    GRAPHICS_INIT_STEP
        DB      GSTAGE_SCREEN
        LD      HL, MSG_GRAPHICS_STAGE
        CALL    GRAPHICS_SHOW_STATUS_SCREEN
        JR      C, .ACTIVE_FAIL
        CALL    GRAPHICS_FADE_IN
        JR      C, .ACTIVE_FAIL
        RET
.STATUS:
        LD      HL, MSG_GRAPHICS_STAGE
        CALL    GRAPHICS_SHOW_STATUS_SCREEN
        RET     NC
.ACTIVE_FAIL:
        CALL    GRAPHICS_RESTORE_MODE
        XOR     A
        LD      (GRAPHICS_MODE_ACTIVE), A
.FAIL:
        SCF
        RET

; The step id follows the CALL as one byte.  This is not a console marker: it
; only records which step is running, so that the text-mode error path in
; weatherc.asm can name it.  Written this way because the steps below are
; entered with values already in A, B, C, DE and HL - this form touches no
; register and no flag, so the call can sit anywhere.
GRAPHICS_INIT_STEP:
        EX      (SP), HL
        PUSH    AF
        LD      A, (HL)
        LD      (GRAPHICS_INIT_STAGE), A
        POP     AF
        INC     HL
        EX      (SP), HL
        RET

GRAPHICS_RENDER_FORECAST:
        CALL    GRAPHICS_FADE_OUT
        RET     C
        CALL    GRAPHICS_DRAW
        RET     C
        CALL    GRAPHICS_FADE_IN
        RET     C
        ; WAITKEY spins on the keyboard ring buffer, which only the 50 Hz
        ; handler refills.  Entering it with interrupts disabled hangs the
        ; machine outright, so never take the caller's IFF on trust here.
.WAIT:  EI
        LD      C, DSS_KCLEAR
        RST     DSS
        LD      C, DSS_WAITKEY
        RST     DSS
        OR      A
        JR      NZ, .ASCII
        LD      A, D                    ; extended key position code
        AND     7Fh
        CP      3Bh                     ; F1, verified against DSS key table
        JR      NZ, .WAIT
        CALL    GRAPHICS_SHOW_HELP
        RET     C
        JR      .WAIT
.ASCII:
        CP      27
        JR      Z, .EXIT
        CP      13
        JR      Z, .REFRESH
        CP      'R'
        JR      Z, .REFRESH
        CP      'r'
        JR      NZ, .WAIT
.REFRESH:
        JP      ATTEMPT_START
.EXIT:
        LD      B, EXIT_OK
        JP      EXIT_PROGRAM

GRAPHICS_LOAD_LIBRARIES:
        ; Not "is the handle zero": libman hands back a table index in L with
        ; H forced to 0, so the first library loaded owns handle 0 and testing
        ; the handle reloads GFX320 on every refresh, leaking a table slot and
        ; a two-page block each time.
        LD      A, (GRAPHICS_LIBS_LOADED)
        OR      A
        JR      NZ, .WINDOWS
        CALL    GRAPHICS_INIT_STEP
        DB      GSTAGE_GFX_LOAD
        LD      HL, GFX_NAME
        LD      A, 1
        CALL    LIBMAN.l_load
        JR      C, .FAIL
        LD      (GFX_HANDLE), HL
        ; libman runs entry 0 as its load hook, but the library's own reference
        ; consumer (gfx320/test.asm) still calls GFX_INIT explicitly and checks
        ; the status.  Doing the same turns a rejected window layout into a
        ; reported code instead of a library left half-configured.
        CALL    GRAPHICS_INIT_STEP
        DB      GSTAGE_GFX_INIT
        LD      B, GFX_INIT
        CALL    LIBMAN.l_call
        JR      C, .FAIL_GFX
        OR      A
        JR      NZ, .FAIL_GFX
        ; GFX320 copies the table into its own storage, so this consumes the
        ; list GRAPHICS_BOOT just collected in the borrowed config buffer.
        CALL    GRAPHICS_INIT_STEP
        DB      GSTAGE_GFX_PAGES
        LD      DE, CFG_FILE_BUFFER
        LD      IX, GRAPHICS_ASSET_PAGES
        LD      B, GFX_SET_PAGE_TABLE
        CALL    LIBMAN.l_call
        JR      C, .FAIL_GFX
        OR      A
        JR      NZ, .FAIL_GFX
        CALL    GRAPHICS_INIT_STEP
        DB      GSTAGE_AFNT_LOAD
        LD      HL, AFNT_NAME
        LD      A, 1
        CALL    LIBMAN.l_load
        JR      C, .FAIL_GFX
        LD      (AFNT_HANDLE), HL
        LD      A, 1
        LD      (GRAPHICS_LIBS_LOADED), A
.WINDOWS:
        CALL    GRAPHICS_INIT_STEP
        DB      GSTAGE_GFX_WINDOW
        LD      HL, (GFX_HANDLE)
        LD      E, 3
        LD      B, GFX_SET_VRAM_WINDOW
        CALL    LIBMAN.l_call
        JR      C, .FAIL
        OR      A
        JR      NZ, .FAIL
        CALL    GRAPHICS_INIT_STEP
        DB      GSTAGE_AFNT_WINDOW
        LD      HL, (AFNT_HANDLE)
        LD      E, 3
        LD      B, AFNT_SET_WINDOW
        CALL    LIBMAN.l_call
        JR      C, .FAIL
        XOR     A
        RET
.FAIL_GFX:
        LD      HL, (GFX_HANDLE)
        CALL    LIBMAN.l_free
.FAIL:  SCF
        RET

; HL points to a CP866 ASCIIZ status/error message.
; This full-screen form is used only when entering the progress state. Later
; network transitions update the status band in place.
GRAPHICS_SHOW_STATUS_SCREEN:
        LD      DE, MSG_GRAPHICS_BUSY_HINT
        LD      A, 0Eh
        JR      GRAPHICS_SHOW_MESSAGE

GRAPHICS_SHOW_STATUS:
        PUSH    HL
        CALL    GRAPHICS_CLEAR_STATUS
        JR      C, .DROP_FAIL
        POP     DE
        LD      IX, 12
        LD      IY, 92
        LD      A, 0Eh
        JP      GRAPHICS_PRINT
.DROP_FAIL:
        POP     HL
        SCF
        RET

GRAPHICS_SHOW_ERROR:
        PUSH    HL
        LD      DE, MSG_GRAPHICS_HINT
        LD      A, 0Ch
        CALL    GRAPHICS_SHOW_MESSAGE
        POP     HL
        RET     NC
        ; A graphics-library failure cannot itself be reported graphically.
        ; Restore the DSS screen before using the sole permitted text fallback.
GRAPHICS_ERROR_FALLBACK:
        LD      A, (GRAPHICS_MODE_ACTIVE)
        OR      A
        JR      Z, .CONSOLE
        CALL    GRAPHICS_RESTORE_MODE
        XOR     A
        LD      (GRAPHICS_MODE_ACTIVE), A
.CONSOLE:
        CALL    PUTS_LN
        OR      A
        RET

GRAPHICS_SHOW_MESSAGE:
        LD      (GRAPHICS_MESSAGE_COLOR), A
        PUSH    DE
        PUSH    HL
        CALL    GRAPHICS_CLEAR
        JR      C, .DROP_FAIL
        LD      DE, MSG_GRAPHICS_TITLE
        LD      IX, 12
        LD      IY, 8
        LD      A, 0Fh
        CALL    GRAPHICS_PRINT
        POP     DE
        LD      IX, 12
        LD      IY, 92
        LD      A, (GRAPHICS_MESSAGE_COLOR)
        CALL    GRAPHICS_PRINT
        JR      C, .FOOTER_FAIL
        POP     DE
        LD      IX, 12
        LD      IY, 238
        LD      A, 07h
        JP      GRAPHICS_PRINT
.FOOTER_FAIL:
        POP     DE
        SCF
        RET
.DROP_FAIL:
        POP     HL
        POP     DE
        SCF
        RET

; Full-screen help is intentionally self-contained and returns to the already
; validated forecast without touching CFG, UNET or the model.
GRAPHICS_SHOW_HELP:
        CALL    GRAPHICS_FADE_OUT
        RET     C
        CALL    GRAPHICS_CLEAR
        RET     C
        CALL    GRAPHICS_BUFFER_START
        LD      HL, MSG_GRAPHICS_HELP_VERSION
        CALL    GRAPHICS_BUFFER_APPEND
        LD      A, (LOADED_BACKEND)
        CP      BACKEND_WIFI
        LD      HL, MSG_GRAPHICS_HELP_BACKEND_ESP
        JR      Z, .VERSION_BACKEND
        LD      HL, MSG_GRAPHICS_HELP_BACKEND_RTL
.VERSION_BACKEND:
        CALL    GRAPHICS_BUFFER_APPEND
        CALL    GRAPHICS_BUFFER_DONE
        LD      HL, GRAPHICS_HELP_LINES
        LD      (GRAPHICS_DAY_MODEL_PTR), HL
        LD      A, 6
        LD      (GRAPHICS_DAY_LEFT), A
        LD      IY, 12
.LINE:
        LD      HL, (GRAPHICS_DAY_MODEL_PTR)
        LD      E, (HL)
        INC     HL
        LD      D, (HL)
        INC     HL
        LD      (GRAPHICS_DAY_MODEL_PTR), HL
        LD      IX, 12
        LD      A, 0Fh
        PUSH    IY
        CALL    GRAPHICS_PRINT
        POP     IY
        RET     C
        LD      DE, 28
        ADD     IY, DE
        LD      A, (GRAPHICS_DAY_LEFT)
        DEC     A
        LD      (GRAPHICS_DAY_LEFT), A
        JR      NZ, .LINE
        CALL    GRAPHICS_FADE_IN
        RET     C
        LD      C, DSS_WAITKEY
        RST     DSS
        CALL    GRAPHICS_FADE_OUT
        RET     C
        CALL    GRAPHICS_DRAW
        RET     C
        JP      GRAPHICS_FADE_IN

; ATTEMPT_FINISH uses this for errors. If graphics initialization itself
; failed, retain the console fallback because AFNT320 is unavailable.
GRAPHICS_RENDER_PROMPT:
        LD      A, (GRAPHICS_MODE_ACTIVE)
        OR      A
        JP      Z, TEXT_RENDER_PROMPT
        LD      DE, MSG_GRAPHICS_HINT
        LD      IX, 12
        LD      IY, 238
        LD      A, 07h
        JP      GRAPHICS_PRINT

GRAPHICS_CLEAR:
        LD      HL, (GFX_HANDLE)
        LD      A, 0
        LD      E, GFX_TARGET_BUF0
        LD      B, GFX_CLEAR
        CALL    LIBMAN.l_call
        RET     C
        OR      A
        RET     Z
        SCF
        RET

; Erase only the changing progress line. This avoids full-screen flashes
; between CONNECT, SEND and RECV while keeping stale longer text invisible.
GRAPHICS_CLEAR_STATUS:
        LD      HL, (GFX_HANDLE)
        LD      DE, GRAPHICS_STATUS_RECT
        LD      B, GFX_FILL_RECT
        CALL    LIBMAN.l_call
        RET     C
        OR      A
        RET     Z
        SCF
        RET

GRAPHICS_LOAD_PALETTE:
        ; Palette page is ordinary asset memory. GFX320 copies all 768 bytes
        ; before opening its VRAM window, so WIN3 may be reused by UNET later.
        LD      A, (ASSET_BLOCK)
        LD      B, GRAPHICS_PALETTE_PAGE
        LD      C, DSS_SETWIN3
        RST     DSS
        RET     C
        LD      HL, (GFX_HANDLE)
        LD      DE, 0C000h + GRAPHICS_PALETTE_OFFSET
        LD      A, GFX_PAL_BUFFER0
        LD      B, GFX_PALETTE_LOAD256
        CALL    LIBMAN.l_call
        RET     C
        OR      A
        RET     Z
        SCF
        RET

GRAPHICS_DRAW:
        CALL    GRAPHICS_CLEAR
        JP      C, .FAIL
        CALL    GRAPHICS_PREPARE_DAYS
        CALL    GRAPHICS_DRAW_CURRENT_ICON
        JP      C, .FAIL
        CALL    GRAPHICS_DRAW_DAY_ICONS
        JP      C, .FAIL
        CALL    GRAPHICS_DRAW_DAY_VALUES
        JP      C, .FAIL
        CALL    GRAPHICS_DRAW_HEADER
        JP      C, .FAIL
        CALL    GRAPHICS_DRAW_CURRENT_TEXT
        JP      C, .FAIL
        CALL    GRAPHICS_DRAW_FOOTER
        JP      C, .FAIL
        OR      A
        RET
.FAIL:
        SCF
        RET

GRAPHICS_DRAW_HEADER:
        LD      DE, MSG_GRAPHICS_TITLE
        LD      IX, 12
        LD      IY, 4
        LD      A, 0Fh
        CALL    GRAPHICS_PRINT
        RET     C
        CALL    GRAPHICS_FORMAT_LOCATION
        LD      DE, CFG_FILE_BUFFER
        LD      IX, 12
        LD      IY, 16
        LD      A, 0Eh
        CALL    GRAPHICS_PRINT
        RET     C
        CALL    GRAPHICS_BUFFER_START
        LD      HL, MSG_UPDATED
        CALL    GRAPHICS_BUFFER_APPEND
        LD      IX, WX1_MODEL + WM_CURRENT
        CALL    GRAPHICS_BUFFER_APPEND_DATE_TIME
        CALL    GRAPHICS_BUFFER_DONE
        LD      IX, 12
        LD      IY, 28
        LD      A, 07h
        JP      GRAPHICS_PRINT_BUFFER

GRAPHICS_DRAW_CURRENT_TEXT:
        CALL    GRAPHICS_BUFFER_START
        LD      HL, MSG_NOW
        CALL    GRAPHICS_BUFFER_APPEND
        LD      DE, (WX1_MODEL + WM_CURRENT + WC_TEMPERATURE)
        CALL    GRAPHICS_BUFFER_APPEND_SIGNED
        LD      HL, MSG_CELSIUS
        CALL    GRAPHICS_BUFFER_APPEND
        CALL    GRAPHICS_BUFFER_DONE
        LD      IX, 92
        LD      IY, 48
        LD      A, 0Fh
        CALL    GRAPHICS_PRINT_BUFFER
        RET     C

        LD      A, (WX1_MODEL + WM_CURRENT + WC_CODE)
        CALL    GRAPHICS_WMO_DESCRIPTION
        EX      DE, HL
        LD      IX, 92
        LD      IY, 60
        LD      A, 0Bh
        CALL    GRAPHICS_PRINT
        RET     C

        CALL    GRAPHICS_BUFFER_START
        LD      HL, MSG_GRAPHICS_FEELS
        CALL    GRAPHICS_BUFFER_APPEND
        LD      DE, (WX1_MODEL + WM_CURRENT + WC_APPARENT)
        CALL    GRAPHICS_BUFFER_APPEND_SIGNED
        LD      HL, MSG_CELSIUS
        CALL    GRAPHICS_BUFFER_APPEND
        CALL    GRAPHICS_BUFFER_DONE
        LD      IY, 72
        CALL    GRAPHICS_PRINT_FIELD
        RET     C

        CALL    GRAPHICS_BUFFER_START
        LD      HL, MSG_HUMIDITY
        CALL    GRAPHICS_BUFFER_APPEND
        LD      A, (WX1_MODEL + WM_CURRENT + WC_HUMIDITY)
        CALL    GRAPHICS_BUFFER_APPEND_U8
        LD      A, '%'
        CALL    GRAPHICS_BUFFER_CHAR
        CALL    GRAPHICS_BUFFER_DONE
        LD      IY, 84
        CALL    GRAPHICS_PRINT_FIELD
        RET     C

        CALL    GRAPHICS_BUFFER_START
        LD      HL, MSG_WIND
        CALL    GRAPHICS_BUFFER_APPEND
        LD      DE, (WX1_MODEL + WM_CURRENT + WC_WIND)
        CALL    GRAPHICS_BUFFER_APPEND_UNSIGNED_TENTHS
        LD      HL, MSG_METERS_PER_SECOND
        CALL    GRAPHICS_BUFFER_APPEND
        LD      A, ','
        CALL    GRAPHICS_BUFFER_CHAR
        LD      A, ' '
        CALL    GRAPHICS_BUFFER_CHAR
        LD      DE, (WX1_MODEL + WM_CURRENT + WC_DIRECTION)
        CALL    GRAPHICS_DIRECTION
        CALL    GRAPHICS_BUFFER_APPEND
        CALL    GRAPHICS_BUFFER_DONE
        LD      IY, 96
        CALL    GRAPHICS_PRINT_FIELD
        RET     C

        CALL    GRAPHICS_BUFFER_START
        LD      HL, MSG_GRAPHICS_MINMAX
        CALL    GRAPHICS_BUFFER_APPEND
        LD      IX, (GRAPHICS_TODAY_MODEL_PTR)
        LD      E, (IX + WD_MIN)
        LD      D, (IX + WD_MIN + 1)
        CALL    GRAPHICS_BUFFER_APPEND_SIGNED
        LD      A, '/'
        CALL    GRAPHICS_BUFFER_CHAR
        LD      IX, (GRAPHICS_TODAY_MODEL_PTR)
        LD      E, (IX + WD_MAX)
        LD      D, (IX + WD_MAX + 1)
        CALL    GRAPHICS_BUFFER_APPEND_SIGNED
        CALL    GRAPHICS_BUFFER_DONE
        LD      IY, 108
        CALL    GRAPHICS_PRINT_FIELD
        RET     C

        CALL    GRAPHICS_BUFFER_START
        LD      HL, MSG_GRAPHICS_PRECIP
        CALL    GRAPHICS_BUFFER_APPEND
        LD      IX, (GRAPHICS_TODAY_MODEL_PTR)
        LD      A, (IX + WD_PRECIPITATION)
        CALL    GRAPHICS_BUFFER_APPEND_U8
        LD      A, '%'
        CALL    GRAPHICS_BUFFER_CHAR
        LD      A, ','
        CALL    GRAPHICS_BUFFER_CHAR
        LD      A, ' '
        CALL    GRAPHICS_BUFFER_CHAR
        LD      HL, MSG_WIND_MAX
        CALL    GRAPHICS_BUFFER_APPEND
        LD      IX, (GRAPHICS_TODAY_MODEL_PTR)
        LD      E, (IX + WD_WIND)
        LD      D, (IX + WD_WIND + 1)
        CALL    GRAPHICS_BUFFER_APPEND_UNSIGNED_TENTHS
        LD      HL, MSG_METERS_PER_SECOND
        CALL    GRAPHICS_BUFFER_APPEND
        CALL    GRAPHICS_BUFFER_DONE
        LD      IY, 120
        JP      GRAPHICS_PRINT_FIELD

GRAPHICS_DRAW_FOOTER:
        CALL    GRAPHICS_BUFFER_START
        LD      HL, WX1_MODEL + WM_SOURCE
        CALL    GRAPHICS_BUFFER_APPEND
        LD      A, (BACKEND)
        CP      BACKEND_WIFI
        LD      HL, MSG_GRAPHICS_BACKEND_WIFI
        JR      Z, .BACKEND
        LD      HL, MSG_GRAPHICS_BACKEND_RTL
.BACKEND:
        CALL    GRAPHICS_BUFFER_APPEND
        CALL    GRAPHICS_BUFFER_DONE
        LD      IX, 8
        LD      IY, 224
        LD      A, 0Bh
        CALL    GRAPHICS_PRINT_BUFFER
        RET     C
        LD      DE, MSG_GRAPHICS_HINT
        LD      IX, 8
        LD      IY, 240
        LD      A, 07h
        JP      GRAPHICS_PRINT

GRAPHICS_PREPARE_DAYS:
        LD      HL, WX1_MODEL + WM_DAYS
        LD      (GRAPHICS_TODAY_MODEL_PTR), HL
        LD      DE, WM_DAY_SIZE
        ADD     HL, DE
        LD      (GRAPHICS_DAY_BASE), HL
        RET

; Days actually parsed, clamped to the six the layout has columns for.  Both
; day loops used to assume six unconditionally and would render whatever the
; model happened to hold past the end.  Z means there is nothing to draw.
GRAPHICS_DAY_COUNT:
        LD      A, (WX1_MODEL + WM_DAY_COUNT)
        OR      A
        RET     Z
        DEC     A                       ; first D belongs to the current block
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
        LD      IX, (GRAPHICS_DAY_BASE)
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
        LD      IY, 148
        CALL    GRAPHICS_DAY_COLUMN
        LD      HL, (GRAPHICS_DAY_X_PTR)
        INC     HL
        INC     HL
        LD      (GRAPHICS_DAY_X_PTR), HL
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
        JP      NZ, .NEXT
        OR      A
        RET

; Each future-day card contains weekday/date, low/high and precipitation.
; A day column is too narrow for the "Osadki" caption the current block uses,
; so a droplet tile marks the percentage as precipitation probability instead
; of humidity; the number moves right to make room for it.
DAY_PRECIP_ICON_Y       EQU 204
DAY_PRECIP_TEXT_DX      EQU 18
GRAPHICS_DRAW_DAY_VALUES:
        LD      IX, (GRAPHICS_DAY_BASE)
        LD      HL, DAY_ICON_X
        LD      (GRAPHICS_DAY_X_PTR), HL
        CALL    GRAPHICS_DAY_COUNT
        LD      (GRAPHICS_DAY_LEFT), A
        RET     Z
.NEXT:  LD      (GRAPHICS_DAY_MODEL_PTR), IX
        LD      IY, 136
        CALL    GRAPHICS_FORMAT_DAY_LABEL
        CALL    GRAPHICS_DAY_COLUMN
        LD      A, 0Eh
        CALL    GRAPHICS_PRINT_NUMBER
        RET     C

        CALL    GRAPHICS_DAY_COLUMN
        LD      IY, 184
        ; WD_MIN, not offset 0: the record starts with WD_YEAR, so reading from
        ; the base printed the year as tenths of a degree ("+202.6" for 2026).
        LD      HL, (GRAPHICS_DAY_MODEL_PTR)
        LD      DE, WD_MIN
        ADD     HL, DE
        LD      E, (HL)
        INC     HL
        LD      D, (HL)
        CALL    GRAPHICS_PRINT_SIGNED_TENTHS
        CALL    GRAPHICS_DAY_COLUMN
        LD      IY, 196
        LD      HL, (GRAPHICS_DAY_MODEL_PTR)
        LD      DE, WD_MAX
        ADD     HL, DE
        LD      E, (HL)
        INC     HL
        LD      D, (HL)
        CALL    GRAPHICS_PRINT_SIGNED_TENTHS
        RET     C

        LD      IX, (GRAPHICS_DAY_MODEL_PTR)
        LD      A, (IX + WD_PRECIPITATION)
        CALL    GRAPHICS_FORMAT_U8
        LD      HL, GRAPHICS_NUMBER
.PERCENT_END:
        LD      A, (HL)
        OR      A
        JR      Z, .PERCENT
        INC     HL
        JR      .PERCENT_END
.PERCENT:
        LD      (HL), '%'
        INC     HL
        LD      (HL), 0
        ; The formatted percentage stays in GRAPHICS_NUMBER across the tile
        ; call: GRAPHICS_DRAW_TILES keeps its own state and does not touch it.
        CALL    GRAPHICS_DAY_COLUMN
        LD      IY, DAY_PRECIP_ICON_Y
        LD      HL, GRAPHICS_UTILITY_REFS + 6 ; droplet, 16x16 as one tile
        LD      B, 1
        LD      C, 1
        CALL    GRAPHICS_DRAW_TILES
        RET     C
        CALL    GRAPHICS_DAY_COLUMN
        LD      DE, DAY_PRECIP_TEXT_DX
        ADD     IX, DE
        LD      IY, 208
        LD      A, 0Bh
        CALL    GRAPHICS_PRINT_NUMBER
        RET     C
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
        JP      NZ, .NEXT
        OR      A
        RET

; IX = left edge of the card being drawn.  Each value in a card needs it and
; every print in between clobbers IX, so the lookup is shared.
GRAPHICS_DAY_COLUMN:
        LD      DE, (GRAPHICS_DAY_X_PTR)
        LD      A, (DE)
        LD      L, A
        INC     DE
        LD      A, (DE)
        LD      H, A
        PUSH    HL
        POP     IX
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

GRAPHICS_PRINT_BUFFER:
        LD      DE, CFG_FILE_BUFFER
        JP      GRAPHICS_PRINT

; Every grey field of the current-conditions block shares one left edge and one
; colour; only the row differs, so callers set IY and come here.
GRAPHICS_PRINT_FIELD:
        LD      IX, 92
        LD      A, 07h
        JP      GRAPHICS_PRINT_BUFFER

GRAPHICS_PRINT_NUMBER:
        LD      DE, GRAPHICS_NUMBER
        JP      GRAPHICS_PRINT

GRAPHICS_BUFFER_START:
        LD      HL, CFG_FILE_BUFFER
        LD      (GRAPHICS_BUFFER_PTR), HL
        RET

GRAPHICS_BUFFER_START_NUMBER:
        LD      HL, GRAPHICS_NUMBER
        LD      (GRAPHICS_BUFFER_PTR), HL
        RET

; Append ASCIIZ HL without its terminator to the active formatting buffer.
GRAPHICS_BUFFER_APPEND:
        LD      DE, (GRAPHICS_BUFFER_PTR)
        CALL    GRAPHICS_COPY_Z_BODY
        LD      (GRAPHICS_BUFFER_PTR), DE
        RET

GRAPHICS_BUFFER_CHAR:
        LD      HL, (GRAPHICS_BUFFER_PTR)
        LD      (HL), A
        INC     HL
        LD      (GRAPHICS_BUFFER_PTR), HL
        RET

GRAPHICS_BUFFER_DONE:
        XOR     A
        JP      GRAPHICS_BUFFER_CHAR

GRAPHICS_BUFFER_APPEND_SIGNED:
        CALL    GRAPHICS_FORMAT_SIGNED_TENTHS
        LD      HL, GRAPHICS_NUMBER
        JR      GRAPHICS_BUFFER_APPEND

GRAPHICS_BUFFER_APPEND_UNSIGNED_TENTHS:
        CALL    GRAPHICS_FORMAT_SIGNED_TENTHS
        LD      HL, GRAPHICS_NUMBER + 1 ; positive values: omit the '+'
        JR      GRAPHICS_BUFFER_APPEND

GRAPHICS_BUFFER_APPEND_U8:
        CALL    GRAPHICS_FORMAT_U8
        LD      HL, GRAPHICS_NUMBER
        JR      GRAPHICS_BUFFER_APPEND

; A -> decimal ASCIIZ in GRAPHICS_NUMBER.
GRAPHICS_FORMAT_U8:
        LD      C, A
        LD      B, 0
.HUNDREDS:
        CP      100
        JR      C, .TENS_START
        SUB     100
        INC     B
        JR      .HUNDREDS
.TENS_START:
        LD      C, A
        LD      D, 0
.TENS:
        CP      10
        JR      C, .WRITE
        SUB     10
        INC     D
        JR      .TENS
.WRITE:
        LD      C, A
        LD      HL, GRAPHICS_NUMBER
        LD      A, B
        OR      A
        JR      Z, .NO_HUNDREDS
        ADD     A, '0'
        LD      (HL), A
        INC     HL
.NO_HUNDREDS:
        LD      A, B
        OR      D
        JR      Z, .ONES
        LD      A, D
        ADD     A, '0'
        LD      (HL), A
        INC     HL
.ONES: LD      A, C
        ADD     A, '0'
        LD      (HL), A
        INC     HL
        LD      (HL), 0
        RET

; A 0..99 -> two decimal characters in the active buffer.
GRAPHICS_BUFFER_APPEND_TWO:
        LD      B, '0'
.TENS:
        CP      10
        JR      C, .WRITE
        SUB     10
        INC     B
        JR      .TENS
.WRITE:
        LD      C, A
        LD      A, B
        CALL    GRAPHICS_BUFFER_CHAR
        LD      A, C
        ADD     A, '0'
        JP      GRAPHICS_BUFFER_CHAR

; IX current-record date/time -> DD.MM HH:MM.
GRAPHICS_BUFFER_APPEND_DATE_TIME:
        LD      A, (IX + WC_DAY)
        CALL    GRAPHICS_BUFFER_APPEND_TWO
        LD      A, '.'
        CALL    GRAPHICS_BUFFER_CHAR
        LD      A, (IX + WC_MONTH)
        CALL    GRAPHICS_BUFFER_APPEND_TWO
        LD      A, ' '
        CALL    GRAPHICS_BUFFER_CHAR
        LD      A, (IX + WC_HOUR)
        CALL    GRAPHICS_BUFFER_APPEND_TWO
        LD      A, ':'
        CALL    GRAPHICS_BUFFER_CHAR
        LD      A, (IX + WC_MINUTE)
        JP      GRAPHICS_BUFFER_APPEND_TWO

; IX day record -> "ПН DD.MM" in GRAPHICS_NUMBER.
GRAPHICS_FORMAT_DAY_LABEL:
        PUSH    IX
        CALL    GRAPHICS_WEEKDAY
        ADD     A, A
        LD      E, A
        LD      D, 0
        LD      HL, GRAPHICS_WEEKDAY_TABLE
        ADD     HL, DE
        LD      E, (HL)
        INC     HL
        LD      D, (HL)
        EX      DE, HL
        PUSH    HL                      ; START_NUMBER uses HL for destination
        CALL    GRAPHICS_BUFFER_START_NUMBER
        POP     HL
        CALL    GRAPHICS_BUFFER_APPEND
        LD      A, ' '
        CALL    GRAPHICS_BUFFER_CHAR
        POP     IX
        LD      A, (IX + WD_DAY)
        CALL    GRAPHICS_BUFFER_APPEND_TWO
        LD      A, '.'
        CALL    GRAPHICS_BUFFER_CHAR
        LD      A, (IX + WD_MONTH)
        CALL    GRAPHICS_BUFFER_APPEND_TWO
        JP      GRAPHICS_BUFFER_DONE

; Gregorian weekday, 0=Sunday. Sakamoto's formula; IX points at a day record.
GRAPHICS_WEEKDAY:
        LD      L, (IX + WD_YEAR)
        LD      H, (IX + WD_YEAR + 1)
        LD      A, (IX + WD_MONTH)
        CP      3
        JR      NC, .YEAR_READY
        DEC     HL
.YEAR_READY:
        LD      (GRAPHICS_NUMBER), HL
        LD      (GRAPHICS_NUMBER + 2), HL
        LD      BC, 4
        CALL    GRAPHICS_QUOTIENT
        LD      DE, (GRAPHICS_NUMBER + 2)
        ADD     HL, DE
        LD      (GRAPHICS_NUMBER + 2), HL
        LD      HL, (GRAPHICS_NUMBER)
        LD      BC, 100
        CALL    GRAPHICS_QUOTIENT
        EX      DE, HL
        LD      HL, (GRAPHICS_NUMBER + 2)
        OR      A
        SBC     HL, DE
        LD      (GRAPHICS_NUMBER + 2), HL
        LD      HL, (GRAPHICS_NUMBER)
        LD      BC, 400
        CALL    GRAPHICS_QUOTIENT
        LD      DE, (GRAPHICS_NUMBER + 2)
        ADD     HL, DE
        LD      A, (IX + WD_MONTH)
        DEC     A
        LD      E, A
        LD      D, 0
        PUSH    HL
        LD      HL, GRAPHICS_MONTH_OFFSETS
        ADD     HL, DE
        LD      A, (HL)
        POP     HL
        LD      E, A
        LD      D, 0
        ADD     HL, DE
        LD      A, (IX + WD_DAY)
        LD      E, A
        ADD     HL, DE
        LD      BC, 7
        CALL    WX1_MOD16
        LD      A, L
        RET

; HL / BC -> HL quotient (small date values; remainder discarded).
GRAPHICS_QUOTIENT:
        LD      DE, 0
.LOOP: OR      A
        SBC     HL, BC
        JR      C, .DONE
        INC     DE
        JR      .LOOP
.DONE: EX      DE, HL
        RET

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
        RET

GFX_NAME:               DB "GFX320.DLL",0
AFNT_NAME:              DB "AFNT320.DLL",0
GRAPHICS_STATUS_RECT:
        DW      0                       ; x
        DB      80                      ; y
        DW      320                     ; width
        DW      32                      ; height
        DB      0                       ; black
        DB      GFX_TARGET_BUF0         ; flags/target
        DB      0, 0, 0                 ; reserved
        ASSERT  $ - GRAPHICS_STATUS_RECT = GFX_FILL_RECT_SIZE
DAY_ICON_X:             DW 8,60,112,164,216,268
GRAPHICS_MONTH_OFFSETS: DB 0,3,2,5,0,3,5,1,4,6,2,4
GRAPHICS_WEEKDAY_TABLE:
        DW      MSG_DAY_SUN, MSG_DAY_MON, MSG_DAY_TUE, MSG_DAY_WED
        DW      MSG_DAY_THU, MSG_DAY_FRI, MSG_DAY_SAT
GRAPHICS_HELP_LINES:
        DW      MSG_GRAPHICS_HELP_TITLE, CFG_FILE_BUFFER
        DW      MSG_GRAPHICS_HELP_AUTHOR, MSG_GRAPHICS_HELP_1
        DW      MSG_GRAPHICS_HELP_2, MSG_GRAPHICS_HELP_RETURN
