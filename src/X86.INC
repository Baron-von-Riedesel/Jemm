
;--- page table flags

PTF_PRESENT equ 001h
PTF_RW      equ 002h
PTF_USER    equ 004h
PTF_PWT     equ 008h ; page write through
PTF_PCD     equ 010h ; page cache disable
PTF_ACCESS  equ 020h ; page accessed
PTF_DIRTY   equ 040h ; page dirty
PTF_4MB     equ 080h ; PDEs: 4MB PDE
PTF_GBL     equ 100h ; page global (P3+)

;--- features, returned by CPUID in EDX
CF_FPU      equ 0001h
CF_VME      equ 0002h
CF_DE       equ 0004h;debugging ext
CF_PSE      equ 0008h;Page Size Ext (4MB)
CF_TSC      equ 0010h;Time Stamp Counter
CF_MSR      equ 0020h;RDMSR/WRMSR supported
CF_PAE      equ 0040h;Physical Address Ext
CF_MCE      equ 0080h;Machine Check Exceptions
CF_CX8      equ 0100h;CMPXCHG8B supported
CF_APIC     equ 0200h;APIC exists
;rsvd       equ 0400h;
CF_SEP      equ 0800h;SYSENTER/SYSEXIT supported
CF_MTRR     equ 1000h
CF_PGE      equ 2000h

;--- flags in CR4
CR4_VME      equ 01h
CR4_PVI      equ 02h
CR4_TSD      equ 04h;1=time stamp disable
CR4_DE       equ 08h
CR4_PSE      equ 10h;1=page size extensions enabled
CR4_PAE      equ 20h
CR4_MCE      equ 40h
CR4_PGE      equ 80h

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

