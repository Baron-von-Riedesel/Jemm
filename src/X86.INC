
;--- page table flags

PTF_PRESENT equ 1
PTF_RW      equ 2
PTF_USER    equ 4
PTF_WT      equ 8
PTF_4MB     equ 80h

;--- descriptor

DESCRIPTOR struct
wLimit  dw ?    ;+0
wA0015  dw ?    ;+2
bA1623  db ?    ;+4
bAttr   db ?    ;+5
bLimEx  db ?    ;+6
bA2431  db ?    ;+7
DESCRIPTOR ends        

GATE struct
wOfsLo dw ?
wSeg   dw ?
wAttr  dw ?
wOfsHi dw ?
GATE ends

;--- TSS structure
;--- the only fields in the TSS which are needed are tsEsp0, tsSS0
;--- and tsOfs. Jemm386 will never switch tasks.

TSSSEG  struct
        dd ?    ;+00 selector
tsEsp0  dd ?    ;+04
tsSS0   dd ?    ;+08
        dq ?    ;+0C
        dq ?    ;+14
tsCR3   dd ?    ;+1C
tsEip   dd ?    ;+20
tsEfl   dd ?    ;+24
tsEax   dd ?    ;+28
tsEcx   dd ?    ;+2C
tsEdx   dd ?    ;+30
tsEbx   dd ?    ;+34
tsEsp   dd ?    ;+38
tsEbp   dd ?    ;+3C
tsEsi   dd ?    ;+40
tsEdi   dd ?    ;+44
tsES    dd ?    ;+48
tsCS    dd ?    ;+4C
tsSS    dd ?    ;+50
tsDS    dd ?    ;+54
tsFS    dd ?    ;+58
tsGS    dd ?    ;+5C
tsLDTR  dd ?    ;+60
tsFlags dw ?    ;+64
tsOfs   dw ?    ;+66
TSSSEG  ends

;--- stack frame for PUSHAD

PUSHADS struct
rEDI    dd ?
rESI    dd ?
rEBP    dd ?
        dd ?    ;reserved
rEBX    dd ?
rEDX    dd ?
rECX    dd ?
rEAX    dd ?
PUSHADS ends

;--- IRET stack frame for 32bit protected-mode

IRETD32 struct
_Eip    dd ?    ;+0
_Cs     dd ?    ;+4 
_Efl    dd ?    ;+8
IRETD32 ends

;--- stack frame expected by ring0-IRETD to switch to v86-mode

IRETDV86 struct
_Eip    dd ?    ;+0
_Cs     dd ?    ;+4 
_Efl    dd ?    ;+8
_Esp    dd ?    ;+12
_Ss     dd ?    ;+16
_Es     dd ?    ;+20
_Ds     dd ?    ;+24
_Fs     dd ?    ;+28
_Gs     dd ?    ;+32
IRETDV86 ends

;--- bit positions of CPUID edx
CPUID_VME equ 1		; =2
CPUID_PGE equ 13	; =2000h
CPUID_PAT equ 16	; =10000h

