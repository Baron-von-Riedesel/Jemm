
;--- these files contains things for 32-bit ONLY

?RING0EXC       EQU 1       ; 1=display more infos on exc in ring 0
?ROMRO          EQU 1       ; 1=make ROM page FF000 r/o
;?ALTBOOT       EQU 1       ; 1=support ALTBOOT option
?MMASK          EQU 1       ; 1=trap DMA master mask port (0F, DE)
?INVLPG         EQU 1       ; 1=use INVLPG opcode on 80486+
?CLEARHIGHESP   EQU 1       ; 1=clear hiword(esp) for buggy VCPI clients
?AUXOUT         EQU 0       ; 1=use COM1 for output, 0=use int 10h/29h
?USEINT10       EQU 1       ; 1=use int 10h for output, 0=use int 29h
?SERVTABLE      equ 1       ; 1=expose service table (for JLoad)
?FASTMON        equ 1       ; 1=faster monitor jmp for int 00-0F
?SHAREDGDT      equ 1       ; 1=place GDT in shared address space
?EXC10          equ 1       ; 1=detect exception 10h (floating point)
?I41SUPP        equ 1       ; 1=support Int 41h in protected-mode
?ALT_TRAPHDL    equ 1       ; v5.85: 1=call alternate trap handler for system ports
ifndef ?SHAREDIDT
?SHAREDIDT      equ 0       ; std=?, 1=place IDT in shared address space
endif

?CODEIN2PAGE    EQU 0       ; 1=move code away from first page
?USETRIPLEFAULT EQU 0       ; 1=use triple fault to reboot
?SAFEKEYBOARD   equ 0       ; 1=use original vector for int 16h kbd poll
?DYNTRAPP60     equ 1       ; 1=trap port 60h conditionally only

GDT_SIZE        equ 200h    ; size of GDT

;--- the following equates define Jemm's memory layout:
;--- Jemm starts at 110000h with data and code (4-5 pages)
;--- system space is F8000000h-F83FFFFFh:
;---  + 0000h: reserved (uncommitted)
;---  + 1000h: page directory
;---  + 2000h: page table 0
;---  + 3000h: system page table
;---  + 4000h: ring 0 stack (4k)
;---  + 5000h: task state segment
;---  + a: page pool descriptors, EMS handle/status tables
;---  + b: shadowed HMA (if XMS handle array is in HMA)
;---  + c: DMA buffer
;---  + d: scratch region for physical page mapping

?BASE           EQU 110000h         ; base of Jemm 32bit code
?SYSBASE        EQU 0F8000000h      ; system space
?SYSLINEAR      EQU ?SYSBASE+1000h
?PAGEDIR        EQU ?SYSBASE+1000h  ; linear address page dir
?PAGETAB0       EQU 1000h           ; offset for page table 0
?PAGETABSYS     EQU 2000h           ; offset for system page table
?TOS            EQU ?SYSLINEAR + 3000h + 1000h  ;top of ring 0 stack
?TSSLEN         EQU 68h+32+2000h+8  ; size of TSS "segment"

;--- other constants

@XBDA           EQU 40Eh            ; segment of XBDA
@MEM_SIZE       EQU 413h            ; base memory size in KB
@KB_FLAG        EQU 417H            ; Status SHIFT/CTRL/ALT etcetera.
@RESET_FLAG     EQU 472H            ; Flag for Warmboot (=1234h)

if ?DMAPT or ?VDS
?DMABUFFMAX     EQU 128             ; max DMA-Buffer size in kB
endif

?FASTENTRIES    equ 32

;--- page table flags

PTF_PRESENT equ 1
PTF_RW      equ 2
PTF_USER    equ 4
PTF_WT      equ 8
PTF_4MB     equ 80h

;--- EMS constants

;-- 32M max EMS memory (in 16K EMS page units), always even
;-- this constant is also defined in Jemm386c.c

EMS_MAX_HANDLES         EQU 255 ; std=255, the EMS handle is a byte value
EMS_MAX_PAGES_ALLOWED   EQU 800h; 2048*16 = 32 MB
EMS_MAXSTATE            EQU 64  ; std=64, number of EMS save state items

;--- EMS status codes

