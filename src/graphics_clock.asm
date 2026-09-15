; A=decimal 0..59, DE=destination. Append two zero-padded digits. AFNT320's
; digit 1 is four pixels wide, while the other digits are six. Character #FF
; is a blank one-pixel glyph, so two of them keep every displayed digit six
; pixels wide and let the caller place the clock against a fixed right edge.
GRAPHICS_CLOCK_2D:
        LD      C, A
        LD      B, 0
.TENS:  LD      A, C
        CP      10
        JR      C, .WRITE
        SUB     10
        LD      C, A
        INC     B
        JR      .TENS
.WRITE: LD      A, B
        CALL    .DIGIT
        LD      A, C
.DIGIT:
        ADD     A, '0'
        LD      (DE), A
        INC     DE
        CP      '1'
        RET     NZ
        LD      A, 0FFh
        LD      (DE), A
        INC     DE
        LD      (DE), A
        INC     DE
        RET
