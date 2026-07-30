; Hrust 1.x depacker used by Kode (DEPACK/DePack.asm).
;
; Contract: HL = packed stream, DE = destination.  The caller guarantees a
; valid Hrust stream and a 16 KiB destination page.  It runs entirely from
; the application page, so source and destination may live in WIN2/WIN3.
;
; Original compact implementation is retained verbatim apart from the public
; label and formatting.  Host-side round-trip tests validate every stream.

HRUST_DEPACK:
        DI
        LD      IX,#FFF4
        ADD     IX,SP
        PUSH    DE
        LD      SP,HL
        POP     BC
        EX      DE,HL
        POP     BC
        DEC     BC
        ADD     HL,BC
        EX      DE,HL
        POP     BC
        DEC     BC
        ADD     HL,BC
        SBC     HL,DE
        ADD     HL,DE
        JR      C,.l8018
        LD      D,H
        LD      E,L
.l8018:
        LDDR
        EX      DE,HL
        LD      D,(IX+#0B)
        LD      E,(IX+#0A)
        LD      SP,HL
        POP     HL
        POP     HL
        POP     HL
        LD      B,#06
.l8027:
        DEC     SP
        POP     AF
        LD      (IX+#06),A
        INC     IX
        DJNZ    .l8027
        EXX
        LD      D,#BF
        LD      BC,#1010
        POP     HL
.l8037:
        DEC     SP
        POP     AF
        EXX
.l803a:
        LD      (DE),A
        INC     DE
.l803c:
        EXX
.l803d:
        ADD     HL,HL
        DJNZ    .l8042
        POP     HL
        LD      B,C
.l8042:
        JR      C,.l8037
        LD      E,#01
.l8046:
        LD      A,#80
.l8048:
        ADD     HL,HL
        DJNZ    .l804d
        POP     HL
        LD      B,C
.l804d:
        RLA
        JR      C,.l8048
        CP      #03
        JR      C,.l8059
        ADD     A,E
        LD      E,A
        XOR     C
        JR      NZ,.l8046
.l8059:
        ADD     A,E
        CP      #04
        JR      Z,.l80b8
        ADC     A,#FF
        CP      #02
        EXX
.l8063:
        LD      C,A
.l8064:
        EXX
        LD      A,#BF
        JR      C,.l807d
.l8069:
        ADD     HL,HL
        DJNZ    .l806e
        POP     HL
        LD      B,C
.l806e:
        RLA
        JR      C,.l8069
        JR      Z,.l8078
        INC     A
        ADD     A,D
        JR      NC,.l807f
        SUB     D
.l8078:
        INC     A
        JR      NZ,.l8087
        LD      A,#EF
.l807d:
        RRCA
        CP      A
.l807f:
        ADD     HL,HL
        DJNZ    .l8084
        POP     HL
        LD      B,C
.l8084:
        RLA
        JR      C,.l807f
.l8087:
        EXX
        LD      H,#FF
        JR      Z,.l8092
        LD      H,A
        DEC     SP
        INC     A
        JR      Z,.l809d
        POP     AF
.l8092:
        LD      L,A
        ADD     HL,DE
        LDIR
.l8096:
        JR      .l803c
.l8098:
        EXX
        RRC     D
        JR      .l803d
.l809d:
        POP     AF
        CP      #E0
        JR      C,.l8092
        RLCA
        XOR     C
        INC     A
        JR      Z,.l8098
        SUB     #10
.l80a9:
        LD      L,A
        LD      C,A
        LD      H,#FF
        ADD     HL,DE
        LDI
        DEC     SP
        POP     AF
        LD      (DE),A
        INC     HL
        INC     DE
        LD      A,(HL)
        JR      .l803a
.l80b8:
        LD      A,#80
.l80ba:
        ADD     HL,HL
        DJNZ    .l80bf
        POP     HL
        LD      B,C
.l80bf:
        ADC     A,A
        JR      NZ,.l80db
        JR      C,.l80ba
        LD      A,#FC
        JR      .l80de
.l80c8:
        DEC     SP
        POP     BC
        LD      C,B
        LD      B,A
        CCF
        JR      .l8064
.l80cf:
        CP      #0F
        JR      C,.l80c8
        JR      NZ,.l8063
        ADD     A,#F4
        LD      SP,IX
        JR      .l80ef
.l80db:
        SBC     A,A
        LD      A,#EF
.l80de:
        ADD     HL,HL
        DJNZ    .l80e3
        POP     HL
        LD      B,C
.l80e3:
        RLA
        JR      C,.l80de
        EXX
        JR      NZ,.l80a9
        BIT     7,A
        JR      Z,.l80cf
        SUB     #EA
.l80ef:
        EX      DE,HL
.l80f0:
        POP     DE
        LD      (HL),E
        INC     HL
        LD      (HL),D
        INC     HL
        DEC     A
        JR      NZ,.l80f0
        EX      DE,HL
        JR      NC,.l8096
        RET
