
;--- common definitions for both Jemm32 and Jemm16

LF              EQU 0AH
CR              EQU 0DH

?VERSIONHIGH    equ 5
?VERSIONLOW     equ 79

ifndef ?INTEGRATED
?INTEGRATED     EQU 0       ; 1=integrated version (XMS + EMM)
endif
?DMA            EQU 1       ; 1=enable DMA port trapping support
?VDS            EQU 1       ; 1=enable VDS support
?VCPI           EQU 1       ; 1=enable VCPI support
?EMX            EQU 1       ; 1=EMX compat switch supported
?SB             EQU 1       ; 1=SB compat switch supported (useful?)
?EMMXXXX0       EQU 1       ; 1=implement EMMXXXX0 IOCTL
?A20XMS         EQU 1       ; 1=emu A20 by trapping XMS functions
?A20PORTS       EQU 1       ; 1=emu A20 by trapping ports (92, 64, 60)
?VME            EQU 1       ; 1=support P1+ VME extension
?LOAD           EQU 1       ; 1=support LOAD command line option
?PGE            EQU 1       ; 1=support PGE on P3+ (requires ?INVLPG!) 
?MOVEHIGH       EQU 1       ; 1=support moving in first UMB
?UNLOAD         EQU 1       ; 1=support UNLOAD option
?FASTBOOT       EQU 1       ; 1=support FASTBOOT option
?SPLIT          EQU 1       ; 1=support SPLIT option
?HOOK13         EQU 1       ; 1=hook int 13h/40h for DMA access trapping
?V86EXC0D       EQU 1       ; 1=support V86EXC0D option
?ADDCONV        EQU 1       ; 1=add A000f to conv memory if I=A000-XXXX

?STKSIZE        EQU 200H    ; Size monitor stack for non-reentrant execution
?HLPSTKSIZE     EQU 80h     ; size of help stack for VCPI

?GDTOFS         equ ?HLPSTKSIZE

?BPOPC          equ 0F4h            ; opcode used for breakpoints (HLT)
;?BPOPC         equ 063h            ; this should also work (ARPL)

;--- XMS

XMS_HANDLE struct
xh_flags    DB  ?
xh_locks    DB  ?
xh_baseK    DD  ?
xh_sizeK    DD  ?
XMS_HANDLE ends

LPXMS_HANDLE typedef ptr XMS_HANDLE

;--- XMS handle flags

XMSF_FREE   equ 1   ;handle describes a free EMB
XMSF_USED   equ 2   ;handle describes a used EMB
XMSF_INPOOL equ 4   ;handle is free


XMS_HANDLETABLE struct
xht_sig         DB  ?
xht_sizeof      DB  ?
xht_numhandles  DW  ?
xht_pArray      DD  ?   ;converted to linear address for 32bit code!
XMS_HANDLETABLE ends

if ?INTEGRATED

XMS_MOVE struct
  len           dd  ?       ;  +0 block length in bytes
  src_handle    dw  ?       ;  +4 source handle
  src_offset    dd  ?       ;  +6 offset into source
  dest_handle   dw  ?       ; +10 destination handle
  dest_offset   dd  ?       ; +12 offset into destination
XMS_MOVE ends

;--- A20 switch methods (must match order in "methods" table)

A20_KBC     equ 0
A20_PS2     equ 1
A20_BIOS    equ 2
A20_ALWAYSON equ 3
A20_FAST    equ 4
A20_PORT92  equ 5

DRIVER_VER      equ 300h+29
INTERFACE_VER   equ 300h

;--- XMS error codes

XMS_NOT_IMPLEMENTED             equ 80h
XMS_VDISK_DETECTED              equ 81h
XMS_A20_FAILURE                 equ 82h
XMS_DRIVER_FAILURE              equ 8eh
XMS_DRIVER_FATAL                equ 8fh
XMS_HMA_NOT_THERE               equ 90h
XMS_HMA_IN_USE                  equ 91h
XMS_HMAREQ_TOO_SMALL            equ 92h
XMS_HMA_NOT_USED                equ 93h
XMS_A20_STILL_ENABLED           equ 94h
XMS_ALL_MEM_ALLOCATED           equ 0a0h
XMS_NO_HANDLE_LEFT              equ 0a1h
XMS_INVALID_HANDLE              equ 0a2h
XMS_INVALID_SOURCE_HANDLE       equ 0a3h
XMS_INVALID_SOURCE_OFFSET       equ 0a4h
XMS_INVALID_DESTINATION_HANDLE  equ 0a5h
XMS_INVALID_DESTINATION_OFFSET  equ 0a6h
XMS_INVALID_LENGTH              equ 0a7h
XMS_INVALID_OVERLAP             equ 0a8h
XMS_PARITY_ERROR                equ 0a9h
XMS_BLOCK_NOT_LOCKED            equ 0aah
XMS_BLOCK_LOCKED                equ 0abh
XMS_LOCK_COUNT_OVERFLOW         equ 0ach
XMS_LOCK_FAILED                 equ 0adh
XMS_ONLY_SMALLER_UMB            equ 0b0h
XMS_NO_UMB_AVAILABLE            equ 0b1h
XMS_UMB_SEGMENT_NR_INVALID      equ 0b2h

endif

