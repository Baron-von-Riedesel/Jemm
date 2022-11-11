;
; XCDROM32.ASM  - a JLM driver for  UltraDMA CD-ROMs/DVDs
; based on XCDROM v1.9 by Jack R. Ellis
; released under the GNU GPL license v2 (see GNU_GPL.TXT for details)
;
; The source is to be assembled with JWasm or Masm v6+!
;
; XCDROM32 switch options are as follows:
;
;  /32   use 32bit INSD instead of INSW in PIO mode.
;
;  /AX   Excludes ALL audio functions. This makes the driver report
;        on a Device-Status request that it reads DATA tracks only!
;        UltraDMA, dual-drives, and other driver features are NOT
;        affected!
;
;  /D:   Specifies the desired "device name" which SHCDX33 or MSCDEX
;        will use during their initialization to address the CD-ROM
;        drives.   Examples are:  /D:CDROM1  /D:MYCDROM  etc.   The
;        device name must be from 1 to 8 bytes valid for use in DOS
;        filenames.   If /D: is omitted, or the "device name" after
;        a /D: is missing or invalid, "XCDROM$$" will be the default.
;
;  /L    Limits UltraDMA to "low memory" below 640K. /L is REQUIRED
;        if upper memory blocks supplied by UMBPCI or a similar driver
;        cannot do UltraDMA. /L causes I-O requests above 640K to use
;        the VDS DMA buffer or, if none is available, to use "PIO mode"
;        input.   Note that /L will be IGNORED if /UX is also given.
;
;  /Mn   Specifies the MAXIMUM UltraDMA "mode" to be set for a CD-ROM
;        drive, where  n  is a number between 0 and 7, as follows:
;            0 = ATA-16, 16 MB/sec.
;            1 = ATA-25, 25 MB/sec.
;            2 = ATA-33. 33 MB/sec.
;            ...
;            7 = ATA-166. 166 MB/sec.
;        A CD-ROM drive designed to use "modes" LESS than the given
;        value will be limited to its own highest "mode".   /M will
;        be IGNORED for CD-ROM drives which cannot do UltraDMA, and
;        it will be ignored for ALL drives if /UX is also given.

;
;  /Q    Quiet mode.
;
;  /F    "Fast" mode. Data input requests that cross an
;        UltraDMA "64K boundary" are executed using a 2-element DMA
;        command list, one for data up to the boundary, and one for
;        data beyond it.   This might increase CD-ROM speed.
;        "Buffered" or "PIO mode" input is still needed for user 
;        buffers that are misaligned (not at an even 4-byte address).
;        /F will be IGNORED for CD-ROM drives which cannot do DMA.
;
;        --- NOTE ---
;        Despite any UltraDMA specs, NOT ALL chipsets or mainboards
;        can run multi-element DMA commands properly!   Although it
;        is valuable, /F must be TESTED on every system, and it
;        should be enabled with CARE!!
;
;  /UX   Disables ALL UltraDMA, even for CD-ROM drives capable of it.
;        The driver then uses "PIO mode" for all data input.    /UX
;        should be needed only for tests and diagnostic work.
;
;  /W    accept (non-UDMA) devices which can do multiword-DMA.
;
; For each switch, a dash may replace the slash, and lower-case letters
; may be used.

        .386
        .model flat
        option casemap:none
        option proc:private

        include jlm.inc

?EXTDISP equ 0 ; extended displays for error trapping
;
; General Program Equations.
;

NUMCTRL     equ 3       ;max # of EIDE controllers
NUMDSK      equ 3       ;max # of CD/DVD devices
SETMODE     equ 1       ;support /M option, set UDMA mode
SETBM       equ 1       ;test Busmaster support in "class"
MWDMA       equ 1       ;support /W option to accept multi-word DMA
DWRDIO      equ 1       ;support /32 option (PIO DWORD IO)
SAVESTAT    equ 1       ;call save/restore "client reg struct" on init
IDENTPKT    equ 1       ;1=issue "identify packet" cmd, 0=normal "identify"

VER     equ <'V1.5, 06.10.2022'>    ;Driver version number and date.
MSELECT equ 0A0h        ;"Master" device-select bits.
SSELECT equ 0B0h        ;"Slave"  device-select bits.
COOKSL  equ 2048        ;CD-ROM "cooked" sector length.
RAWSL   equ 2352        ;CD-ROM "raw" sector length.
CMDTO   equ 00Ah        ;500-msec minimum command timeout.
SEEKTO  equ 025h        ;2-second minimum "seek"  timeout.
;STARTTO equ 049h        ;4-second minimum startup timeout.
STARTTO equ 07Fh        ;7-second minimum startup timeout.
BIOSTMR equ 0046Ch      ;BIOS "tick" timer address.
;VDSFLAG equ 0047Bh      ;BIOS "Virtual DMA" flag address.
;IXM     equ 2048        ;IOCTL transfer-length multiplier.
CR      equ 00Dh        ;ASCII carriage-return.
LF      equ 00Ah        ;ASCII line-feed.
TAB     equ 009h        ;ASCII "tab".

REQOFS   equ 16h        ; must be at least "sizeof DOSDRV"


@byte   equ <byte ptr>
@word   equ <word ptr>
@dword  equ <dword ptr>
;
; IDE Controller Register Definitions.
;
CDATA   equ 0           ;Data port.
CSECCT  equ 2           ;offset port for I-O sector count.
CDSEL   equ 6           ;offset port Drive-select and upper LBA.
CCMD    equ 7           ;offset port Command register (write)
CSTAT   equ 7           ;Primary status register (read)
;
; Controller Status and Command Definitions.
;
BSY     equ 080h        ;IDE controller is busy.
DRQ     equ 008h        ;IDE data request.
ERR     equ 001h        ;IDE general error flag.

DMI     equ 004h        ;DMA interrupt occured.
DME     equ 002h        ;DMA error occurred.
SETM    equ 003h        ;Set Mode subcommand.
SETF    equ 0EFh        ;Set Features command.
LBABITS equ 0E0h        ;Fixed LBA command bits.

;--- structures

DOSDRV struct
		dd ?
wAttr	dw ?
ofsStr	dw ?
ofsInt	dw ?
name_	db 8 dup (?);+10
wRes1	dw ?		;+18 req. for cd drivers, init with 0
bRes2	db ?		;+20 req. for cd drivers, modified by mscdex
bUnits	db ?		;+21 set by driver
DOSDRV ends

;
; DOS "Request Packet" header layout.
;
RPH     struc
bHLen   db  ?       ;+0 Header byte count.
bSubU   db  ?       ;+1 Subunit number.
bOp     db  ?       ;+2 Command code.
wStat   dw  ?       ;+3 Status field.
        db 8 dup (?);(Unused by us).
RPH     ends

;--- wStat values
RPERR   equ 08003h      ;Packet "error" flags.
RPDON   equ 00100h      ;Packet "done" flag.
RPBUSY  equ 00200h      ;Packet "busy" flag.

;--- Init "Request Packet" Layout.

RPINIT  struc
        RPH <> 
bUnit   db  ?       ;+13 Number of units found.
RPSize  dw  ?       ;+14 Resident driver offset
        dw  ?
dwCL    dd  ?       ;Command-line data pointer.
RPINIT  ends

;
; IOCTL "Request Packet" Layout.
;
IOC struc
        RPH <>
        db  ?       ;+13 Media descriptor byte (Unused by us).
IOCAdr  dd  ?       ;+14 Data-transfer address.
IOCLen  dw  ?       ;+18 Data-transfer length.
        dw  ?       ;+20 Starting sector (unused by us).
        dd  ?       ;+22 Volume I.D. pointer (unused by us).
IOC ends
;
; Read Long "Request Packet" Layout.
;
RL struc
        RPH <>
RLAM    db  ?       ;+13 Addressing mode.
RLAddr  dd  ?       ;+14 Data-transfer address.
RLSC    dw  ?       ;+18 Data-transfer sector count.
RLSec   dd  ?       ;+20 Starting sector number.
RLDM    db  ?       ;+24 Data-transfer mode.
RLIntlv db  ?       ;+25 Interleave size.
RLISkip db  ?       ;+26 Interleave skip factor.
RL  ends

;
; Play "Request Packet" Layout
;
RPPlay struc
        RPH <>
bMode   db  ?       ;+13 Addressing mode.
dwStart dd  ?       ;+14 Data-transfer address.
dwSize  dd  ?       ;+18 Data-transfer sector count.
RPPlay ends

IDEPARM struc
wIDEBase    dw ?
wDMABase    dw ?
bDevSel     db ?
            db ?
IDEPARM ends

AUDADR struct
dwAudSta dd ?      ;Current audio-start address - LBA?
dwAudEnd dd ?      ;Current audio-end   address - LBA?
dwLSSta  dd ?      ;Last-session starting LBA.
AUDADR ends

;--- Unit Parameter (first 3 fields must match IDEPARM)

UPARM  struc
wIDEBase    dw ?    ;IDE address   (set by Init).
wDMABase    dw ?    ;DMA address   (set by Init).
bDevSel     db ?    ;Device-select (set by Init).
            dw ?    ;not used
            db ?    ;Media-change flag (one byte below dwAudSta).
            AUDADR <>
UPARM ends

;--- macros

CStr macro text:vararg
local sym
	.code text$01
sym db text,0
	.code
	exitm <offset sym>
endm

@dprintf macro text,args:vararg
local sym
ifdef _DEBUG
	ifnb <args>
		invoke printf, CStr(text), args
	else
		invoke printf, CStr(text)
	endif
endif
endm

    .data

pRequest    dd 0    ;linear address where request header is stored
dwRequest   dd 0    ;linear address request header
dwBase      dd 0    ;linear address driver base
dwCmdLine   dd 0
;
; Main I-O Variables
;
BufAdr  dd  0       ;buffer linear address
BufLng  dd  0       ;buffer length
XFRAdr  dd  0       ;I-O data transfer address.
XFRLng  dd  0       ;I-O data transfer length.
;
; DMA Variables.
;
DmaAdr  dd  0           ;1st physical address for DMA
DmaLng  dd  0           ;1st DMA byte count
DmaAdr2 dd  0           ;2nd physical address
DmaLng2 dw  0           ;2nd DMA byte count LoWord
        dw  8000h       ;2nd DMA byte count HiWord (fix)
PRDAd   dd  0           ;PRD 32-bit command addr. (Init set).
        align 4

;
; ATAPI "Packet" Area (always 12 bytes for a CD-ROM).
; packet commands used by this program:
; - 01Bh:  start/stop unit
; - 01Eh:  prevent/allow media removal
; - 025h:  read capacity
; - 028h:  read (cooked)
; - 02Bh:  seek
; - 042h:  read sub-channel
; - 043h:  read TOC
; - 047h:  play audio MSF
; - 04Bh:  pause/resume
; - 05Ah:  mode sense
; - 0BEh:  read CD (raw)
;
Packet label byte
PktOPC  db  0       ;Opcode.
        db  0       ;Unused (LUN and reserved).
