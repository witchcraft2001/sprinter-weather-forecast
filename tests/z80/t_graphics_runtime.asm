; Execute the assembled loader's entry/parser, then the assembled runtime.
; IRQs drive a simulated RTC; production EI/HALT and all timer/clock code run
; unchanged. Only file/page loading, network entry and DSS/DLL I/O are replaced.
        DEVICE NOSLOT64K
        INCLUDE "runtime_symbols.inc"
        ORG 0
        JP START
        DS 010h-$,0
        JP DSS_MOCK
        DS 038h-$,0
        JP IRQ
        DS 0100h-$,0
        INCLUDE "harness.inc"
START:
        LD SP,0DF00h
        IM 1
        CALL T_BEGIN
        LD IX,PSP_ADDRESS
        LD (IX-3),7                     ; PRELOAD EXE handle
        LD (IX),2
        LD (IX+1),' '
        LD (IX+2),'0'+INTERVAL
        LD A,0C3h
        LD (L_ARG_OK),A
        LD HL,PARSED
        LD (L_ARG_OK+1),HL
        JP 08100h                       ; actual primary-loader entry
PARSED:
        LD DE,INTERVAL
        OR A
        SBC HL,DE
        LD A,1
        CALL T_EXPECT_Z
        ADD HL,DE
        LD (RUNTIME_IMAGE+6),HL          ; loader handoff, before page replacement
        LD HL,RUNTIME_IMAGE
        LD DE,08100h
        LD BC,RUNTIME_SIZE
        LDIR
        LD A,0C3h
        LD (R_ATTEMPT_START),A
        LD HL,ATTEMPT
        LD (R_ATTEMPT_START+1),HL
        LD (R_LIBCALL),A
        LD HL,DLL_MOCK
        LD (R_LIBCALL+1),HL
        LD A,7
        JP 08100h
ATTEMPT:
        LD HL,(R_INTERVAL)
        LD DE,INTERVAL
        OR A
        SBC HL,DE
        LD A,2
        CALL T_EXPECT_Z
        LD HL,ATTEMPT_DUE
        LD (R_ATTEMPT_START+1),HL
        LD A,1
        LD (R_MODE_ACTIVE),A
        LD B,0
        JP R_ATTEMPT_FINISH             ; real cleanup/re-arm/event loop
ATTEMPT_DUE:
        LD HL,(ELAPSED)
        LD DE,(EXPECTED)
        OR A
        SBC HL,DE
        LD A,3
        CALL T_EXPECT_Z
        LD A,(ATTEMPTS)
        DEC A
        LD (ATTEMPTS),A
        JR Z,.DONE
        LD HL,INTERVAL*120
        LD (EXPECTED),HL
        LD B,0
        JP R_ATTEMPT_FINISH
.DONE:
        DI
        CALL T_END
        HALT
DSS_MOCK:
        LD A,C
        CP 021h
        JR Z,.TIME
        CP 031h
        JR Z,.SCAN
        LD A,4
        CALL T_FAIL
        DI
        CALL T_END
        HALT
.SCAN:
        XOR A
        RET
.TIME:
        LD A,(SECOND)
        LD B,A
        LD C,1
        LD HL,0908h
        LD DE,0101h
        LD IX,2026
        OR A
        RET
IRQ:
        PUSH AF
        PUSH HL
        LD HL,FRAMES
        INC (HL)
        LD A,(HL)
        CP 50
        JR C,.DONE
        LD (HL),0
        LD HL,(ELAPSED)
        INC HL
        LD (ELAPSED),HL
.SECOND:
        LD HL,SECOND
        INC (HL)
        LD A,(HL)
        CP 60
        JR C,.DONE
        LD (HL),0
.DONE:
        POP HL
        POP AF
        EI
        RETI
DLL_MOCK:
        XOR A
        RET
FRAMES: DB 0
SECOND: DB 0
ELAPSED: DW 0
EXPECTED: DW INTERVAL*60
ATTEMPTS: DB 2
        DS 02000h-$,0
RUNTIME_IMAGE:
        INCBIN "runtime_test.bin"
RUNTIME_SIZE EQU $-RUNTIME_IMAGE
        DS 08100h-$,0
        INCBIN "loader_test.bin"
