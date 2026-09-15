; IX is the command-tail pointer supplied by DSS at EXE entry: (IX)=length,
; (IX+1)=text. Classic DSS uses load-#80; current Estex uses load-#100+3.
; Do not infer the address from the load origin or a particular DSS revision.
; Return HL=minutes; carry on anything except an optional 1..1440 decimal.
L_PARSE_INTERVAL:
        PUSH    IX
        POP     HL
        LD      A, (HL)
        INC     HL
        LD      B, A
        LD      DE, 0
.LEAD:  LD      A, B
        OR      A
        JR      Z, .DEFAULT
        LD      A, (HL)
        CP      ' '
        JR      NZ, .START
        INC     HL
        DJNZ    .LEAD
        JR      .DEFAULT
.START: XOR     A
        LD      (L_DIGITS), A
        LD      DE, 0
.DIGIT: LD      A, B
        OR      A
        JR      Z, .TRAIL
        LD      A, (HL)
        CP      ' '
        JR      Z, .TRAIL
        CP      '0'
        JR      C, .BAD
        CP      '9'+1
        JR      NC, .BAD
        SUB     '0'
        LD      C, A
        LD      A, (L_DIGITS)
        INC     A
        CP      5
        JR      NC, .BAD
        LD      (L_DIGITS), A
        ; DE = DE * 10 + digit. Four digits fit in 16 bits.
        PUSH    HL                      ; preserve PSP cursor while DE holds value
        EX      DE, HL
        ADD     HL, HL
        PUSH    HL
        ADD     HL, HL
        ADD     HL, HL
        POP     DE
        ADD     HL, DE
        LD      E, C
        LD      D, 0
        ADD     HL, DE
        EX      DE, HL
        POP     HL
        INC     HL
        DJNZ    .DIGIT
.TRAIL: LD      A, B
        OR      A
        JR      Z, .RANGE
        LD      A, (HL)
        CP      ' '
        JR      NZ, .BAD
        INC     HL
        DJNZ    .TRAIL
.RANGE: LD      A, (L_DIGITS)
        OR      A
        JR      Z, .BAD
        EX      DE, HL
        LD      A, H
        OR      L
        JR      Z, .BAD
        LD      DE, 1440
        OR      A
        SBC     HL, DE
        JR      C, .VALID
        JR      Z, .VALID
        JR      .BAD
.VALID: ADD     HL, DE
        OR      A
        RET
.DEFAULT:
        LD      HL, 5
        OR      A
        RET
.BAD:   SCF
        RET