PktLBA  dd  0       ;CD-ROM logical block address.
PktLH   db  0       ;"Transfer length" (sector count).
PktLn   dw  0       ;Middle- and low-order sector count.
PktRM   db  0       ;Read mode ("Raw" Read Long only).
        dw  0       ;Unused ATAPI "pad" bytes (required).
        align 4
;
; Miscellaneous Driver Variables.
;
AudAP   dd  0       ;Current audio-start address pointer.
                    ;points to curr AUDADR struct
bFlags  db  0
bDMA    db  0       ;DMA input flag (0/1).
bTry    db  0       ;I-O retry counter.
        align 4

;bFlags values
FL_Q    equ 1       ;/Q option set
FL_F    equ 2       ;/F option set
if MWDMA
FL_W    equ 4       ;/W option
endif
FL_UX   equ 8       ;/UX option set

;
; Audio Function Buffer (16 bytes) for most CD-ROM "audio" requests.
;   The variables below are used only during driver initialization.
;
InBuf   equ $
pUTbl   dd  offset UnitTbl      ;Initialization unit table pointer.
ScanX   dd  offset ScanLPM      ;Scan table ptr (disks)
pScan   dd  offset ScanLPM      ;Scan table ptr (controllers)
MaxUM   db  -1                  ;UDMA "mode" limit set by /Mn option.
UFlag   db  0                   ;UltraDMA "mode" flags (set by Init).
UMode   db  0                   ;UltraDMA "mode" value (set by Init).
bLegacy db  0                   ;allow just one "legacy" controller

;
; Unit Parameter Tables.   If you want a 4th drive, simply add 1 more
;   parameter table -- NO extra code and NO other changes are needed!
;
UnitTbl UPARM NUMDSK dup (<-1,-1,-1,0,-1,<-1,-1,-1>>)
        align 4
;
; Dispatch Table for DOS CD-ROM request codes 0 through 14.
;
DspTbl1 dd  DspLmt1     ;Number of valid request codes.
        dd  Try2ndD     ;Invalid-request handler address.
DspTblA dd  UnSupp      ;00 -- Initialization  (special).
        dd  UnSupp      ;01 -- Media Check  (unused).
        dd  UnSupp      ;02 -- Build BPB    (unused).
        dd  IOCTLInput  ;03 -- IOCTL Input.
        dd  UnSupp      ;04 -- Input        (unused).
        dd  UnSupp      ;05 -- Input no-wait    (unused).
        dd  UnSupp      ;06 -- Input Status (unused).
        dd  UnSupp      ;07 -- Input flush  (unused).
        dd  UnSupp      ;08 -- Output       (unused).
        dd  UnSupp      ;09 -- Output & verify  (unused).
        dd  UnSupp      ;10 -- Output status    (unused).
        dd  UnSupp      ;11 -- Output flush (unused).
        dd  IOCTLOutput ;12 -- IOCTL Output.
        dd  Ignored     ;13 -- Device Open     (ignored).
        dd  Ignored     ;14 -- Device Close    (ignored).
DspLmt1 equ ($ - offset DspTblA)/4  ;Request-code limit for this table.

        dd DspLmt1 dup (0)
;
; Dispatch Table for DOS CD-ROM request codes 128 through 136.
;
DspTbl2 dd  DspLmt2     ;Number of valid request codes.
        dd  UnSupp      ;Invalid-request handler address.
DspTblB dd  ReqRL       ;128 -- Read Long.
        dd  UnSupp      ;129 -- Reserved    (unused).
@RqPref dd  ReqSeek     ;130 -- Read Long Prefetch.
@RqSeek dd  ReqSeek     ;131 -- Seek.
@RqPlay dd  ReqPlay     ;132 -- Play Audio.
@RqStop dd  ReqStop     ;133 -- Stop Audio.
        dd  UnSupp      ;134 -- Write Long  (unused).
        dd  UnSupp      ;135 -- Wr. Long Verify (unused).
@RqRsum dd  ReqRsum     ;136 -- Resume Audio.
DspLmt2 equ ( $ - offset DspTblB)/4 ;Request-code limit for this table.

        dd DspLmt2 dup (0)

;
; Dispatch table for IOCTL Input requests.
;
DspTbl3 dd  DspLmt3     ;Number of valid request codes.
        dd  UnSupp      ;Invalid-request handler address.
DspTblC dd  ReqDHA      ;00 -- Device-header address.
@RqCHL  dd  ReqCHL      ;01 -- Current head location.
        dd  UnSupp      ;02 -- Reserved     (unused).
        dd  UnSupp      ;03 -- Error Statistics (unused).
        dd  UnSupp      ;04 -- Audio chan. info (unused).
        dd  UnSupp      ;05 -- Read drive bytes (unused).
        dd  ReqDevStat  ;06 -- Device status.
        dd  ReqSecSize  ;07 -- Sector size.
@RqVS   dd  ReqVolSize  ;08 -- Volume size.
        dd  ReqMCS      ;09 -- Media-change status.
@RqADI  dd  ReqADI      ;10 -- Audio disk info.
@RqATI  dd  ReqATI      ;11 -- Audio track info.
@RqAQI  dd  ReqAQI      ;12 -- Audio Q-channel info.
        dd  UnSupp      ;13 -- Subchannel info  (unused).
        dd  UnSupp      ;14 -- Read UPC code    (unused).
@RqASI  dd  ReqASI      ;15 -- Audio status info.
DspLmt3 equ ( $ - offset DspTblC)/4 ;Request-code limit for this table.

;--- expected size of IOCTL input requests
        dd  5       ;0
        dd  6       ;1
        dd  0,0,0,0 ;2-5
        dd  5       ;6
        dd  4       ;7
        dd  5       ;8
        dd  2       ;9
        dd  7       ;10
        dd  7       ;11
        dd  11      ;12
        dd  0,0     ;13-14
        dd  11      ;15

;
; Dispatch table for IOCTL Output requests.
;
DspTbl4 dd  DspLmt4     ;Number of valid request codes.
        dd  UnSupp      ;Invalid-request handler address.
DspTblD dd  ReqEjct     ;00 -- Eject Disk.
        dd  ReqDoor     ;01 -- Lock/Unlock Door.
        dd  ReqRS       ;02 -- Reset drive.
        dd  UnSupp      ;03 -- Audio control    (unused).
        dd  UnSupp      ;04 -- Write ctl. bytes (unused).
        dd  ReqTray     ;05 -- Close tray.
DspLmt4 equ ( $ - offset DspTblD)/4 ;Request-code limit for this table.

;--- expected size of IOCTL output requests
        dd  1
        dd  2
        dd  1
        dd  0,0
        dd  1

; IDE controllers, programming interface bits:
; 7 bus mastering (read-only)
; 6-4   reserved (read-only)
; 3 secondary IDE mode bit is writable (read-only)
; 2 secondary IDE mode (0 = legacy, 1 = native)
; 1 primary IDE mode bit is writable (read-only)
; 0 primary IDE mode (0 = legacy, 1 = native)
;
; Initialization IDE Parameter-Value Table.
; each IDE controller needs 4 entries (primary/secondary, master/slave),

ScanLPM IDEPARM NUMCTRL dup (<-1,-1,0A0h>,<-1,-1,0B0h>,<-1,-1,0A0h>,<-1,-1,0B0h>)

if MWDMA
MWModes label word
    dw  0004       ;Mode 0
    dw  0013       ;Mode 1
    dw  0016       ;Mode 2
endif
UModes label word
    dw  0016       ;Mode 0, ATA-16  UDMA mode table
    dw  0025       ;Mode 1, ATA-25
    dw  0033       ;Mode 2, ATA-33
    dw  0044       ;Mode 3, ATA-44  (Unusual but possible).
    dw  0066       ;Mode 4, ATA-66
    dw  0100       ;Mode 5, ATA-100
    dw  0133       ;Mode 6, ATA-133
    dw  0166       ;Mode 7, ATA-166

UnitNo  dd  0
wDmaMode dw 0
        db -1
DrvName db 40 dup (0)
        db 0
szDriver db 9 dup (0)


rmcode label byte
    db 2Eh, 89h, 1eh, REQOFS+0, 0    ;mov cs:[16h],bx
    db 2Eh, 8Ch, 06h, REQOFS+2, 0    ;mov cs:[18h],es
    db 0CBh                     ;retf
SIZERMCODE equ $ - offset rmcode    
    db 0EAh                     ;jmp ssss:oooo

    .code

	include printf.inc

;
; "Device-Interrupt" routine -- This routine processes DOS requests.
;
DevInt:

    call ZPacket            ;Clear our ATAPI packet area.
    mov esi, [pRequest]
    movzx eax,@word [esi+0]
    movzx esi,@word [esi+2]
    shl esi, 4
    add esi, eax            ;Point to DOS request packet.
    mov [dwRequest], esi    ;linear address request header

    mov [esi].RPH.wStat,RPDON ;Init status to "done".
    mov al,[esi].RPH.bSubU    ;Get unit-table offset.
    mov ah,sizeof UPARM
    mul ah
    lea ebx,[eax+offset UnitTbl]    ;Set unit's audio-start address ptr.
    lea eax, [ebx+UPARM.dwAudSta]
    mov [AudAP],eax

    push [ebp].Client_Reg_Struc.Client_EFlags           ;save client flags
    or @byte [ebp].Client_Reg_Struc.Client_EFlags+1,2   ;set client's IF

    mov al,[esi].RPH.bOp    ;Get packet request code.
    mov edi,offset DspTbl1  ;Point to 1st DOS dispatch table.
    call Dspatch            ;Dispatch to desired request handler.

    pop [ebp].Client_Reg_Struc.Client_EFlags    ;restore client flags

    @VMMCall Simulate_Far_Ret
    ret
;
; Function-Code "Dispatch" Routines.
;
Try2ndD:
    sub al,080h             ;Not request code 0-15:  subtract 128.
    mov edi,offset DspTbl2  ;Point to 2nd DOS dispatch table.
    jmp Dspatch             ;Go try request-dispatch again.
IOCTLInput:
    mov edi,offset DspTbl3  ;Point to IOCTL Input dispatch table.
    jmp TryIOC
IOCTLOutput:
    mov edi,offset DspTbl4  ;Point to IOCTL Output dispatch table.
TryIOC:
    movzx ecx,@word [esi].IOC.IOCAdr+2
    movzx esi,@word [esi].IOC.IOCAdr+0
    shl ecx,4
    add esi, ecx
    mov al,[esi]            ;Get actual IOCTL request code.
    mov esi,[dwRequest]     ;Reload DOS request-packet address.