EMSS_OK                 equ 00h
EMSS_SOFTWARE_ERR       equ 80h ;unexpected error
EMSS_HARDWARE_ERR       equ 81h ;should never occur with EMM emulators
EMSS_EMM_BUSY           equ 82h ;should never occur with EMS 3.2+
EMSS_INVALID_HANDLE     equ 83h
EMSS_INVALID_FUNCTION   equ 84h ;function code in AH not defined
EMSS_NO_MORE_HANDLES    equ 85h ;all handles in use
EMSS_CONTEXT_EXISTS     equ 86h ;45h: try to free a handle with saved context
EMSS_OUT_OF_PAGES       equ 87h ;43h, 51h, 5A00h, 5A01h
EMSS_OUT_OF_FREE_PAGES  equ 88h ;43h, 51h, 5A00h, 5A01h
EMSS_ZERO_PAGES         equ 89h ;43h
EMSS_LOG_PAGE_INVALID   equ 8Ah ;44h, 50h, 55h, 56h, 57h
EMSS_PHYS_PAGE_INVALID  equ 8Bh ;44h, 4Fh, 50h, 55h, 56h
EMSS_CONTEXT_STACK_FULL equ 8Ch ;46h
EMSS_STATE_ALREADY_SAVED equ 8Dh;47h
EMSS_NO_STATE_IS_SAVED  equ 8Eh ;48h
EMSS_INVALID_SUBFUNC    equ 8Fh ;4Eh, 4Fh, 50h, 52h, 53h, 54h, 57h, 58h, 59h, 5Bh
EMSS_UNDEF_ATTR_TYPE    equ 90h ;
EMSS_FEATURE_UNSUPP     equ 91h ;52h
EMSS_OVERLAP_OCCURED    equ 92h ;5700h
EMSS_LENGTH_EXCEEDED    equ 93h ;57h
EMSS_CONVEMS_OVERLAPP   equ 94h ;57h (jemm never returns this code)
EMSS_OFFS_EXCEEDS_PGSIZ equ 95h ;57h
EMSS_REGLEN_EXCEEDS_1MB equ 96h ;57h
EMSS_REGIONS_OVERLAPP   equ 97h ;5701h
EMSS_TYPE_UNDEFINED     equ 98h ;57h
EMSS_ALT_MAPS_UNSUPP    equ 9Ch ;5B01h, 5B04h, 5B06h, 5B07h, 5B08h
EMSS_INVALID_ALT_MAP    equ 9Dh ;5Bh (jemm never returns this code)
EMSS_MBBOUNDARY_CROSSED equ 0A2h;57h
EMSS_SRC_ARRAY_INVALID  equ 0A3h;4E01h, 5B01h
EMSS_ACCESS_DENIED      equ 0A4h;5Bh

;--- EMS handle descriptor

EMSHD struct
ehd_wIdx    dw ?    ;index of EMSPD for first page
ehd_bFlags  db ?
ehd_bSS     db ?    ;saved state index
EMSHD ends

;--- values for flags

EMSH_USED   equ 1

EMSSTAT struct
dPg0    dd ?
dPg1    dd ?
dPg2    dd ?
dPg3    dd ?
EMSSTAT ends

;--- flags for pool descriptor block

PBF_DONTEXPAND  EQU 1   ; don't try to expand this block
PBF_DONTFREE    EQU 2   ; don't try to free this block

DESCRIPTOR struct
wLimit  dw ?    ;+0
wA0015  dw ?    ;+2
bA1623  db ?    ;+4
bAttr   db ?    ;+5
bLimEx  db ?    ;+6
bA2431  db ?    ;+7
DESCRIPTOR ends        

;--- selector definitions
;--- FLAT_CODE_SEL must be first descriptor in GDT

FLAT_CODE_SEL   equ 1 * sizeof DESCRIPTOR
FLAT_DATA_SEL   equ 2 * sizeof DESCRIPTOR
V86_TSS_SEL     equ 3 * sizeof DESCRIPTOR
REAL_CODE_SEL   equ 4 * sizeof DESCRIPTOR
REAL_DATA_SEL   equ 5 * sizeof DESCRIPTOR
if ?CLEARHIGHESP
V86_STACK_SEL   equ 6 * sizeof DESCRIPTOR
endif
if ?KD
GDT_SEL         equ 48h
endif

;--- equates from JLM.INC
;--- OUT_INSTR, WORD_IO and DWORD_IO are used as offset in tables
;--- and hence cannot be changed; see DMA.ASM!

OUT_INSTR   equ 04h
WORD_IO     equ 08h
DWORD_IO    equ 10h
STRING_IO   EQU 20h
REP_IO      EQU 40h

DMAREQ struct
bMode       db ?    ;saved "mode" value (register 0Bh or D6h)
bFlags      db ?    ;flags (DMAF_ENABLED) 
BlockLen    dw ?    ;saved "block length" value
BaseAdr     dw ?    ;saved "block address" value
PageReg     db ?    ;saved "page register" value
cDisable    db ?    ;is automatic translation disabled? (VDS)
DMAREQ ends

