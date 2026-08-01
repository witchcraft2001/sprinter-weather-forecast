; Graphical Weather Forecast frontend.
; The shared client implementation lives in weatherc.asm and is selected by
; this build-time switch. The PRELOAD loader places the resident runtime and
; stack in WIN2; libman maps called DLLs through WIN1, while WIN3 is reused by
; UNET and the video libraries according to the current operation.

        DEFINE  WEATHER_GRAPHICS 1
        INCLUDE "weatherc.asm"