;--- Dspatch()
;--- EDI=DTAB
;--- DTAB+0: dd #entries
;--- DTAB+4: dd offset error handler
;--- DTAB+8: start dispatch table ( size #entries )

Dspatch:
    xor edx,edx
    mov ecx, [edi]          ;get number of table entries
    add edi,4               ;(Skip past table-limit value).
    cmp al,cl               ;Is request code out-of-bounds?
    jae @F                  ;Yes?  Dispatch to error handler!
    add edi,4               ;Skip past error-handler address.
    movzx eax,al            ;Point to request-handler address.
    lea edi,[edi+eax*4]
    mov edx,[edi+ecx*4]
@@:
    mov edi,[edi]           ;Get handler address from table.
    and edx, edx
    jz  @F

;--- v1.5: IXM removed
;    shr edx,11              ;Ensure correct IOCTL transfer

    mov [esi].IOC.IOCLen,dx ;length is set in DOS packet.
    movzx ecx,@word [esi].IOC.IOCAdr+2
    movzx esi,@word [esi].IOC.IOCAdr+0
    shl ecx,4               ;Get IOCTL data-transfer address.
    add esi, ecx
@@:
    jmp edi                 ;Dispatch to desired request handler.

GenFail:
    mov al,12               ;General failure!  Get error code.
    jmp ReqErr              ;Go post packet error code & exit.
UnSupp:
    mov al,3                ;Unsupported request!  Get error code.
    jmp ReqErr              ;Go post packet error code & exit.
SectNF:
    mov al,8                ;Sector not found!  Get error code.
ReqErr:
    mov esi,[dwRequest]     ;Reload DOS request-packet address.
    mov ah,081h             ;Post error flags & code in packet.
    mov [esi].RPH.wStat,ax
Ignored:
    ret                     ;Exit ("ignored" request handler).
;
; IOCTL Input "Device Header Address" handler
;
ReqDHA:
    mov eax,[dwBase]
    shl eax,12              ;convert linear address to SSSS:0000
    mov [esi+1], eax
    ret
;
; IOCTL Input "Return Sector Size" handler
;
ReqSecSize:
    cmp @byte [esi+1],1     ;Is read mode "cooked" or "raw"
    ja  GenFail             ;No?  Post "general failure" & exit.
    mov ax,RAWSL            ;Get "raw" sector length.
    je  @F                  ;If "raw" mode, set sector length.
    mov ax,COOKSL           ;Get "cooked" sector length.
@@:
    mov [esi+2],ax          ;Post sector length in IOCTL packet.
RqSSX:
    ret
;
; DOS "Read Long" handler.
;
ReqRL:
    call ValSN                      ;Validate starting sector number.
    call MultiS                     ;Handle Multi-Session disk if needed.
    jc  ReqErr                      ;If error, post return code & exit.
    mov cx,[esi].RL.RLSC            ;Get request sector count.
    jcxz RqSSX                      ;If zero, simply exit.
    xchg cl,ch                      ;Save swapped sector count.
    mov [PktLn],cx
    cmp [esi].RL.RLDM,1             ;"Cooked" or "raw" read mode?
    ja  SectNF                      ;No?  Return "sector not found"!
    mov dl,028h                     ;Get "cooked" input values.
    mov ax,COOKSL
    jb  @F                          ;If "cooked" input, set values.
    mov dl,0BEh                     ;Get "raw" input values.
    mov ax,RAWSL
    mov [PktRM],0F8h                ;Set "raw" input flags.
@@:
    mov [PktOPC],dl                 ;Set "packet" opcode.
    mul [esi].RL.RLSC               ;Get desired input byte count.
    test dx,dx                      ;More than 64K bytes desired?
    jnz SectNF                      ;Yes?  Return sector not found!
    movzx eax,ax
    mov [BufLng],eax                ;Set DMA byte counts.
    mov ecx, eax                    ;set ECX for VDMAD call below
    bts eax,31
    mov [DmaLng],eax                ;Set DMA list "end" flag.

    movzx edx,@word [esi].RL.RLAddr+0
    movzx eax,@word [esi].RL.RLAddr+2
    shl eax, 4
    add eax, edx
    mov [BufAdr],eax

    test @byte [ebx].UPARM.wDMABase,7  ;Is drive using UltraDMA?
    jnz UsePIO                      ;No, do "PIO mode" input.
    test al,3                       ;Is user buffer 32-bit aligned?
    jnz BuffIO                      ;No, use buffered IO

    push esi
    mov esi, eax                    ;ESI=lin addr, ECX=length
    test [bFlags],FL_F              ;if /F not set, check 64 kB boundary
    setz dl
    VxDCall VDMAD_Lock_DMA_Region   ;is region physical contiguous?
    pop esi
    jc  BuffIO                      ;Error -- use buffered input.
    mov [DmaAdr],edx
    mov eax,edx                     ;Get phys address.
    cmp @word [DmaAdr+2],-1         ;Is DMA beyond our limit?
@DMALmt equ $-1                     ;(009h for a 640K limit).
    ja  BuffIO                      ;Yes, use buffered input
    test [bFlags],FL_F              ;/F option set?
    jz UseDMA
    mov ecx,[DmaLng]                ;Get lower ending DMA address.
    dec ecx                         ;(DmaLng - 1 + DmaAdr).
    add ax,cx                       ;Would input cross a 64K boundary?
    jnc UseDMA                      ;No, set DMA flag & do transfer.
    inc eax                         ;Get bytes above 64K boundary.
    cmp ax,64                       ;Is this at least 64 bytes?
    jb  BuffIO                      ;No, use buffered input
    inc ecx                         ;Get bytes below 64K boundary.
    sub cx,ax
    cmp cx,64                       ;Is this at least 64 bytes?
    jb  BuffIO                      ;No, use buffered input
    mov [DmaLng2],ax                ;Set 2nd command-list byte count.
    movzx eax,cx                    ;Set 1st command-list byte count.
    mov [DmaLng],eax
    add eax,[DmaAdr]                ;Set 2nd command-list address.
    mov [DmaAdr2],eax
UseDMA:
    mov [bDMA],1                    ;Set UltraDMA input flag.
UsePIO:
    call DoIO                       ;Execute desired read request.
    jnc @F                          ;If no errors, go exit below.
    call ReqErr                     ;Post desired error code.
@@:
    mov [bDMA],0                    ;Reset UltraDMA input flag.
    ret

;--- use the VDS DMA buffer if user buffer cannot be used.
;--- this should be rarely necessary if /F is set.

BuffIO:
    push esi
    push ebx
    mov esi,[BufAdr]
    mov ecx,[BufLng]
    VxDCall VDMAD_Request_Buffer    ;get VDS DMA buffer
    mov eax,ebx
    pop ebx
    pop esi
    jc UsePIO                       ;no buffer available, use PIO!
    mov [DmaAdr],edx
    push eax
    call UseDMA
    pop ebx                         ;set buffer ID in ebx
    jc @F
    mov esi, [BufAdr]
    mov ecx, [BufLng]
    xor edi, edi                    ;buffer offset always zero
    VxDCall VDMAD_Copy_From_Buffer
@@:
    VxDCall VDMAD_Release_Buffer    ;buffer ID still in ebx
    ret

;
; DOS "Seek" handler.
;
DOSSeek:
    call ValSN                      ;Validate desired seek address.
    call MultiS                     ;Handle Multi-Session disk if needed.
    jc  DOSSkE                      ;If error, post return code & exit.
    mov [PktOPC],02Bh               ;Set "seek" command code.
DOSSk1:
    call DoIOCmd                    ;Issue desired command to drive.
DOSSkE:
    jc ReqErr   ;If error, post return code & exit.
    ret
;
; IOCTL Input "Device Status" handler.
;
;--- status flag bits:
;--- 001 - door opened
;--- 002 - door unlocked
;--- 004 - supports cooked AND raw
;--- 008 - read AND write
;--- 010 - data read AND play audio
;--- 020 - supports interleaving
;--- 040 - (res)
;--- 080 - supports prefetching
;--- 100 - supports audio channel manipulation
;--- 200 - supports HSG AND red book addressing modes

ReqDevStat:
    mov @dword [Packet],0002A005Ah  ;Set up mode-sense.
    mov al,16           ;Set input byte count of 16.
    call DoBufIO        ;Issue mode-sense for hardware data.
    jc  DOSSkE          ;If error, post return code & exit.
    mov eax,00214h      ;Get our basic driver status flags.
@Status equ $-4         ;(Set by Init to 00204h for /AX).
    cmp @byte [edi+2],071h  ;"Unknown CD", i.e. door open?
    jne @F              ;No, check "locked" status.
    or  al,001h         ;Post "door open" status flag.
@@:
    test @byte [edi+14],002h ;Drive pushbutton "locked out"?
    jnz @F              ;No, set flags in IOCTL.
    or  al,002h         ;Set "door locked" status flag.
@@:
    mov [esi+1],eax     ;Set status flags in IOCTL buffer.
@RqDSX:
    jmp ReadAudioSt     ;Go post "busy" status and exit.
;
; IOCTL Input "Media-Change Status" handler.
;
ReqMCS:
    call DoIOCmd        ;Issue "Test Unit Ready" command.
    mov edi,[AudAP]     ;Get media-change flag from table.
    mov al,[edi-1]
    mov [esi+1],al      ;Return media-change flag to user.
    ret
;
; IOCTL Output "Eject Disk" handler.
;
ReqEjct:
    mov @word [Packet],0011Bh   ;Set "eject" commands.
    mov @byte [PktLBA+2],002h   ;Set "eject" function.
    jmp DOSSk1                  ;Go do "eject" & exit.
;
; IOCTL Output "Lock/Unlock Door" handler.
;
ReqDoor:
    mov al,[esi+1]          ;Get "lock" or "unlock" function.
    cmp al,001h             ;Is function byte too big?
    ja  RqRS1               ;Yes, post "General Failure" & exit.
    mov cx,0001Eh           ;Get "lock" & "unlock" commands.
RqDoor1:
    mov @word [Packet],cx   ;Set "packet" command bytes.
    mov @byte [PktLBA+2],al ;Set "packet" function byte.
    call DoIOCmd            ;Issue desired command to drive.
    jc  DOSSkE              ;If error, post return code & exit.
    jmp @RqDSX              ;Go post "busy" status and exit.
;
; IOCTL Output "Reset Drive" handler.
;
ReqRS:
    call StopDMA            ;Stop previous DMA & select drive.
    inc edx                 ;Point to IDE command register.
    mov al,008h             ;Do an ATAPI "soft reset" command.
    out dx,al
    call TestTO             ;Await controller-ready.
RqRS1:
    jc GenFail              ;Timeout!  Return "General Failure".
    ret
;
; IOCTL Output "Close Tray" handler.
;
ReqTray:
    mov al,003h             ;Get "close tray" function byte.
    mov cx,0011Bh           ;Get "eject" & "close" commands.
    jmp RqDoor1             ;Go do "close tray" command above.
;
; Subroutine to handle a Multi-Session disk for DOS reads and seeks.
;   Multi-Session disks require (A) saving the last-session starting
;   LBA for a new disk after any media-change and (B) "offsetting" a
;   read of the VTOC or initial directory block, sector 16 or 17, to
;   access the VTOC/directory of the disk's last session.
;
MultiS:
    mov edi,[AudAP]             ;Point to drive variables.
    cmp @byte [edi+11],0FFh     ;Is last-session LBA valid?
    jne MultiS1                 ;Yes, proceed with request.
    mov [PktOPC],043h           ;Set "Read TOC" command.
    inc @byte [PktLBA]          ;Set "format 1" request.
    mov al,12                   ;Set 12-byte allocation ct.
    call DoBufIO                ;Read first & last session.
    jc  MultiSX                 ;If any error, exit below.
    mov @byte [PktLBA],0        ;Reset "format 1" request.
    mov al,[edi+3]              ;Set last session in packet.
    mov [PktLH],al
    call DoIO                   ;Read disk info for last session.
    jc  MultiSX                 ;If error, exit with carry set.
    mov eax,[edi+8]             ;"Swap" & save this disk's last-
    call Swap32                 ;  session starting LBA address.
    mov edi,[AudAP]
    mov [edi.AUDADR.dwLSSta],eax
    call ZPacket                ;Reset our ATAPI packet area.
MultiS1:
    mov eax,[esi].RL.RLSec      ;Get starting sector number.
    mov edx,eax                 ;"Mask" sector to an even number.
    and dl,0FEh
    cmp edx,16                  ;Sector 16 (VTOC) or 17 (directory)?
    jne MultiS2                 ;No, set sector in packet.
    add eax,[edi+8]             ;Offset sector to last-session start.
MultiS2:
    call Swap32                 ;"Swap" sector into packet as LBA.
    mov [PktLBA],eax
    clc                         ;Clear carry flag (no errors).
MultiSX:
    ret

;--- read in internal buffer
;--- size in AL (12,16,4)
;--- the ATAPI command to perform is in PktOPC

DoBufIO:
    mov @byte [PktLn+1],al  ;Buffered -- set packet count.
DoBufIn:                    ;<--- entry with AL=8
    movzx eax,al            ;Save data-transfer length.
    mov [BufLng],eax
    mov [BufAdr],offset InBuf;Use our buffer for I-O.
    jmp DoIO                ;Go start I-O below.
DoIOCmd:
    mov [BufLng],0          ;Command only -- reset length.

;
;--- I-O Subroutine.   ALL of our CD-ROM I-O is executed here!
;--- ebx -> drive params
;--- Packet: ATAPI packet command to be sent
;--- esi must be preserved
;--- returns with C on errors, then AL contains error code
;--- edi is set to offset InBuf on exit
    
DoIO proc
    cld
    push esi
    mov [bTry],4            ;Set request retry count of 4.
DoIO1:                      ;<--- new try
    call StopDMA            ;Stop previous DMA & select drive.
    call TestTO             ;Await controller-ready.
    jc  DoIOErr             ;Timeout!  Handle as a "hard error".
    cmp [bDMA],0            ;UltraDMA input request?
    je  @F                  ;No, output our ATAPI "packet".
    mov dx,[ebx].UPARM.wDMABase;Point to DMA command register.
    mov al,008h             ;Reset DMA commands & set read mode.
    out dx,al
    inc edx                 ;Point to DMA status register.
    inc edx
    in  al,dx               ;Reset DMA status register.
    or  al,006h             ;(Done this way so we do NOT alter
    out dx,al               ;  the "DMA capable" status flags!).
    inc edx                 ;Set PRD pointer to our DMA address.
    inc edx
    mov eax,[PRDAd]
    out dx,eax
@@:
    mov dx,[ebx].UPARM.wIDEBase;Point to IDE "features" register.
    inc edx
    mov al,[bDMA]           ;If UltraDMA input, set "DMA" flag.
    out dx,al
    add edx,3               ;Point to byte count registers.
    mov eax,[BufLng]        ;Output data-transfer length.
    out dx,al
    inc edx
    mov al,ah
    out dx,al
    inc edx                 ;Point to command register.
    inc edx
    mov al,0A0h             ;Issue "Packet" command.
    out dx,al
    mov cl,DRQ              ;Await controller- and data-ready.
    call TestTO1
    jc  DoIOErr             ;Timeout!  Handle as a "hard error".
    xchg eax,esi            ;Save BIOS timer address.
    mov dx,[ebx].UPARM.wIDEBase;Point to IDE data register.
    mov ecx,6               ;Output all 12 "Packet" bytes.
    mov esi,offset Packet
    rep outsw
    xchg eax,esi            ;Reload BIOS timer address.
    mov ah,STARTTO          ;Allow 4 seconds for drive startup.
    cmp [bDMA],0            ;UltraDMA input request?
    je  DoPioIO             ;No, do "PIO mode" transfer below.
    mov [XFRLng],0          ;Reset transfer length (DMA does it).
    add ah,[esi]            ;Set 4-second timeout in AH-reg.

    mov @byte ds:[48Eh],0   ;Reset BIOS disk-interrupt flag.

    mov dx,[ebx].UPARM.wDMABase;Point to DMA command register.
    in  al,dx               ;Set DMA Start/Stop bit (starts DMA).
    or  al,1
    out dx,al

@@:
    inc edx                 ;Point to DMA status register.
    inc edx
    in  al,dx               ;Read DMA controller status.
    dec edx                 ;Point back to DMA command register.
    dec edx
    and al,DMI+DME          ;DMA interrupt or DMA error?
    jnz @F                  ;Yes, halt DMA and check results.
    cmp ah,[esi]            ;Has our DMA transfer timed out?
    jz  @F
    @VMMCall Yield           ;run client's ISRs
    cmp @byte ds:[48Eh],0   ;Did BIOS get a disk interrupt?
    je  @B                  ;No, loop back & retest status.
    mov al,DMI              ;Set "simulated" interrupt flag.
@@:
    xchg eax,esi            ;Save ending DMA status.
    in  al,dx               ;Reset DMA Start/Stop bit.
    and al,0FEh
    out dx,al
    xchg eax,esi            ;Reload ending DMA status.
    cmp al,DMI              ;Did DMA end with only an interrupt?
    jne DoIOErr             ;No?  Handle as a "hard error"!
    inc edx                 ;Reread DMA controller status.
    inc edx
    in  al,dx
    test al,DME             ;Any "late" DMA error after DMA end?
    jz  DoIO18              ;No, go await controller-ready.
    jmp DoIOErr             ;Timeouts and DMA errors are "hard"!
    align 4

;--- do PIO mode IO

DoPioIO:
    mov edx,[BufAdr]
    mov ecx,[BufLng]
    mov [XFRAdr],edx        ;reset data-transfer buffer address.
    mov [XFRLng],ecx        ;reset data-transfer byte count.
ContPioIO:                  ;<---
    xor cl,cl
    call TestTO2            ;await controller-ready (CL=flag, AH=time).
    jc  DoIOErr             ;Timeout!  Handle as a "hard error".
    test al,DRQ             ;Did we also get a data-request?
    jz  DoIO18              ;No, go await controller-ready.
    dec edx                 ;Get number of buffer bytes.
    dec edx
    in  al,dx
    mov ah,al
    dec edx
    in  al,dx
    inc eax                 ;Make buffer byte count "even".
    and eax,not 1
    movzx eax,ax
    mov dx,[ebx].UPARM.wIDEBase;Point to IDE data register.
    mov esi,[XFRLng]        ;Get our data-transfer length.
    test esi,esi            ;Any remaining bytes to transfer?
    jz  DoIO14              ;No, "eat" input or "pad" output.
    cmp esi,eax             ;Buffer count > remaining bytes?
    jbe @F                  ;No, save current block count.
    mov esi,eax             ;Set remaining bytes as block count.
@@:
    mov ecx,esi             ;Save current block count.
    mov edi,[XFRAdr]        ;Get input data-transfer address.
    shr ecx,1               ;Get input word count.
if DWRDIO
@DWOP::
    db 8Dh,9Bh,0,0,0,0      ;a 6 byte NOP (lea ebx,[ebx+0])
endif
    rep insw                ;Input all data words.
    mov [XFRAdr],edi
    sub [XFRLng],esi        ;Decrement data-transfer length.
    sub eax,esi             ;Decrement buffer count.
    jz DoIO17
DoIO14:
    xchg eax,ecx            ;Any "residual" bytes to handle?
    jecxz DoIO17            ;No, see if more I-O is needed.
    shr ecx,1               ;Get residual buffer word count.
@@:
    in  ax,dx               ;"Eat" residual input bytes.
    loop @B
DoIO17:
    mov ah,SEEKTO           ;Allow 2 seconds if drive must "seek".
    jmp ContPioIO           ;Go see if more I-O is needed.
    align 4

;--- Finish DMA/PIO
    
DoIO18:
    call TestTO             ;Await controller-ready.
    jc  DoIOErr             ;Timeout!  Handle as a "hard error".
    mov esi,[AudAP]         ;Get drive media-change flag pointer.
    dec esi
    and eax,1               ;Did controller detect any errors?
    jz  DoIO21              ;No, see if all data was transferred.
    sub edx,6               ;Get controller's sense key value.
    in  al,dx
    shr al,4
    cmp al,006h             ;Is sense key "Unit Attention"?
    je  DoIO23              ;Yes, check for prior media-change.
    mov ah,0FFh             ;Get 0FFh M.C. flag for "Not Ready".
    cmp al,002h             ;Is sense key "Drive Not Ready"?
    je  DoIO24              ;Yes, go set our media-change flag.
DoIOErr:
    mov dx,[ebx].UPARM.wIDEBase;Hard error!  Point to command reg.
    add edx,7
    mov al,008h             ;Issue ATAPI "soft reset" to drive.
    out dx,al
    mov al,11               ;Get "hard error" return code.
DoIO20:
    dec [bTry]              ;Do we have more I-O retries left?
    jnz DoIO1               ;Try re-executing this I-O request.
    stc
    jmp DoIOExit            ;No, return error code.
    align 4
    
;--- operation ended without error    
    
DoIO21:
    mov ecx,[XFRLng]        ;Get remaining data-transfer length.
    jecxz @F                ;If zero, reset media-change & exit.
    cmp @byte [Packet],028h ;"Cooked" data input req.?
    je  DoIOErr             ;Yes, see if we can retry.
    cmp @byte [Packet],0BEh ;"Raw" data input request?
    je  DoIOErr             ;Yes, see if we can retry.
    mov edi,[XFRAdr]        ;Load data-transfer address.
    rep stosb               ;"Pad" remaining bytes to 0.
@@:
    mov @byte [esi],1       ;Set "no media change" flag.
    clc                     ;Reset carry flag (no error).
DoIOExit:
    pop esi
    mov edi,offset InBuf    ;For audio, point to our buffer.
    ret

;--- operation ended with error "Unit Attention"
;--- esi=AudAP-1
;--- AH=
;--- AL=error code if byte ptr [esi] !=1
    
DoIO23:
    mov al,2                ;"Attention":  Get "Not Ready" code.
    cmp @byte [esi],0       ;Is media-change flag already set?
    jle DoIO20              ;Yes, retry & see if it goes away!
DoIO24:
    xchg ah,[esi]           ;Load & set our media-change flag.
    mov @byte [esi+12],0FFh ;Make last-session LBA invalid.
    dec ah                  ;Is media-change flag already set?
    jnz @F                  ;Yes, set carry flag and exit.
    mov al,15               ;Return "Invalid Media Change".
;	@dprintf <"DoIO, error 15, esi=%X, eax=%X",13,10>, esi, eax
@@:
    stc                     ;Set carry flag (error!).
    jmp DoIOExit
    align 4
DoIO endp
;
; Subroutine to convert "RedBook" MSF values to an LBA sector number.
;
ConvLBA:
    mov ecx,eax     ;Save "seconds" & "frames" in CX-reg.
    shr eax,16      ;Get "minute" value.
    cmp ax,99       ;Is "minute" value too large?
    ja  CnvLBAE     ;Yes, return -1 error value.
    cmp ch,60       ;Is "second" value too large?
    ja  CnvLBAE     ;Yes, return -1 error value.
    cmp cl,75       ;Is "frame" value too large?
    ja  CnvLBAE     ;Yes, return -1 error value.
    xor edx,edx     ;Zero EDX-reg. for 32-bit math below.
    mov dl,60       ;Convert "minute" value to "seconds".
    mul dl          ;(Multiply by 60, obviously!).
    mov dl,ch       ;Add in "second" value.
    add ax,dx
    mov dl,75       ;Convert "second" value to "frames".
    mul edx         ;(Multiply by 75 "frames"/second).
    mov dl,150      ;Subtract offset - "frame".
    sub dl,cl       ;("Adds" frame, "subtracts" offset).
    sub eax,edx
    ret
CnvLBAE:
    or  eax,-1      ;Too large!  Set -1 error value.
    ret
;
; Subroutine to clear our ATAPI "packet" area.
;
ZPacket:
    xor eax, eax
    mov @dword [Packet+0],eax   ;Zero ATAPI packet bytes.
    mov @dword [Packet+4],eax
    mov @dword [Packet+8],eax
    ret
;
; Subroutine to validate the starting disk sector number.
;
ValSN proc
    mov eax,[esi].RL.RLSec  ;Get starting sector number.
ValSN1::
    mov dl,[esi].RL.RLAM    ;Get desired addressing mode.
    cmp dl,001h             ;HSG or RedBook addressing?
    ja  ValSNE              ;Neither -- set carry and exit!
    jb  @F                  ;HSG -- check sector limit.
    call ConvLBA            ;Get RedBook starting sector.
@@: 
;   cmp eax,00006DD3Ah
    cmp eax,001000000h      ;Is starting sector too big?
    jb  done                ;No, all is well -- exit.
ValSNE:
    pop eax                 ;Error!  Discard our exit address.
    jmp SectNF              ;Post "sector not found" and exit.
done:
	ret
ValSN endp
;
;--- Subroutine to test for I-O timeouts.
;--- In: EBX=UPARM
;--- Out: DX=IDE primary-status register.
;--- modifies: eax, esi
;
TestTO proc
    xor cl,cl           ;Check for only controller-ready.
TestTO1::               ;<--- CL-reg = 008h to test for DRQ
    mov ah, CMDTO       ;Use 500-msec command timeout.
TestTO2::               ;<--- AH=STARTTO
    mov esi,BIOSTMR     ;0040:006Ch
    add ah,[esi]        ;Set timeout limit in AH-reg.
@@:
    @VMMCall Yield       ;preserves all registers
    cmp ah,[esi]        ;Has our I-O timed out?
    stc                 ;(If so, set carry flag).
    je  exit            ;Yes?  Exit with carry flag on.
    mov dx,[ebx].UPARM.wIDEBase
    add edx,7
    in  al,dx           ;Read IDE primary status.
    test al,BSY         ;Is our controller still busy?
    jnz @B              ;Yes, loop back and test again.
    or  cl,cl           ;Are we also awaiting I-O data?
    jz  exit            ;No, just exit.
    test al,cl          ;Is data-request (DRQ) also set?
    jz  @B              ;No, loop back and test again.
exit:
    ret                 ;Exit -- carry indicates timeout.
TestTO endp
;
; Subroutine to ensure UltraDMA is stopped and then select our CD-ROM
;   drive.   For some older chipsets, if UltraDMA is running, reading
;   an IDE register causes the chipset to "HANG"!!
;
StopDMA proc
    mov dx,[ebx].UPARM.wDMABase;Get drive UltraDMA command address.
    test dl,2+4             ;Is any UltraDMA controller present?
    jnz @F                  ;No, select "master" or "slave" unit.
    and dl,0FEh             ;Mask out "DMA disabled" flag.
    in  al,dx               ;Ensure any previous DMA is stopped!
    and al,0FEh
    out dx,al
@@:
    mov dx,[ebx].UPARM.wIDEBase;Point to IDE device-select register.
    add edx,6
    mov al,[ebx].UPARM.bDevSel ;Select IDE "master" or "slave" unit.
    out dx,al
    ret
StopDMA endp
;
; Subroutine to "swap" the 4 bytes of a 32-bit value.
;
Swap32:
    xchg al,ah      ;"Swap" original low-order bytes.
    rol eax,16      ;"Exchange" low- and high-order.
    xchg al,ah      ;"Swap" ending low-order bytes.
Swap32X:
    ret

;
; DOS "Audio Seek" handler.   All DOS and IOCTL routines beyond this
;   point are DISMISSED by driver-init when the /AX switch is given.
;
ReqSeek:
    call ReadAudioSt    ;Read current "audio" status.
    call ZPacket        ;Reset our ATAPI packet area.
    jc  RqSK1           ;If status error, do DOS seek.
    mov al,[edi+1]      ;Get "audio" status flag.
    cmp al,011h         ;Is drive in "play audio" mode?
    je  RqSK2           ;Yes, validate seek address.
    cmp al,012h         ;Is drive in "pause" mode?
    je  RqSK2           ;Yes, validate seek address.
RqSK1:
    jmp DOSSeek         ;Use DOS seek routine above.
RqSK2:
    call ValSN          ;Validate desired seek address.
    mov edi,[AudAP]     ;Point to audio-start address.
    cmp eax,[edi.AUDADR.dwAudEnd]     ;Is address past "play" area?
    ja  RqSK1           ;Yes, do DOS seek above.
    mov [edi.AUDADR.dwAudSta],eax     ;Update "audio" start address.
    call ConvMSF        ;Set "packet" audio-start address.
    mov @dword [PktLBA+1],eax
    mov eax,[edi.AUDADR.dwAudEnd]     ;Set "packet" audio-end address.
    call ConvMSF
    mov @dword [PktLH],eax
    mov @byte [Packet],047h ;Set "Play Audio" command.
    call DoIOCmd        ;Start drive playing audio.
    jc  RqPLE           ;If error, post code & exit.
    cmp @byte [edi+1],011h  ;Playing audio before?
    je  RqPLX           ;Yes, post "busy" status and exit.
    call ZPacket        ;Reset our ATAPI packet area.
    jmp ReqStop         ;Go put drive back in "pause" mode.
;
; DOS "Play Audio" handler.
;
ReqPlay:
    cmp [esi].RPPlay.dwSize,0   ;Is sector count zero?
    je  Swap32X                 ;Yes, just exit above.
    mov edi,[AudAP]             ;Point to audio-start addr.
    mov @byte [Packet],047h     ;Set "Play Audio" command.
    mov eax,[esi].RPPlay.dwStart;Validate starting address.
    call ValSN1
    mov [edi.AUDADR.dwAudSta],eax       ;Save audio-start address.
    call ConvMSF        ;Set MSF start address in packet.
    mov @dword [PktLBA+1],eax
    mov eax,[esi].RPPlay.dwSize ;calc "end" address.
    add eax,[edi.AUDADR.dwAudSta]
    mov edx,00006DD39h  ;Get maximum audio address.
    jc  ReqPL1          ;If "end" WAY too big, use max.
    cmp eax,edx         ;Is "end" address past maximum?
    jbe ReqPL2          ;No, use "end" address as-is.
ReqPL1:
    mov eax,edx         ;Set "end" address to maximum.
ReqPL2:
    mov [edi+4],eax     ;Save audio-end address.
    call ConvMSF        ;Set MSF end address in packet.
    mov @dword [PktLH],eax
    call DoIOCmd        ;Issue "Play Audio" command.
RqPLE:
    jc  ReqErr          ;Error!  Post return code & exit.
RqPLX:
    jmp RdAST3          ;Go post "busy" status and exit.
;
; DOS "Stop Audio" handler.
;
ReqStop:
    mov @byte [Packet],04Bh     ;Set "Pause/Resume" cmd.
    jmp DoIOCmd                 ;Go pause "audio", then exit.
;
; DOS "Resume Audio" handler.
;
ReqRsum:
    inc @byte [PktLn+1]         ;Set "Resume" flag for above.
    call ReqStop                ;Issue "Pause/Resume" command.
    jmp RqPLE                   ;Go exit through "ReqPlay" above.
;
; IOCTL Input "Current Head Location" handler.
;
ReqCHL:
;--- issue "read sub-channel" command (42h), MSF=0, SubQ=1
;--- data format to be returned is 01 (=Audio Status)
    mov @dword [Packet],001400042h   ;Set command bytes.
    mov al,16           ;Set input byte count of 16.
    call RdAST2         ;Issue "Read Subchannel" request.
    jc  RqPLE           ;If error, post return code & exit.
    mov @byte [esi+1],0 ;Return "HSG" addressing mode.
    mov eax,[edi+8]     ;Return "swapped" head location.
    call Swap32
    mov [esi+2],eax
    jmp RqATIX          ;Go post "busy" status and exit.
;
; IOCTL Input "Return Volume Size" handler.
;
ReqVolSize:
    mov @byte [Packet],025h  ;Set "Read Capacity" code.
    mov al,008h         ;Get 8 byte data-transfer length.
    call DoBufIn        ;Issue "Read Capacity" command.
    jc  RqPLE           ;If error, post return code & exit.
    mov eax,[edi]       ;Set "swapped" size in IOCTL packet.
    call Swap32
    mov [esi+1],eax
    jmp RqATIX          ;Go post "busy" status and exit.
;
; IOCTL Input "Audio Disk Info" handler.
;--- db ? ;lowest track number (binary)
;--- db ? ;highest track number (binary)
;--- dd ? ;start of lead-out track
;
ReqADI:
    mov al,0AAh         ;Specify "lead-out" session number.
    call ReadTOC        ;Read disk table-of-contents (TOC).
    jc  ReqErr          ;If error, post return code & exit.
    mov [esi+3],eax     ;Set "lead out" LBA addr. in IOCTL.
    mov ax,[edi+2]      ;Set first & last tracks in IOCTL.
    mov [esi+1],ax
    jmp RqATIX          ;Go post "busy" status and exit.
;
; IOCTL Input "Audio Track Info" handler.
;--- db ? ;track number (binary)
;--- dd ? ;start of track (red book format)
;--- db ? ;track control info (ADR=low nibble, CONTROL=high nibble)
;
ReqATI:
    mov al,[esi+1]      ;Specify desired session (track) no.
    call ReadTOC        ;Read disk table-of-contents (TOC).
    jc  ReqErr          ;If error, post return code & exit.
    mov [esi+2],eax     ;Set track LBA address in IOCTL.
    mov al,[edi+5]
    shl al,4
    mov [esi+6],al
RqATIX:
    jmp ReadAudioSt     ;Go post "busy" status and exit.
;
; IOCTL Input "Audio Q-Channel Info" handler.
;--- db ? ;+1 CONTROL (4-7) and ADR (0-3)
;--- db ? ;+2 track number (in BCD?)
;--- db ? ;+3 index (unchanged from disk)
;--- running time within track (binary)
;--- db ? ;+4 min
;--- db ? ;+5 sec
;--- db ? ;+6 frame
;--- db ? ;+7 zero
;--- running time on disk (binary)
;--- db ? ;+8 min
;--- db ? ;+9 sec
;--- db ? ;+10 frame

;--- the sub-channel data that is returned from the ATAPI device
;--- consists of a 4-byte header and 12 bytes data,
;--- the data's format depends on the format code:
;---  01: CD-ROM current position
;---  02: UPC/bar code
;---  03: ISRC code 
;--- data header:
;---  db ? ;+0 reserved
;---  db ? ;+1 Audio Status
;---  dw ? ;+2 sub-channel data length
;--- data (CD-ROM current position):
;---  db ? ;+4 data format code ( =01 )
;---  db ? ;+5 ADR (bits 7-4) CONTROL (bits 3-0)
;---  db ? ;+6 track number
;---  db ? ;+7 index number
;---  dd ? ;+8 absolute CD-ROM address
;---  dd ? ;+12 track-relative CD-ROM address

ReqAQI:
    mov ax,04010h       ;read sub-channel, SubQ=1, use 16-byte count.
    call RdAST1         ;Read sub-channel
    jc  ReqErr          ;If error, post return code (AL) & exit.
    mov edx,[edi+5]     ;Set ctrl/track/index in IOCTL.
if 1
;--- xchg ADR and CONTROL
    rol dl,4
;--- convert TNO to BCD
;--- ensure that conversion is done only when ADR is 1
;    mov al,dl
;    and al,0Fh
;    cmp al,1
;    jnz @F
    mov al,dh
    aam                 ;converts binary in AL to BCD in AH,AL
    db 0d5h,10h         ;packs 2 BCD digits in AH,AL into AL
    mov dh,al
@@:
endif
    mov [esi+1],edx
    mov eax,[edi+13]    ;Set time-on-track in IOCTL.
    mov [esi+4],eax
    mov edx,[edi+9]     ;Get time-on-disk & clear high
    shl edx,8           ;  order time-on-track in IOCTL.
    mov [esi+7],edx     ;Set time-on-disk
    ret
;
; IOCTL Input "Audio Status Info" handler.
;
ReqASI:
    mov ax,04010h       ;Set SubQ=1, use 16-byte count.
    call RdAST1         ;Read sub-channel
    jc  ReqErr          ;If error, post return code & exit.
    xor eax,eax         ;Reset starting audio address.
    mov [esi+1],ax      ;Reset audio "paused" flag.
    xor edx,edx         ;Reset ending audio address.
    cmp @byte [edi+1],011h  ;Is drive now "playing" audio?
    jne @F              ;No, check for audio "pause".
    mov edi,[AudAP]     ;Point to drive's audio data.
    mov eax,[edi.AUDADR.dwAudSta]     ;Get current audio "start" addr.
    call ConvMSF
    jmp RqASI2          ;Go get current audio "end" addr.
@@:
    cmp @byte [edi+1],012h  ;Is drive now in audio "pause"?
    jne RqASI3              ;No, return "null" addresses.
    or @byte [esi+1],1      ;Set audio "paused" flag.
    mov eax,[edi+8]         ;Convert time-on-disk to LBA addr.
    call Swap32
;--- do not convert to LBA
;    call ConvLBA
    mov edi,[AudAP]     ;Point to drive's audio data.
RqASI2:
    push eax
    mov eax,[edi.AUDADR.dwAudEnd]     ;Get current audio "end" address.
    call ConvMSF
    call Swap32
    shr eax, 8
    mov edx, eax
    pop eax
RqASI3:
    mov [esi+3],eax ;Set audio "start" addr. in IOCTL.
    mov [esi+7],edx ;Set audio "end" address in IOCTL.
    ret
;
; Subroutine to read the current "audio" status and disk address.
;
ReadAudioSt:
    call ZPacket        ;Status only -- reset ATAPI packet.
    mov ax,00004h       ;set SubQ=0, use 4-byte count.
RdAST1:                 ;<--- entry ReqAQI, ReqASI (ax=4010h)
;--- issue a "read sub-channel" packet command (42h)
;--- MSF (bit 1 of byte 1) is 1
;--- data format is 1 (=Audio Status)
    mov @dword [Packet],001000242h  ;Set command bytes.
    mov @byte [PktLBA],ah           ;Set SubQ flag (bit 6)
RdAST2:
    call DoBufIO                ;Issue "Read Subchannel" command.
    jc  RdASTX                  ;If error, exit immediately.
    cmp @byte [edi+1],011h      ;Is a "play audio" in progress?
    jnz RdTOC1                  ;No, clear carry flag and exit.
RdAST3:
    push esi                    ;Save SI- and ES-regs.
    mov esi,[dwRequest]         ;Reload DOS request-packet addr.
    or [esi].RPH.wStat,RPBUSY   ;Set "busy" status bit.
    pop esi
RdASTX:
    ret
;
; Subroutine to read disk "Table of Contents" (TOC) values.
;
ReadTOC:
    mov @word [Packet],00243h   ;Set TOC and MSF bytes.
    mov [PktLH],al              ;Set desired "session" number.
    mov al,12                   ;Get 12-byte "allocation" count.
    call DoBufIO                ;Issue "Read Table of Contents" cmd.
    jc  RdTOCX                  ;If error, exit immediately.
    mov eax,[edi+8]             ;Return "swapped" starting address.
    call Swap32
RdTOC1:
    clc         ;Clear carry flag (no error).
RdTOCX:
    ret
    align 4
;
; Subroutine to convert an LBA sector number to "RedBook" MSF format.
;
ConvMSF:
    add eax,150     ;Add in offset.
    push eax        ;Get address in DX:AX-regs.
    pop ax
    pop dx
    mov cx,75       ;Divide by 75 "frames"/second.
    div cx
    shl eax,16      ;Set "frames" remainder in upper EAX.
    mov al,dl
    ror eax,16
    mov cl,60       ;Divide quotient by 60 seconds/min.
    div cl
    ret             ;Exit -- EAX-reg. contains MSF value.

;--- set device name (/D:xxxx)

I_SetName proc    
    mov edi,[dwBase]    ;Blank out device name.
    add edi,10
    lea edx,[edi+8]
    mov eax,"    "
    mov [edi+0],eax
    mov [edi+4],eax
I_NameB:
    mov al,[esi]    ;Get next device-name byte.
    cmp al,TAB      ;Is byte a "tab"?
    je  I_NxtCJ     ;Yes, handle above, "name" has ended!
    cmp al,' '      ;Is byte a space?
    je  I_NxtCJ     ;Yes, handle above, "name" has ended!
    cmp al,'/'      ;Is byte a slash?
    je  I_NxtCJ     ;Yes, handle above, "name" has ended!
    cmp al,0        ;Is byte the command-line terminator?
    je  I_NxtCJ     ;Yes, go test for UltraDMA controller.
    cmp al,LF       ;Is byte an ASCII line-feed?
    je  I_NxtCJ     ;Yes, go test for UltraDMA controller.
    cmp al,CR       ;Is byte an ASCII carriage-return?
    je  I_NxtCJ     ;Yes, go test for UltraDMA controller.
    cmp al,'a'      ;Ensure letters are upper-case.
    jc  I_Name2
    cmp al,'z'
    ja  I_Name2
    and al,0DFh
I_Name2:
    cmp al,'!'      ;Is this byte an exclamation point?
    jz  I_Name3     ;Yes, store it in device name.
    cmp al,'#'      ;Is byte below a pound-sign?
    jb  I_Name4     ;Yes, Invalid!  Blank first byte.
    cmp al,')'      ;Is byte a right-parenthesis or less?
    jbe I_Name3     ;Yes, store it in device name.
    cmp al,'-'      ;Is byte a dash?
    jz  I_Name3     ;Yes, store it in device name.
    cmp al,'0'      ;Is byte below a zero?
    jb  I_Name4     ;Yes, invalid!  Blank first byte.
    cmp al,'9'      ;Is byte a nine or less?
    jbe I_Name3     ;Yes, store it in device name.
    cmp al,'@'      ;Is byte below an "at sign"?
    jb  I_Name4     ;Yes, invalid!  Blank first byte.
    cmp al,'Z'      ;Is byte a "Z" or less?
    jbe I_Name3     ;Yes, store it in device name.
    cmp al,'^'      ;Is byte below a carat?
    jb  I_Name4     ;Yes, invalid!  Blank first byte.
    cmp al,'~'      ;Is byte above a tilde?
    ja  I_Name4     ;Yes, invalid!  Blank first byte.
    cmp al,'|'      ;Is byte an "or" symbol?
    je  I_Name4     ;Yes, invalid!  Blank first byte.
I_Name3:
    stosb           ;Store next byte in device name.
    inc esi         ;Bump command-line pointer.
    cmp edi,edx     ;Have we stored 8 device-name bytes?
    jb  I_NameB     ;No, go get next byte.
I_NxtCJ:
    ret
I_Name4:
    mov @byte [edx-8],' '
    ret
I_SetName endp    

;--- handle /AX option

I_SetAX proc
    mov eax,offset UnSupp   ;Disable all unwanted dispatches.
    mov [@RqPlay],eax       ; play audio
    mov [@RqStop],eax       ; stop audio
    mov [@RqRsum],eax       ; resume audio
    mov [@RqCHL],eax        ; current head location
    mov [@RqADI],eax        ; audio disk info
    mov [@RqATI],eax        ; audio track info
    mov [@RqAQI],eax        ; audio q-channel info
    mov [@RqASI],eax        ; audio status info
    mov eax,offset DOSSeek  ;Do only LBA-address DOS seeks.
    mov [@RqPref],eax
    mov [@RqSeek],eax
    mov al,004h                     ; Have "Device Status" declare
    mov @byte ds:[@Status],al       ; we handle DATA reads only

;---  have it NOT update the IOCTL "busy" flag & return.
;---  ["ReadAudioSt" gets DISMISSED]!

    mov @byte ds:[@RqDSX], 0C3h
    ret
I_SetAX endp

;--- for SATA controllers, check if AHCI mode is disabled
;--- in: EAX=phys. address HBA

IsAHCIdisabled proc uses edi ebx

	@dprintf <"SATA controller at %X",13,10>, eax
	mov edi, eax
    push 0
    push 1
    push PR_SYSTEM
    @VMMCall _PageReserve    ;allocate a 4 kB block of address space
    add esp,3*4
    cmp eax,-1
    jz error
    mov ebx, eax            ; save linear address in ebx
    @dprintf <"HBA mapped at %X",13,10>, ebx

    shr eax, 12             ;convert linear address to page number

    push PC_INCR or PC_WRITEABLE
    mov edx, edi
    shr edx, 12
    push edx
    push 1
    push eax
    @VMMCall _PageCommitPhys ;backup address space
    add esp,4*4

	and edi, 0fffh
	mov eax, [ebx+edi+4]

	@dprintf <"HBA.GHC=%X",13,10>, eax

;--- todo: free address space

	and eax, eax
	js error
	or eax, -1
	ret
error:
	xor eax, eax
	ret
IsAHCIdisabled endp

;
; Driver Initialization Routine.
;
I_Init proc
    cld
    mov esi,[dwRequest] ;Point to DOS request packet.
    cmp [esi].RPINIT.bOp,0 ;Is this an "Init" packet?
    jnz I_BadP
    mov esi,[dwCmdLine] ;Point to command line that loaded us.
I_NxtC:
    lodsb           ;Get next command-line byte.
    cmp al,0
    je  I_Term
    cmp al,LF
    je  I_Term
    cmp al,CR
    je  I_Term
    cmp al,'-'      ; a dash?
    je  @F          ; Yes, see what next "switch" byte is.
    cmp al,'/'      ; a slash?
    jne I_NxtC      ; No, check next command-line byte.
@@:
    mov ax,[esi]    ;Get next 2 command-line bytes.
    or  ax,2020h    ;convert to lower case
    cmp ax,'xu'     ;/UX?
    jne @F
    inc esi         ;Bump pointer past "UX" switch.
    inc esi
    or [bFlags],FL_UX
    jmp I_NxtC
@@:
    cmp al,'f'      ;/F?
    jnz @F
    inc esi
    or [bFlags],FL_F
    jmp I_NxtC
@@:
    cmp ax,'xa'     ;/AX?
    jne @F
    inc esi         ;Bump pointer past "ax"
    inc esi
    call I_SetAX
    jmp I_NxtC
@@:
if DWRDIO
    cmp ax,"23"     ;/32?
    jnz @F
    inc esi
    inc esi
    mov @dword ds:[@DWOP+0],6DF3E9D1h   ;shr ecx,1  rep insd
    mov @word ds:[@DWOP+4],0C911h       ;adc ecx,ecx
    jmp I_NxtC
@@:
endif
    cmp al,'l'      ;/L?
    jne @F
    mov @byte [@DMALmt],009h  ;Set 640K "DMA limit" above.
    inc esi         ;Bump pointer past "limit" switch.
    jmp I_NxtC
@@:
if SETMODE
    cmp al,'m'      ;Is this byte an "M" or "m"?
    jne @F
    inc esi         ;Bump pointer past "mode" switch.
    cmp ah,'7'
    ja  I_NxtC
    sub ah,'0'
    jb  I_NxtC
    mov [MaxUM],ah  ;Set maximum UltraDMA "mode" above.
    inc esi         ;Bump pointer past "mode" value.
    jmp I_NxtC
@@:
endif

I_ChkD:
    cmp al,'d'      ;Is switch byte a "D" or "d"?
    jne @F
    inc esi         ;Bump pointer past "device" switch.
    cmp ah,':'      ;Is following byte a colon?
    jne I_NxtC
    inc esi         ;Bump pointer past colon.
    call I_SetName
    jmp I_NxtC
@@:
if MWDMA
    cmp al,'w'      ;/W?
    jnz @F
    or [bFlags],FL_W
    inc esi
    jmp I_NxtC
@@:
endif
    cmp al,'q'
    jnz I_NxtC
    inc esi
    or [bFlags],FL_Q
    jmp I_NxtC

getpci:
	mov dx, 0cf8h
	out dx, eax
	add dl, 4
	in eax, dx
	sub dl, 4
	ret
setpci:
	mov dx, 0cf8h
	out dx, eax
	add dl, 4
	mov eax, ecx
	out dx, eax
	sub dl, 4
	ret

;--- done cmdline parsing

I_Term:

	test [bFlags],FL_Q
	jnz @F
    invoke printf, CStr('XCDROM32 ',VER,'.',CR,LF)
@@:

;--- check for PCI BIOS

	mov @word [ebp].Client_Reg_Struc.Client_EAX, 0B101h ; get PCI BIOS version
	@VMMCall Begin_Nest_Exec
	mov eax, 1Ah
	@VMMCall Exec_Int
	@VMMCall End_Nest_Exec
    mov edx, [ebp].Client_Reg_Struc.Client_EDX

    cmp edx," ICP"          ;Do we have a V2.0C or newer PCI BIOS?
    jne I_ChkNm             ;No, check for valid driver name.

;--- scan for native/legacy IDE controllers
;--- rewritten for v1.5

	mov edi, [pScan]
	mov esi, 80000008h
I_FindC:
	mov eax, esi
	call getpci
	shr eax, 8
	mov ebx, eax
	and al, 80h
	cmp eax, 10180h         ;storage+IDE+busmaster?
	jz isEIDE
	cmp ebx, 10601h         ;SATA controller?
	jz isSATA
I_ContFindC:
	@VMMCall Yield
	add esi, 100h
	cmp esi, 81000008h
	jb I_FindC
	jmp I_DoneScan
isSATA:
;--- for SATA controllers, check if AHCI is enabled
	mov eax, esi
	mov al, 16+5*4
	call getpci
	and al, 0fch
	call IsAHCIdisabled
	and eax, eax
	jz I_ContFindC          ;if AHCI active, ignore device
isEIDE:
if SETBM
	mov eax, esi
	mov al, 4
	call getpci
	bts eax, 2              ;busmaster enabled?
	jc @F
;--- enable busmaster
	mov ecx, eax
	mov eax, esi
	mov al, 4
	call setpci
@@:
endif

	mov eax, esi
	mov al,16+4*4           ;Get DMA base address (register 4).
	call getpci
	and al,0FCh
	mov ecx, eax

	test bl, 1              ;primary in "native" mode?
	jnz prim_native
	mov ax, 1F0h
	bts dword ptr bLegacy, 0
	jnc @F
	or eax, -1
	jmp @F
prim_native:
	mov eax, esi
	mov al,16+0*4           ;Get primary channel base port
	call getpci
	and al,0FCh
@@:
	mov [edi+0*sizeof IDEPARM].IDEPARM.wIDEBase, ax
	mov [edi+0*sizeof IDEPARM].IDEPARM.wDMABase, cx
	mov [edi+1*sizeof IDEPARM].IDEPARM.wIDEBase, ax
	mov [edi+1*sizeof IDEPARM].IDEPARM.wDMABase, cx

	test bl, 4              ;secondary in "native" mode?
	jnz sec_native
	mov ax, 170h
	bts dword ptr bLegacy, 1
	jnc @F
	or eax, -1
	jmp @F
sec_native:
	mov eax, esi
	mov al,16+2*4           ;Get secondary channel base port
	call getpci
	and al,0FCh
@@:
	add ecx, 8
	mov [edi+2*sizeof IDEPARM].IDEPARM.wIDEBase, ax
	mov [edi+2*sizeof IDEPARM].IDEPARM.wDMABase, cx
	mov [edi+3*sizeof IDEPARM].IDEPARM.wIDEBase, ax
	mov [edi+3*sizeof IDEPARM].IDEPARM.wDMABase, cx

	@dprintf <"controller primary base=%X, secondary base=%X, dmabase=%X",13,10>, [edi].IDEPARM.wIDEBase, ax, [edi].IDEPARM.wDMABase
	test [bFlags], FL_Q
	jnz @F
	mov eax, esi
	shr eax, 16
	mov ah, 0
	mov edx, esi
	shr edx, 11
	and edx, 1Fh
	mov ecx, esi
	shr ecx, 8
	and ecx, 7
	invoke printf, CStr("IDE controller at bus/dev/fn=%u/%u/%u, P/S/DMA=%X/%X/%X",CR,LF), eax, edx, ecx, [edi].IDEPARM.wIDEBase, [edi+2*sizeof IDEPARM].IDEPARM.wIDEBase, [edi].IDEPARM.wDMABase
@@:
	add edi, 4 * sizeof IDEPARM
	cmp edi, offset ScanLPM + sizeof ScanLPM
	jb I_ContFindC              ;continue PCI scan
I_DoneScan:
	mov [pScan], edi

;--- done controller scan

I_ChkNm:
	cmp [pScan], offset ScanLPM ; any PCI IDE controller found?
	jnz @F
	mov ax, 1F0h                ; if no, check legacy ports
	mov [ScanLPM+0*sizeof IDEPARM].wIDEBase, ax
	mov [ScanLPM+1*sizeof IDEPARM].wIDEBase, ax
	mov ax, 170h
	mov [ScanLPM+2*sizeof IDEPARM].wIDEBase, ax
	mov [ScanLPM+3*sizeof IDEPARM].wIDEBase, ax
	add [pScan], 4 * sizeof IDEPARM
@@:

    mov ecx,[dwBase]
    cmp @byte [ecx+10],' '      ;Is driver "name" valid?
    jnz @F
    mov @dword [ecx+10],"RDCX"  ;Set our default "name".
    mov @dword [ecx+10+4],"$$MO"
@@:
	test [bFlags],FL_Q
	jnz @F
    mov eax,[ecx+10+0]
    mov @dword [szDriver+0],eax
    mov eax,[ecx+10+4]
    mov @dword [szDriver+4],eax
    invoke printf, CStr('Driver name is %s.',13,10), offset szDriver
@@:
    
    mov esi, offset DmaAdr
    mov ecx, 4*4
    xor edx, edx
    VxDCall VDMAD_Lock_DMA_Region
    mov [PRDAd],edx             ;Set physical PRD address.

if 0
    test [bFlags],FL_UX         ;Did user disable UltraDMA?
    jnz I_LinkX                 ;Yes, proceed
    cmp @byte [@DMALmt],-1      ;Is UltraDMA limited to < 640K?
    je  I_LinkX                 ;No, proceed
    mov edx,offset LEMsg        ;Point to "/L Invalid" message.
    cmp @word [DmaAdr+2],009h   ;Are we loaded high?
    ja  I_InitE                 ;Yes?  Display message and exit!
I_LinkX:
endif

    @dprintf <"Start drive scan",CR,LF>
    mov [pUTbl], offset UnitTbl ;Reset our unit-table pointer.

I_ScanU:                    ;<--- try next
    mov ebx,[ScanX]         ;Get current parameters index.
    cmp ebx,[pScan]         ;Any more IDE units to check?
    je  I_AnyCD             ;No, check for any drives to use.
    add [ScanX], sizeof IDEPARM

    mov ax,[ebx].IDEPARM.wIDEBase;Get unit's IDE address
    cmp ax,-1               ;valid address?
    je  I_ScanU             ;no, skip this entry

    call I_ValDV            ;check if device is an ATAPI CD-ROM
    jnc  I_ScnVN            ;if yes, display device and update UnitTbl
if ?EXTDISP
	invoke printf, CStr("port %X,dev=%X: v86 ss:sp=%X:%X, %s",13,10),
		[ebx].IDEPARM.wIDEBase,
		@word [ebx].IDEPARM.bDevSel,
		[ebp].Client_Reg_Struc.Client_SS,
		[ebp].Client_Reg_Struc.Client_ESP, edi
else
	@VMMCall Yield           ;don't remove, may avoid v86 stack errors
endif
    jmp I_ScanU             ;try next unit.
I_ScnVN:
    test [bFlags],FL_UX     ;Was the /UX switch given?
    je  @F
    or  @byte [ebx].UPARM.wDMABase,1   ;Post drive "DMA disabled".
@@:
	test [bFlags],FL_Q
	jnz nodisp

    mov edi,offset DrvName + sizeof DrvName
@@:
    mov @byte [edi],0       ; skip trailing spaces of drive name
    dec edi
    cmp @byte [edi],' '
    je  @B

    mov edx, CStr("Master")
    test [ebx].IDEPARM.bDevSel,10h
    jz  @F
    mov edx, CStr("Slave")
@@:
	invoke printf, CStr("Unit %u: %s, IDE/DMA ports %X/%X, %s, "),
		UnitNo, edx, [ebx].IDEPARM.wIDEBase, [ebx].IDEPARM.wDMABase, offset DrvName
	mov ecx,CStr("PIO mode",13,10)
	test @byte [ebx].IDEPARM.wDMABase,7  ;Will drive be using UltraDMA?
	jnz @F
	mov ecx, CStr("ATA-%u",13,10)
@@:
	invoke printf, ecx, wDmaMode
if ?EXTDISP
	invoke printf, CStr("v86 ss:sp=%X:%X",13,10),[ebp].Client_Reg_Struc.Client_SS,
		[ebp].Client_Reg_Struc.Client_ESP
endif
nodisp:

    mov esi,[pUTbl]         ;Update all unit-table parameters.
    mov ax,[ebx].IDEPARM.wIDEBase
    mov cx,[ebx].IDEPARM.wDMABase
    mov dl,[ebx].IDEPARM.bDevSel
    mov [esi].UPARM.wIDEBase,ax
    mov [esi].UPARM.wDMABase,cx
    mov [esi].UPARM.bDevSel,dl
    add esi,sizeof UPARM    ;Update unit-table pointer.
    mov [pUTbl],esi

;   inc @byte [Units]       ;Bump number of active units.
    mov eax, [dwBase]
    inc [eax].DOSDRV.bUnits

    inc [UnitNo]            ;Bump display unit number.
    cmp esi,offset UnitTbl + sizeof UnitTbl ;end of table reached?
    jb  I_ScanU             ;no, loop back & check for more.
I_AnyCD:

    @dprintf <"End drive scan",CR,LF>

;   cmp [Units],0           ;Do we have any CD-ROM drives to use?
    mov edx, [dwBase]
    cmp [edx].DOSDRV.bUnits,0 ;Do we have any CD-ROM drives to use?

    ja  I_ClrSt             ;Yes, success
    mov edx, CStr('No CD-ROM drive to use')
I_InitE:
    invoke printf, CStr('%s; XCDROM32 not loaded!',CR,LF), edx
I_BadP:
    xor eax,eax             ;Get "null" length & error flags.
    mov dx,RPDON+RPERR
    jmp I_Exit              ;Go set "init" packet values & exit.
I_ClrSt:

if 0
	invoke printf, CStr("xcdrom32: v86 ss:sp=%X:%X",CR,LF),
		[ebp].Client_Reg_Struc.Client_SS, [ebp].Client_Reg_Struc.Client_ESP
endif

    mov dx,RPDON            ;Get initialization "success" code.
    mov ax,12h+4+SIZERMCODE+5
I_Exit:
    mov esi,[dwRequest]     ;Set result values in "init" packet.
    mov [esi].RPINIT.RPSize,ax
    mov [esi].RPINIT.wStat,dx
    mov [esi].RPINIT.bUnit,0
    mov eax, edx
    ret
I_Init endp
;
; Subroutine to "validate" an IDE unit as an ATAPI CD-ROM drive.
; in: ebx = IDEPARM
; ebx must be preserved!
;
I_ValDV proc

    call StopDMA        ;Stop previous DMA & select drive.
    mov edi,CStr('Device select timeout')
    call TestTO         ;Await controller-ready (sets DX to ATA cmd port)
    jc  I_Val7          ;If timeout, go post pointer & exit.

;--- check if BSY and DRQ are 0; bit 6 (device ready ) should be 1,
;--- but this is nothing to rely on...
    and al, BSY or DRQ  ;check BSY+DRQ, both must be 0
    jnz I_Val7

if IDENTPKT
    @dprintf <"ValDV: ready, base=%X, executing Identify Packet command",CR,LF>, [ebx].UPARM.wIDEBase
    mov al,0A1h         ;Issue "Identify Packet Device" cmd.
else
    @dprintf <"ValDV: ready, base=%X, executing Identify command",CR,LF>, [ebx].UPARM.wIDEBase
    mov al,0ECh         ;Issue "Identify Device" cmd.
endif
    out dx,al
    call TestTO         ;Await controller-ready.
    mov edi, CStr('Identify Device error')
ifdef _DEBUG
    pushfd
    lahf
    @dprintf <"ValDV: Identify Packet command returned, ax=%X",CR,LF>, ax
    popfd
endif
    jc  I_Val7          ;If timeout, go post pointer & exit.
    test al,ERR         ;non-ATAPI devices will respond with ERR set
    jnz I_Val6

if 1
	@dprintf <"ValDV, identify ok, al=%X, port=%X",CR,LF>, eax, [ebx].UPARM.wIDEBase
else
	invoke printf, CStr("ValDV, identify ok, al=%X, port=%X",CR,LF), eax, [ebx].UPARM.wIDEBase
endif

    sub edx,7           ;Point back to IDE data register.
    mov ecx,90
    sub esp,ecx
    sub esp,ecx
    mov edi,esp
    rep insw
    mov ecx,256-90      ;skip the rest
@@:
    in  ax,dx
    loop @B
    
    mov edi,offset DrvName ;Point to drive "name" input buffer.
    mov cl,20           ;Read & swap words 27-46 into buffer.
    lea esi,[esp+27*2]  ;(Manufacturer "name" of this drive).
@@:
    lodsw
    xchg al,ah
    stosw
    loop @B

    mov esi,esp
    mov al,[esi+53*2]
    mov [UFlag],al      ;Save UltraDMA "valid" flags.
    mov dx,[esi+88*2]
    mov [UMode],dh      ;Save current UltraDMA "mode" value.
                        ;"supported" UDMA "modes" is in DL

    mov ax,[esi+0*2]    ;Get I.D. word 0, main device flags.
if MWDMA
    mov ch,[esi+63*2+1] ;copy multiword flags to CH
endif    
    add esp,90*2        ;restore ESP
    
    and ax,0DF03h       ;Mask off flags for an ATAPI CD-ROM.
    cmp ax,08500h       ;Do device flags say "ATAPI CD-ROM"?
    je  I_Val9          ;Yes, see about UltraDMA use.
I_Val6:
    mov edi, CStr("No ATAPI CD-ROM")
I_Val7:
    stc                 ;Set carry flag on (error!).
I_Val8:
    ret
I_Val9:

    @dprintf <"ATAPI CDROM detected",CR,LF>

    test @byte [ebx].UPARM.wDMABase,7  ;Will we be using UltraDMA?
    jnz I_Val8                      ;No, go exit above.
    test @byte [UFlag], 4           ;Valid UltraDMA "mode" bits?
    jz  noudma                      ;No, jump

if SETMODE
    cmp [MaxUM],-1      ;/Mn switch used?
    jz nomopt
    movzx edx,dl        ;supported UDMA modes in EDX now
    bsr eax, edx
    jz nomopt
    mov dl,[MaxUM]
    cmp dl,al           ;supported mode < /Mn?
    jb @F
    mov dl,al
@@:
    bts @word [UMode],dx
    mov ah,dl
    mov dx,[ebx].UPARM.wIDEBase    ;Point to IDE "features" register.
    inc edx
    mov al,SETM         ;Set mode-select subcode.
    out dx,al
    inc edx             ;Point to IDE sector-count register.
    mov al,ah           ;Set desired UltraDMA mode.
    or  al,040h
    out dx,al
    add edx,5           ;Point to IDE command register.
    mov al,SETF         ;Issue "set features" command.
    out dx,al
    call TestTO         ;Await controller-ready.
    test al, ERR
    jz nomopt
    invoke printf, CStr('UltraDMA Set Mode failed',CR,LF)
nomopt:
endif
    mov edi,offset UModes
    mov al,[UMode]              ;Get UltraDMA "mode" value.
    or  al,al                   ;Can drive do mode 0 minimum?
    jnz I_Val11                 ;Yes, set up UltraDMA mode 0.
noudma:
if MWDMA
    test [bFlags],FL_W          ;handle multiword DMA devices?
    jz @F
    mov [MaxUM],-1
    mov al,ch
    mov edi,offset MWModes
    or al,al                    ;is a MW-DMA mode set?
    jnz I_Val11
@@:
endif
I_Val10:
    or  @byte [ebx].UPARM.wDMABase,1   ;Post drive "DMA disabled".
    ret                         ;Exit -- must use "PIO mode"!
I_Val11:
    movzx eax,al
    bsr ecx, eax
    cmp cl,[MaxUM]
    jbe @F
    mov cl,[MaxUM]
@@:
    mov ax,@word [ecx*2+edi]
    mov wDmaMode, ax
    clc
    ret
I_ValDV endp


DllMain proc stdcall public hModule:dword, dwReason:dword, dwRes:dword

    mov eax,dwReason
    cmp eax, 1
    jnz done
;   .if (dwReason == 1)

        mov esi, dwRes
        test [esi].JLCOMM.wFlags, JLF_DRIVER
        jz failed
        movzx ecx,[esi].JLCOMM.wLdrCS
        shl ecx, 4
        mov dwBase, ecx
        lea eax, [ecx+REQOFS]
        mov pRequest, eax
        mov eax,[esi].JLCOMM.lpCmdLine
        mov dwCmdLine, eax
        mov eax,[esi].JLCOMM.lpRequest
        mov dwRequest, eax

        mov esi, offset DevInt
        xor edx, edx
        @VMMCall Allocate_V86_Call_Back
        jc failed

        mov edi, dwBase
        mov [edi].DOSDRV.wAttr, 0C800h    ;driver attributes
        mov [edi].DOSDRV.ofsStr, REQOFS+4
        mov [edi].DOSDRV.ofsInt, REQOFS+4+SIZERMCODE
        mov [edi].DOSDRV.wRes1, 0
        mov [edi].DOSDRV.bRes2, 0
        mov [edi].DOSDRV.bUnits, 0

        add edi, REQOFS+4
        mov esi, offset rmcode
        mov ecx, SIZERMCODE+1
        rep movsb
        stosd

;--- set EBP to the client pointer before calling I_Init

        push ebp
        @VMMCall Get_Cur_VM_Handle
        mov ebp,[ebx].cb_s.CB_Client_Pointer
if SAVESTAT
        sub esp, sizeof Client_Reg_Struc
        mov edi, esp
        @VMMCall Save_Client_State
endif

        call I_Init

        cmp ax,RPDON
        setz al
if SAVESTAT
        movzx edi,al
        mov esi, esp
        @VMMCall Restore_Client_State
        add esp, sizeof Client_Reg_Struc
        mov eax, edi
else
        movzx eax, al
endif
        pop ebp
;    .endif
done:
    ret
failed:
    xor eax, eax
    ret

DllMain endp

    end DllMain