BPTABLE struct
pInt06  dd ?
pInt19  dd ?
pInt67  dd ?
if ?VDS
pInt4B  dd ?
endif
pBack   dd ?
pI1587  dd ?
if ?DMAPT
p1340   dd ?
endif
pXMS    dd ?
pStrat  dd ?
pDev    dd ?
if ?UNLOAD
pUnload dd ?
endif
BPTABLE ends


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
pEIP    dd ?    ;+0
pCS     dd ?    ;+4 
pEFL    dd ?    ;+8
IRETD32 ends

;--- client register structure in V86 monitor.
;--- consists of:
;--- 1. PUSHAD
;--- 2. Int#
;--- 3. v86-exception frame with error code

Client_Reg_Struc  struct
Client_EDI  dd ?    ;+0
Client_ESI  dd ?    ;+4
Client_EBP  dd ?    ;+8
Client_res0 dd ?    ;+12
Client_EBX  dd ?    ;+16
Client_EDX  dd ?    ;+20
Client_ECX  dd ?    ;+24
Client_EAX  dd ?    ;+28
Client_Int  dd ?    ;+32
Client_Error dd ?   ;+36
Client_EIP  dd ?    ;+40
Client_CS   dd ?    ;+44    
Client_EFlags dd ?  ;+48
Client_ESP  dd ?    ;+52
Client_SS   dd ?    ;+56
Client_ES   dd ?    ;+60
Client_DS   dd ?    ;+64
Client_FS   dd ?    ;+68
Client_GS   dd ?    ;+72
Client_Reg_Struc ends

;--- entry in IO trap table
;--- this is for the default port trap handler;
;--- it handles byte ports only.

IOTRAPENTRY struct
bStart  db ?
bEnd    db ?
dwProc  dd ?
IOTRAPENTRY ends

;--- Jemm Service Table
;--- this structure is filled and returned by 
;--- IoCtl call 8. Used by JLoad.

if ?SERVTABLE
VMM_SERV_TABLE struct
pSimulate_Int           dd ?
pSimulate_Iret          dd ?
pSimulate_Far_Call      dd ?
pSimulate_Far_Ret       dd ?
pBegin_Nest_Exec        dd ?
pExec_Int               dd ?
pResume_Exec            dd ?
pEnd_Nest_Exec          dd ?
pSimulate_IO            dd ?
pYield                  dd ?
pVDS_Call_Table         dd ?
pVCPI_Call_Table        dd ?
pIO_Trap_Table          dd ?
pV86_Monitor            dd ?	; linear address of V86_Monitor() (obsolete with ppV86Hooks)
pStackCurr              dd ?	; linear address of dwStackCurr (obsolete with ppV86Hooks)
pMoveMemory             dd ?	; linear address of MoveMemory()
ppV86Hooks              dd ?	; linear address of pV86Hooks variable (since v5.85)
VMM_SERV_TABLE ends
endif

;--- macros

@mov_eax_cr4 macro
    db 0fh, 20h, 0E0h
endm
@mov_ecx_cr4 macro
    db 0fh, 20h, 0E1h
endm

@mov_cr4_eax macro
    db 0fh, 22h, 0E0h
endm
@mov_cr4_ecx macro
    db 0fh, 22h, 0E1h
endm

@cpuid  macro
;   cpuid
    db 0Fh,0A2h
endm

@wrmsr  macro
    db 0Fh,030h
endm

@rdtsc  macro
    db 0Fh,031h
endm

@rdmsr  macro
    db 0Fh,032h
endm

;--- macro to get a pointer to PTEs
;--- reg: register to set
;--- ofs: offset in page dir/page table
;--- bIsConst: if blank, then ofs is/contains a register

@GETPTEPTR macro reg, ofs, bIsConst
if 0
    mov reg,[PAGEDIR]
  ifnb <ofs>
    lea reg, [reg+ofs]
  endif  
else
  ifnb <ofs>
    ifnb <bIsConst>
      mov reg,?PAGEDIR+ofs
    else
      lea reg,[?PAGEDIR+ofs]
    endif
  else
    mov reg, ?PAGEDIR
  endif
endif
endm

@GETPTE macro reg, ofs, bIsConst
if 0
    mov reg,[PAGEDIR]
    mov reg,[reg+ofs]
else
    ifnb <bIsConst>
      mov reg,ds:[?PAGEDIR+ofs]
    else
      mov reg,[?PAGEDIR+ofs]
    endif
endif
endm

;--- macro to convert a a pointer to PTEs in system page table
;--- to the according linear address

@SYSPTE2LINEAR macro reg, pPT
    mov     reg, pPT
    sub     reg, ?SYSLINEAR+?PAGETABSYS
    shl     reg, 10
    add     reg, ?SYSBASE
endm
