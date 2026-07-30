; Graphical Weather Forecast frontend.
; The shared client implementation lives in weatherc.asm and is selected by
; this build-time switch.  WEATHER.EXE runs from WIN1; all DLL handles use
; WIN2 and WIN3 remains available to ISA/VRAM code.

        DEFINE  WEATHER_GRAPHICS 1
        INCLUDE "weatherc.asm"
