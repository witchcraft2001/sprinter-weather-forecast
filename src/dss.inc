; Minimal Weather Forecast DSS bindings, verified against Estex-DSS.
; Keep this local: neither the application nor UNETLD should depend on a
; backend kit's private copy of dss.inc.

        IFNDEF  _DSS_INC
        DEFINE  _DSS_INC

DSS                     EQU 010h

DSS_OPEN_FILE           EQU 011h
DSS_CLOSE_FILE          EQU 012h
DSS_READ_FILE           EQU 013h
DSS_MOVE_FP             EQU 015h
DSS_WAITKEY             EQU 030h
DSS_KCLEAR              EQU 035h
DSS_SETWIN1             EQU 039h
DSS_SETWIN3             EQU 03Bh
DSS_GETMEM              EQU 03Dh
DSS_FREEMEM             EQU 03Eh
DSS_EXIT                EQU 041h
DSS_ENVIRON             EQU 046h
DSS_APPINFO             EQU 047h
DSS_SETVMOD             EQU 050h
DSS_GETVMOD             EQU 051h
DSS_PUTCHAR             EQU 05Bh
DSS_PCHARS              EQU 05Ch

ENV_GET                 EQU 001h
APPINFO_EXE_HOMEDIR     EQU 001h

SEEK_END                EQU 2
FM_READ                 EQU 1
E_FILE_NOT_FOUND        EQU 3
DSS_VMOD_G320           EQU 081h

        ENDIF