if ?EMMXXXX0

;--- structure returned by Jemm386 if an "INFO" request was made
;--- for device "EMMXXXX0"

EMX06 struct
e06_NoEMS       db ? ;+0
e06_Frame       dw ? ;+1 segment
e06_NoVCPI      db ? ;+3
e06_DMABuff     dd ? ;+4 physical address DMA buffer
e06_NoPGE       db ? ;+8
                db ?
                db ?
                db ?
e06_DMASize     dw ? ;+12 in KB
e06_NoVME       db ? ;+14
e06_NoA20       db ? ;+15
e06_VCPITotal   dd ? ;+16 VCPI pages total (def 120 MB)
e06_VCPIUsed    dd ? ;+20 VCPI pages allocated
EMX06 ends

;--- this is the structure for a "Get VMM info" request

EMX08 struct
e08_ServiceTable    dd ?
e08_BPTable         dd ?
e08_BPTableRM       dd ?
e08_GDTR            df ?
e08_IDTR            df ?
e08_TR              dw ?
e08_FlatCS          dw ?
EMX08 ends

;--- this is the structure for an "UPDATE" request with IoctlWrite

EMX15W struct
e15_bVME    db ?
e15_bA20    db ?
e15_bVCPI   db ?
e15_bPGE    db ?
EMX15W ends

endif

DMABUFFDEFAULT equ 64 ;/* DMA buffer default size in kB */
MINMEM16K_DEFAULT equ 0 ;/* MIN= default (in 16 kB units) */

;--- data for monitor initialization

JEMMINIT struct 4
MonitorStart      dd 0    ;memory block start address (XMS/I15)
MonitorEnd        dd 0    ;memory block end address (XMS/I15)
MaxPhysMem        dd 0    ;highest physical memory address (XMS/I15)
MaxMem16k         dd -1   ;MAX mem in 16 kB units (default 7680)
MinMem16k         dd MINMEM16K_DEFAULT    ;MIN mem in 16 kB units (default 0)
XMSHandleTable    dd 0    ;XMS handle table (FAR16)
PageMap           dd 0    ;conventional memory page map (FLAT!)
MaxEMSPages       dw 0    ;EMS max 16 kB pages (default 2048)
XMSControlHandle  dw 0    ;XMS memory block handle (or 0000 if I15)
DMABufferSize     dw DMABUFFDEFAULT    ;DMA buffer size in kB
Frame             dw 0E000h    ;EMS page frame
Border            dw 04000h    ;EMS border for mappable pages
ResUMB            dw 0    ;UMB para where the resident part was moved to
if ?INTEGRATED
HmaMin            dw 0    ;min request in KB for HMA
X2Max             dw -1
endif
NoEMS             db 0
NoFrame           db 0
NoPool            db 0
AltBoot           db 0
NoVME             db 1
NoVDS             db 0
NoPGE             db 1
NoA20             db 0
NoVCPI            db 0
NoInvlPg          db -1
V86Flags          db 0
NoRAM             db 0
NoHigh            db 0
NumUMBs           db 0    ;number of UMBs installed
if ?INTEGRATED
A20Method         db -1
endif
JEMMINIT ends

;--- V86Flags equates

V86F_SB         equ 1   ; soundblaster driver compat
V86F_NOCHECK    equ 2   ; flag NOCHECK option
if ?EMX
V86F_EMX        equ 4   ; EMX compat
endif
if ?FASTBOOT
V86F_FASTBOOT   equ 8   ; fastboot active
V86B_FASTBOOT   equ 3   ; bit 3
endif
if ?V86EXC0D
V86F_V86EXC0D   equ 16  ; V86EXC0D active
endif

;-- 120 MB max VCPI memory (in 16 kB units)
;-- keep this value low for buggy VCPI clients
;-- that fail with large free amounts
;-- this constant is also defined in Jemm386c.c

MAXMEM16K_DEFAULT   EQU 1E00h   ; 120M in 16K blocks

MAX_EMS_PAGES_POSSIBLE  equ 8000h

;--- this is the table of RSEG offsets 
;--- the values are offsets in the RSEG segment
;--- there is just one instance defined in jemm16.asm.

RSOFS struct
wSizeRes    dw ?    ;size resident part
wBpTab      dw ?    ;offset of BP table
if ?DMA
wRFlags     dw ?    ;offset of DMA flags
endif
RSOFS ends

;--- max number of UMB blocks
;--- this constant is also defined in Jemm386c.c

UMB_MAX_BLOCKS  equ 8

UMBBLK struct
wSegm   dw ?    ;segment address
wSize   dw ?    ;size in paras, high bit used as flag free/allocated
UMBBLK ends

UMB_ALLOCATED equ 80h	;flag in wSize+1

;--- stack frame expected by ring0-IRETD to switch to v86-mode

IRETDV86 struct
vEIP    dd ?    ;+0
vCS     dd ?    ;+4 
vEFL    dd ?    ;+8
vESP    dd ?    ;+12
vSS     dd ?    ;+16
vES     dd ?    ;+20
vDS     dd ?    ;+24
vFS     dd ?    ;+28
vGS     dd ?    ;+32
IRETDV86 ends

;--- macros

@BPOPC macro
    db ?BPOPC
endm

