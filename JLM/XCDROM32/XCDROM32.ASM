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

;--- /PM, /PS, /SM and /SS are disabled for XCDROM32!
;
;  /PM   Requests the driver to check the IDE primary-master unit for
;        a CD-ROM drive during driver init.    If a CD-ROM drive is
;        NOT found as primary-master, driver loading will ABORT!
;
;  /PS   Same as /PM but tests the primary-slave unit only.
;
;  /SM   Same as /PM but tests the secondary-master unit only.
;
;  /SS   Same as /PM but tests the secondary-slave unit only.
;
;        --- NOTE ---
;        Using multiple drives, multiple  /PM /PS /SM /SS  switches
;        can be given.    The first-specified drive is addressed as
;        "unit 0", the second as "unit 1", etc.   If fewer switches
;        than drives are given, the unreferenced drives will NOT be
;        used.    If NO such switches are given, the driver "scans"
;        for CD-ROM drives, from primary-master to secondary-slave.
;        The first drive found will be "unit 0", the second will be
;        "unit 1", etc.
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

;
; General Program Equations.
;

SUPPPS      equ 0       ;support /PM /PS /SM /SS option
SETMODE     equ 1       ;support /M option, set UDMA mode
SETVD       equ 1       ;support /P option to set IDE vendor/device ID
SETBM       equ 1       ;test Busmaster support in "class"
MWDMA       equ 1       ;support /W option to accept multi-word DMA
DWRDIO      equ 1       ;support /32 option (PIO DWORD IO)

VER     equ <'V1.5, 18.08.2022'>    ;Driver version number and date.
MSELECT equ 0A0h        ;"Master" device-select bits.
SSELECT equ 0B0h        ;"Slave"  device-select bits.
COOKSL  equ 2048        ;CD-ROM "cooked" sector length.
RAWSL   equ 2352        ;CD-ROM "raw" sector length.
CMDTO   equ 00Ah        ;500-msec minimum command timeout.
SEEKTO  equ 025h        ;2-second minimum "seek"  timeout.
STARTTO equ 049h        ;4-second minimum startup timeout.
BIOSTMR equ 0046Ch      ;BIOS "tick" timer address.
;VDSFLAG equ    0047Bh      ;BIOS "Virtual DMA" flag address.
IXM     equ 2048        ;IOCTL transfer-length multiplier.
CR      equ 00Dh        ;ASCII carriage-return.
LF      equ 00Ah        ;ASCII line-feed.
TAB     equ 009h        ;ASCII "tab".

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

;
; DOS "Request Packet" Layout.
;
RP      struc
RPHLen  db  ?       ;+0 Header byte count.
RPSubU  db  ?       ;+1 Subunit number.
RPOp    db  ?       ;+2 Command code.
RPStat  dw  ?       ;+3 Status field.
        db 8 dup (?);(Unused by us).
RPUnit  db  ?       ;+12 Number of units found.
RPSize  dw  ?       ;+14 Resident driver offset
        dw  ?
RPCL    dd  ?       ;Command-line data pointer.
RP      ends

RPERR   equ 08003h      ;Packet "error" flags.
RPDON   equ 00100h      ;Packet "done" flag.
RPBUSY  equ 00200h      ;Packet "busy" flag.
;
; IOCTL "Request Packet" Layout.
;
IOC struc
        db  13  dup (?) ;Request "header" (unused by us).
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
        db  13  dup (?) ;Request "header" (unused by us).
RLAM    db  ?       ;Addressing mode.
RLAddr  dd  ?       ;Data-transfer address.
RLSC    dw  ?       ;Data-transfer sector count.
RLSec   dd  ?       ;Starting sector number.
RLDM    db  ?       ;Data-transfer mode.
RLIntlv db  ?       ;Interleave size.
RLISkip db  ?       ;Interleave skip factor.
RL  ends

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
;dwAudSta    dd ?    ;Current audio-start address.
;            dd ?    ;Current audio-end   address.
;            dd ?    ;Last-session starting LBA.
UPARM ends

REQOFS   equ 16h

    .data

pRequest    dd 0    ;linear address where request header is stored
dwRequest   dd 0    ;linear address request header
dwBase      dd 0    ;linear address driver base
dwCmdLine   dd 0
if SETVD
dwVD        dd 0
endif
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
if SETVD
FL_P    equ 16      ;/P option set
endif

;
; Audio Function Buffer (16 bytes) for most CD-ROM "audio" requests.
;   The variables below are used only during driver initialization.
;
InBuf   equ $
UTblP   dd  offset UnitTbl      ;Initialization unit table pointer.
IEMsg   dd  0                   ;Init error-message pointer.
MaxUM   db  -1                  ;UDMA "mode" limit set by /Mn option.
UFlag   db  0                   ;UltraDMA "mode" flags (set by Init).
UMode   db  0                   ;UltraDMA "mode" value (set by Init).
        db  0
ScanX   dd  offset ScanLPM      ;Scan table index (0FFFFh = no scan).

;
; Unit Parameter Tables.   If you want a 4th drive, simply add 1 more
;   parameter table -- NO extra code and NO other changes are needed!
;
UnitTbl label UPARM
        UPARM <-1,-1,-1,0,-1,<-1,-1,-1>>
        UPARM <-1,-1,-1,0,-1,<-1,-1,-1>>
        UPARM <-1,-1,-1,0,-1,<-1,-1,-1>>
UTblEnd equ $       ;(End of all unit tables).
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
        dd  ReqDS       ;06 -- Device status.
        dd  ReqSS       ;07 -- Sector size.
@RqVS   dd  ReqVS       ;08 -- Volume size.
        dd  ReqMCS      ;09 -- Media-change status.
@RqADI  dd  ReqADI      ;10 -- Audio disk info.
@RqATI  dd  ReqATI      ;11 -- Audio track info.
@RqAQI  dd  ReqAQI      ;12 -- Audio Q-channel info.
        dd  UnSupp      ;13 -- Subchannel info  (unused).
        dd  UnSupp      ;14 -- Read UPC code    (unused).
@RqASI  dd  ReqASI      ;15 -- Audio status info.
DspLmt3 equ ( $ - offset DspTblC)/4 ;Request-code limit for this table.

;--- expected size of IOCTL input requests
        dd  5*IXM       ;0
        dd  6*IXM       ;1
        dd  0
        dd  0
        dd  0
        dd  0
        dd  5*IXM       ;6
        dd  4*IXM       ;7
        dd  5*IXM       ;8
        dd  2*IXM       ;9
        dd  7*IXM       ;10
        dd  7*IXM       ;11
        dd  11*IXM      ;12
        dd  0
        dd  0
        dd  11*IXM      ;15

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

        dd  1*IXM
        dd  2*IXM
        dd  1*IXM
        dd  0
        dd  0
        dd  1*IXM

;
; Initialization PCI Class-Code "Interface" Bytes.   The 0BAh and 0B0h
; bytes handle ALi M5529 chips.   MANY THANKS to David Muller for this
; VALUABLE addition!
;
; from RBIL, FARCALL.LST, F0087:
;Bit(s) Description (Table F0087)
; 7 bus mastering (read-only)
; 6-4   reserved (read-only)
; 3 secondary IDE mode bit is writable (read-only)
; 2 secondary IDE mode (0 = legacy, 1 = native)
; 1 primary IDE mode bit is writable (read-only)
; 0 primary IDE mode (0 = legacy, 1 = native)
;
ClCodes label byte
        db 08Ah,080h
        db 0FAh,0F0h
        db 0BAh,0B0h
        db 085h,08Fh    ;native controller
ClCEnd  equ $
;
; Initialization IDE Parameter-Value Table.
;

ScanLPM IDEPARM <1F0h,-1,0A0h>  ;legacy IDE primary master
ScanLPS IDEPARM <1F0h,-1,0B0h>  ;legacy IDE primary slave
ScanLSM IDEPARM <170h,-1,0A0h>  ;legacy IDE secondary master
ScanLSS IDEPARM <170h,-1,0B0h>  ;legacy IDE secondary slave
ScanNPM IDEPARM <  -1,-1,0A0h>  ;native IDE primary master
ScanNPS IDEPARM <  -1,-1,0B0h>  ;native IDE primary slave
ScanNSM IDEPARM <  -1,-1,0A0h>  ;native IDE secondary master
ScanNSS IDEPARM <  -1,-1,0B0h>  ;native IDE secondary slave
ScanE   equ $           ;(End of IDE parameter table).

if MWDMA
MWModes label word
    dw  0004h       ;Mode 0
    dw  0013h       ;Mode 1
    dw  0016h       ;Mode 2
endif
UModes label word
    dw  0016h       ;Mode 0, ATA-16  UDMA mode table
    dw  0025h       ;Mode 1, ATA-25
    dw  0033h       ;Mode 2, ATA-33
    dw  0044h       ;Mode 3, ATA-44  (Unusual but possible).
    dw  0066h       ;Mode 4, ATA-66
    dw  0100h       ;Mode 5, ATA-100
    dw  0133h       ;Mode 6, ATA-133
    dw  0166h       ;Mode 7, ATA-166

;  A)  All message LABELS ("XCMsg" etc.) must appear as shown.
;
;  B)  All CR, LF, and ending $ bytes must appear as shown.  Only the
;      message TEXT bytes (letters, numbers and punctuation) are open
;      to change.
;
;  C)  There must be at least 42 characters from the start of "XCMsg"
;      to the start of "Suffix", as the driver reads 40 bytes of data
;      into this area (the name of each drive) and suffixes an ending
;      $ before displaying the final CD-ROM drive name.
;
;  D)  Other messages MODIFIED by driver initialization are:
;
;   1) The 8 driver name bytes at "DvrMsg1".
;   2) The 4 controller address bytes at "CtlrAdr".
;   3) The 8 controller I.D. bytes at "CtlrID".
;   4) The drive unit-number byte at "UMsgNo".
;   5) The 2 UltraDMA mode bytes at "UDMode".
;
; For an "Internationalization" example, compare the file XDMAMSGS.ENG
; with the file XDMAMSGS.NL, both of which are included in the current
; XDMA driver package.   XDMAMSGS.NL translates all XDMA init messages
; into the Dutch language.   This file was written by Bernd Blaauw who
; suggested making XDMA, and now XCDROM, into "International" drivers.
;
;
XCMsg   db  'XCDROM32 '
        db  VER     ;XCDROM.ASM provides version and date!
        db  '.',CR,LF,0
DvrMsg  db  'Driver name is '
DvrMsg1 db  '        ',0
CtlrMsg db  'UltraDMA controller at IDE/DMA ports '
CtlrAdr db  'xxxx/xxxx, Chip I.D. '
CtlrID  db  'xxxxxxxxh.',CR,LF,0
LEMsg   db  '.',CR,LF,'/L Invalid',0
SyEMsg  db  '.',CR,LF,'ERROR '
Suffix  db  '; XCDROM32 not loaded!',CR,LF,0
UnitMsg db  'Unit '
UMsgNo  db  '0: ',0
TOMsg   db  ' device select timeout',0
IDMsg   db  ' Identify Device error',0
NCMsg   db  " isn't an ATAPI CD-ROM",0
SEMsg   db  ' UltraDMA Set Mode error',0
NDMsg   db  'No CD-ROM drive to use',0
if 0
PriMsg  db  'Primary-',0
SecMsg  db  'Secondary-',0
endif
MstMsg  db  'Master',0
SlvMsg  db  'Slave',0
PortMsg db  ', IDE/DMA ports '
IDEPort db  '    /'
DMAPort db  '    , ',0
UDMsg   db  ', ATA-'
UDMode  db  '   ',0
PIOMsg  db  ', PIO mode',0
CRMsg   db  '.',CR,LF,0
ifdef _DEBUG
DbgMsg1 db  "Start drive scan",CR,LF,0
DbgMsg2 db  "End drive scan",CR,LF,0
DbgMsg4 db  "Executing Identify command, IDE Controller base="
DbgMsg4_1 db "    ",CR,LF,0
DbgMsg5 db  "IDE controller ready",CR,LF,0
DbgMsg6 db  "ATAPI CDROM detected",CR,LF,0
endif

rmcode label byte
    db 2Eh, 89h, 1eh, REQOFS+0, 0    ;mov cs:[16h],bx
    db 2Eh, 8Ch, 06h, REQOFS+2, 0    ;mov cs:[18h],es
    db 0CBh                     ;retf
SIZERMCODE equ $ - offset rmcode    
    db 0EAh                     ;jmp ssss:oooo

    .code

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

    mov [esi].RP.RPStat,RPDON ;Init status to "done".
    mov al,[esi].RP.RPSubU  ;Get unit-table offset.
    mov ah,sizeof UPARM
    mul ah
    lea ebx,[eax+offset UnitTbl]    ;Set unit's audio-start address ptr.
    lea eax, [ebx+UPARM.dwAudSta]
    mov [AudAP],eax

    push [ebp].Client_Reg_Struc.Client_EFlags           ;save client flags
    or @byte [ebp].Client_Reg_Struc.Client_EFlags+1,2   ;set client's IF

    mov al,[esi].RP.RPOp    ;Get packet request code.
    mov edi,offset DspTbl1  ;Point to 1st DOS dispatch table.
    call Dspatch            ;Dispatch to desired request handler.

    pop [ebp].Client_Reg_Struc.Client_EFlags    ;restore client flags

    VMMCall Simulate_Far_Ret
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
    shr edx,11              ;Ensure correct IOCTL transfer
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
    mov [esi].RP.RPStat,ax
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
ReqSS:
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

ReqDS:
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
    jmp ReadAST         ;Go post "busy" status and exit.
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
    VMMCall Yield           ;run client's ISRs
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
    VMMCall Yield
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
    jb  TestTOX             ;No, all is well -- exit above.
ValSNE:
    pop eax                 ;Error!  Discard our exit address.
    jmp SectNF              ;Post "sector not found" and exit.
ValSN endp
;
; Subroutine to test for I-O timeouts. At entry, the CL-reg. is
;   008h to test for a data-request, also. At exit, the DX-reg.
;   points to the IDE primary-status register. The AH and ESI
;   will be lost.
;
TestTO:
    xor cl,cl           ;Check for only controller-ready.
TestTO1:
    mov ah,CMDTO        ;Use 500-msec command timeout.
TestTO2:
    mov esi,BIOSTMR
    add ah,[esi]        ;Set timeout limit in AH-reg.
@@:
    VMMCall Yield       ;preserves all registers
    cmp ah,[esi]        ;Has our I-O timed out?
    stc                 ;(If so, set carry flag).
    je  TestTOX         ;Yes?  Exit with carry flag on.
    mov dx,[ebx].UPARM.wIDEBase
    add edx,7
    in  al,dx           ;Read IDE primary status.
    test al,BSY         ;Is our controller still busy?
    jnz @B              ;Yes, loop back and test again.
    or  cl,cl           ;Are we also awaiting I-O data?
    jz  TestTOX         ;No, just exit.
    test al,cl          ;Is data-request (DRQ) also set?
    jz  @B              ;No, loop back and test again.
TestTOX:
    ret                 ;Exit -- carry indicates timeout.
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
    call ReadAST        ;Read current "audio" status.
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
    cmp @dword [esi].RL.RLSC,0  ;Is sector count zero?
    je  Swap32X                 ;Yes, just exit above.
    mov edi,[AudAP]             ;Point to audio-start addr.
    mov @byte [Packet],047h     ;Set "Play Audio" command.
    mov eax,[esi].RL.RLAddr     ;Validate starting address.
    call ValSN1
    mov [edi.AUDADR.dwAudSta],eax       ;Save audio-start address.
    call ConvMSF        ;Set MSF start address in packet.
    mov @dword [PktLBA+1],eax
    mov eax,[esi+18]    ;Get play-audio "end" address.
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
ReqVS:
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
    jmp ReadAST         ;Go post "busy" status and exit.
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
    jc  ReqErr          ;If error, post return code & exit.
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
ReadAST:
    call ZPacket        ;Status only -- reset ATAPI packet.
    mov ax,00004h       ;set SubQ=0, use 4-byte count.
RdAST1:
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
    or  @word [esi].RP.RPStat,RPBUSY  ;Set "busy" status bit.
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

if SUPPPS

;--- handle /PM /PS /SM /SS switches
;--- EDI-> IDEPARM
;--- AH=M or S

I_SetPS proc
    inc esi         ;Bump pointer past "channel" switch.
    cmp ah,'m'      ;Is following byte an "M" or "m"?
    je  I_SetHW     ;Yes, set desired hardware values.
    cmp ah,'s'      ;Is following byte an "S" or "s"?
    jne I_NxtCJ     ;No, see if byte is a terminator.
    add edi,sizeof IDEPARM      ;Point to channel "slave" values.
I_SetHW:
    inc esi         ;Bump pointer past master/slave byte.
    or  [ScanX],-1  ;Set "no scan" flag.
    xor edx,edx     ;Get this device's hardware values.
    xchg edx,@dword [edi].IDEPARM.wIDEBase
    or  edx,edx     ;Have we already used these values?
    jz  I_NxtCJ     ;Yes, IGNORE duplicate switches!
    mov edi,[UTblP] ;Get current unit-table pointer.
    cmp edi,offset UTblEnd  ;Have we already set up all units?
    je  I_NxtCJ             ;Yes, IGNORE any more switches!
    mov @dword [edi].UPARM.wIDEBase,edx    ;Set parameters in unit table.
    add [UTblP],sizeof UPARM   ;Bump to next unit table.
I_NxtCJ:
    ret
I_SetPS endp

endif

if SETVD

GetDWord proc
    push esi
    mov ch,0
    xor edx,edx
Next:
    lodsb
    and al,al
    jz gd_done
    cmp al,'0'
    jb gd_done
    cmp al,'9'
    jbe isdigit
    or al,20h
    cmp al,'a'
    jb gd_done
    cmp al,'f'
    ja gd_done
    sub al,27h
isdigit:
    sub al,'0'
    shl edx,4
    movzx eax,al
    add edx,eax
    inc ch
    jmp Next
gd_done:
    pop eax
    cmp ch,1
    jb failed
    mov eax,edx
    ret
failed:
    mov esi,eax
    ret
GetDWord endp

endif

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
    mov [@RqPlay],eax
    mov [@RqStop],eax
    mov [@RqRsum],eax
    mov [@RqCHL],eax
    mov [@RqADI],eax
    mov [@RqATI],eax
    mov [@RqAQI],eax
    mov [@RqASI],eax
    mov eax,offset DOSSeek  ;Do only LBA-address DOS seeks.
    mov [@RqPref],eax
    mov [@RqSeek],eax
    mov al,004h                     ;Have "Device Status" declare
    mov @byte ds:[@Status],al       ;  we handle DATA reads only,
    db  0B0h                        ;  and have it NOT update the
    ret                             ;  IOCTL "busy" flag & return
    mov @byte ds:[@RqDSX],al        ;  ["ReadAST" gets DISMISSED]!
    ret
I_SetAX endp

WordOut proc
    push eax
    mov al,ah
    call ByteOut
    pop eax
ByteOut:
    push eax
    shr eax,4
    call NibOut
    pop eax
NibOut:
    and al,0Fh
    cmp al,10
    sbb al,69H
    das
    stosb
    ret
WordOut endp

;
; Driver Initialization Routine.   Note that this routine runs on
;   the DOS stack.   All logic past this point becomes our local-
;   stack or is DISMISSED, after initialization is completed.
;
I_Init proc
    cld             ;Ensure FORWARD "string" commands!
    mov esi,[dwRequest] ;Point to DOS request packet.
    cmp [esi].RP.RPOp,0 ;Is this an "Init" packet?
    jnz I_BadP      ;Go post errors and exit quick!
    mov esi,[dwCmdLine] ;Point to command line that loaded us.
I_NxtC:
    lodsb           ;Get next command-line byte.
    cmp al,0        ;Is byte the command-line terminator?
    je  I_Term      ;Yes, go test for UltraDMA controller.
    cmp al,LF       ;Is byte an ASCII line-feed?
    je  I_Term      ;Yes, go test for UltraDMA controller.
    cmp al,CR       ;Is byte an ASCII carriage-return?
    je  I_Term      ;Yes, go test for UltraDMA controller.
    cmp al,'-'      ;Is byte a dash?
    je  I_NxtS      ;Yes, see what next "switch" byte is.
    cmp al,'/'      ;Is byte a slash?
    jne I_NxtC      ;No, check next command-line byte.
I_NxtS:
    mov ax,[esi]    ;Get next 2 command-line bytes.
    or  ax,2020h    ;convert to lower case
    cmp ax,'xu'     ;/UX?
    jne @F
    inc esi         ;Bump pointer past "UX" switch.
    inc esi
    or [bFlags],FL_UX
@@:
    cmp al,'f'      ;/F?
    jnz @F
    inc esi
    or [bFlags],FL_F
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
@@:
endif
    cmp al,'l'      ;/L?
    jne @F
    mov @byte [@DMALmt],009h  ;Set 640K "DMA limit" above.
    inc esi         ;Bump pointer past "limit" switch.
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
@@:
endif

if SETVD
    cmp ax,':p'     ;/P:?
    jnz @F
    inc esi
    inc esi
    call GetDWord
    jc I_NxtC
    or [bFlags],FL_P
    mov [dwVD],eax
    jmp I_NxtC
@@:
endif

if SUPPPS

    mov edi,offset ScanLPM  ;Point to primary-channel values.
    cmp al,'p'              ;Is switch byte a "P" or "p"?
    je  @F                  ;No, go see if byte is "S" or "s".
    mov edi,offset ScanLSM  ;Point to secondary-channel values.
    cmp al,'s'              ;Is switch byte an "S" or "s"?
    jne I_ChkD              ;No, check for "D" or "d".
@@:
    call I_SetPS
    jmp I_NxtC              ;Go check next command byte.
endif

I_ChkD:
    cmp al,'d'      ;Is switch byte a "D" or "d"?
    jne @F
    inc esi         ;Bump pointer past "device" switch.
    cmp ah,':'      ;Is following byte a colon?
    jne I_NxtC
    inc esi         ;Bump pointer past colon.
    call I_SetName
    jmp I_NxtC      ;Go get next command byte.
@@:
if MWDMA
    cmp al,'w'      ;/W?
    jnz @F
    or [bFlags],FL_W
    inc esi
@@:
endif
    cmp al,'q'
    jnz I_NxtC
    inc esi
    or [bFlags],FL_Q
    jmp I_NxtC
I_Term:
    mov edx,offset XCMsg    ;Display driver "title" message.
    call I_DisplaySQ
    xor edi,edi             ;UltraDMA controller check:  Request
    mov al,001h             ;  PCI BIOS I.D. (should be "PCI ").
    mov [ebp].Client_Reg_Struc.Client_EDI, 0
    call I_Int1A

    mov edi, [ebp].Client_Reg_Struc.Client_EDI
    mov edx, [ebp].Client_Reg_Struc.Client_EDX
    cmp edx," ICP"          ;Do we have a V2.0C or newer PCI BIOS?
    jne I_ChkNm             ;No, check for valid driver name.
    
if SETVD
    test [bFlags],FL_P
    jz @F
    mov eax,[dwVD]
    mov [ebp].Client_Reg_Struc.Client_ECX,eax
    shr eax,16
    mov [ebp].Client_Reg_Struc.Client_EDX,eax
    mov @word [ebp].Client_Reg_Struc.Client_ESI, 0  ;controller index
    mov al,002h             ;find vendor/device
    call I_Int1A
    mov esi,offset ClCEnd
    jmp testdev
@@:
endif
    mov esi,offset ClCodes  ;Point to interface byte table.
    
I_FindC:                    ;<--- next controller
    cmp esi,offset ClCEnd   ;More interface bytes to check?
    jae I_ChkNm             ;No, check for valid driver name.
    mov ecx,000010100h      ;Find class 1 storage, subclass 1 IDE.
    lodsb                   ;Use next class-code "interface" byte.
    mov cl,al
    mov al,003h             ;Inquire about an UltraDMA controller.
    mov [ebp].Client_Reg_Struc.Client_ESI, 0
    mov [ebp].Client_Reg_Struc.Client_ECX, ecx
    call I_Int1A
testdev:
    jc  I_FindC             ;Not found -- test for more I/F bytes.

if SETBM
    mov ebx,[ebp].Client_Reg_Struc.Client_EBX
    mov ax,4                ;Get low-order PCI command byte.
    call I_PCID
;--- it's strange if BM isn't set, since we REQUESTED BM API ( bit 7 )
;--- but it can be found, at least in emulators.
	bts [ebp].Client_Reg_Struc.Client_ECX, 2	;busmaster enabled?
	jc @F
	mov al, 0Bh				; enable BM
	call I_Int1A
@@:
endif

if 0;CLSBM
    mov ax,8                ;get class code
    call I_PCID
    mov edi,[ebp].Client_Reg_Struc.Client_ECX   ;save it in EDI
    shr edi,8
    test @byte [ebp].Client_Reg_Struc.Client_ECX+1,80h  ;BusMaster?
    jz I_FindC
endif

    mov ax,0                ;Get Vendor and Device I.D.
    call I_PCID
    push [ebp].Client_Reg_Struc.Client_ECX  ;save it on stack

    mov ax,16+4*4           ;Get DMA base address (register 4).
    call I_PCID

    mov eax,[ebp].Client_Reg_Struc.Client_ECX ;get our DMA controller address.
    and al,0FCh
    test edi,1              ;is it a native controller?
    jz I_Legacy
    push eax
    mov ax,16+0*4           ;Get primary channel base port
    call I_PCID
    mov eax,[ebp].Client_Reg_Struc.Client_ECX
    and al,0FCh
    mov [ScanNPM.wIDEBase], ax
    mov [ScanNPS.wIDEBase], ax
    mov ax,16+2*4           ;Get secondary channel base port
    call I_PCID
    mov eax,[ebp].Client_Reg_Struc.Client_ECX
    and al,0FCh
    mov [ScanNSM.wIDEBase], ax
    mov [ScanNSS.wIDEBase], ax
    pop eax
    mov edi, offset ScanNPM
    mov dx,[ScanNPM.wIDEBase]
    jmp I_Native
I_Legacy:
    mov edi, offset ScanLPM
    mov dx,[ScanLPM.wIDEBase]
I_Native:
    lea ecx,[eax+8]
    mov [edi+0*sizeof IDEPARM].IDEPARM.wDMABase,ax
    mov [edi+1*sizeof IDEPARM].IDEPARM.wDMABase,ax
    mov [edi+2*sizeof IDEPARM].IDEPARM.wDMABase,cx
    mov [edi+3*sizeof IDEPARM].IDEPARM.wDMABase,cx
    push eax
    mov eax, edx
    mov edi,offset CtlrAdr  ;Set IDE port in message.
    call WordOut
    pop eax
    mov edi,offset CtlrAdr+5;Set DMA port in message.
    call WordOut
    pop eax
    mov edi,offset CtlrID   ;Set Vendor & Device I.D. in message.
    call WordOut
    shr eax,16
    call WordOut
    mov edx,offset CtlrMsg  ;Display UltraDMA controller data.
    call I_DisplaySQ
    jmp I_FindC

I_ChkNm:
    mov ecx,[dwBase]
    cmp @byte [ecx+10],' '      ;Is driver "name" valid?
    jnz I_SetNm                 ;Yes, display driver name.
    mov @dword [ecx+10],"RDCX"  ;Set our default "name".
    mov @dword [ecx+10+4],"$$MO"
I_SetNm:
    mov eax,[ecx+10+0]
    mov @dword [DvrMsg1+0],eax
    mov eax,[ecx+10+4]
    mov @dword [DvrMsg1+4],eax
    mov edx,offset DvrMsg       ;Display our driver "name".
    call I_DisplaySQ
    
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
    xor eax, eax
    mov edi, eax
I_OurUC:
    mov edx,offset CRMsg        ;Display ending CR/LF message.
    call I_DisplaySQ
    
    mov eax,offset UnitTbl      ;Reset our unit-table pointer.
    mov [UTblP],eax
ifdef _DEBUG
    mov edx,offset DbgMsg1
    call I_DisplayS
endif
I_ScanU:                    ;<--- try next
    mov ebx,[UTblP]         ;Get current unit-table pointer.
    mov edi,[ScanX]         ;Get current parameters index.
    cmp edi,-1              ;Are we "scanning" for drives?
    je  @F                  ;No, get unit-table parameters.
    cmp edi,offset ScanE    ;Any more IDE units to check?
    je  I_AnyCD             ;No, check for any drives to use.
    mov ebx,edi             ;Point to IDE unit parameters.
    add edi,sizeof IDEPARM  ;Update parameter-table index.
    mov [ScanX],edi
@@:
    mov ax,[ebx].UPARM.wIDEBase;Get unit's IDE address
    cmp ax,-1               ;Not scanning & unit table "empty"?
    je  I_AnyCD             ;Yes, check for any drives to use.
    call I_ValDV            ;Validate device as an ATAPI CD-ROM.
    jnc I_AnySy             ;If no error, we can USE this drive!
    cmp [ScanX],-1          ;"Scanning" for drives?
    je  I_AnySy             ;No, must show unit & error.
ifndef _DEBUG    
    cmp @dword [IEMsg],offset SEMsg ;UltraDMA "Set-Mode" error?
    jne I_ScanU             ;No, ignore & try next unit.
endif    
I_AnySy:
    test [bFlags],FL_UX     ;Was the /UX switch given?
    je  @F                  ;No, display all drive data.
    or  @byte [ebx].UPARM.wDMABase,1   ;Post drive "DMA disabled".
@@:
    mov edx,offset UnitMsg  ;Display "Unit n:" message.
    call I_DisplaySQ
if 0
    mov edx,offset PriMsg   ;Point to "Primary" message.
    test [ebx].UPARM.wDMABase,8;Primary-channel drive?
    je  @F                  ;Yes, display "Primary" message.
    mov edx,offset SecMsg   ;Point to "Secondary" message.
@@:
    call I_DisplaySQ        ;Display our CD-ROM's IDE channel.
endif
    mov edx,offset MstMsg   ;Point to "Master" message.
    test [ebx].UPARM.bDevSel,10h   ;Is our drive a "slave"?
    jz  @F                  ;No, display "Master".
    mov edx,offset SlvMsg   ;Point to "Slave" message.
@@:
    call I_DisplaySQ        ;Display "Master" or "Slave".

    mov ax,[ebx].UPARM.wIDEBase
    mov edi,offset IDEPort
    call WordOut
    inc edi
    mov ax,[ebx].UPARM.wDMABase
    call WordOut
    mov edx,offset PortMsg
    call I_DisplaySQ        ;Display IDE/DMA ports


    cmp [IEMsg],0           ;Did any validation ERROR occur?
    jz  I_ScnVN             ;No, scan "vendor name" for data.
    mov edx,[IEMsg]         ;Get init error-message pointer.
ifdef _DEBUG
    call I_DisplaySQ
    mov edx,offset CRMsg    ;Display terminating CR/LF/$.
    call I_DisplaySQ
    jmp I_ScanU             ;ignore & try next unit.
else
    jmp I_InitE             ;Go display error message and exit.
endif    
I_ScnVN:
    mov edi,offset XCMsg+40 ;Point to CD-ROM "vendor name" end.
I_ScnV1:
    mov @byte [edi],0       ;Set message terminator after name.
    dec edi                 ;Point to previous name byte.
    cmp @byte [edi],' '     ;Is this byte a space?
    je  I_ScnV1             ;Yes, keep scanning for a non-space.
    cmp @byte [XCMsg],0     ;Is CD-ROM "name" all spaces?
    je  I_ModeM             ;Yes, no need to display it!
    mov edx,offset XCMsg    ;Display manufacturer CD-ROM "name".
    call I_DisplaySQ
I_ModeM:
    mov edx,offset PIOMsg   ;Point to "PIO mode" message.
    test @byte [ebx].UPARM.wDMABase,7  ;Will drive be using UltraDMA?
    jnz I_MsEnd             ;No, display "PIO mode" message.
    mov edx,offset UDMsg    ;Point to "ATA-xx" message.
I_MsEnd:
    call I_DisplaySQ        ;Display drive's operating "mode".
    mov edx,offset CRMsg    ;Display terminating CR/LF/$.
    call I_DisplaySQ
    mov esi,[UTblP]         ;Update all unit-table parameters.
    mov ax,[ebx].UPARM.wIDEBase
    mov cx,[ebx].UPARM.wDMABase
    mov dl,[ebx].UPARM.bDevSel
    mov [esi].UPARM.wIDEBase,ax
    mov [esi].UPARM.wDMABase,cx
    mov [esi].UPARM.bDevSel,dl
    add esi,sizeof UPARM    ;Update unit-table pointer.
    mov [UTblP],esi

;   inc @byte [Units]       ;Bump number of active units.
    mov eax, [dwBase]
    inc @byte [eax+21]      ;units

    inc @byte [UMsgNo]      ;Bump display unit number.
    cmp esi,offset UTblEnd  ;Can we install another drive?
    jb  I_ScanU             ;Yes, loop back & check for more.
I_AnyCD:
ifdef _DEBUG
    mov edx,offset DbgMsg2
    call I_DisplayS
endif
;   cmp [Units],0           ;Do we have any CD-ROM drives to use?
    mov edx, [dwBase]
    cmp @byte [edx+21],0    ;Do we have any CD-ROM drives to use?

    ja  I_ClrSt             ;Yes, success
    mov edx,offset NDMsg    ;NOT GOOD!  Point to "No CD-ROM" msg.
I_InitE:
I_DsplE:
    call I_DisplayS         ;Display desired error message.
    mov edx,offset Suffix   ;Display error message suffix.
I_Quit:
    call I_DisplayS
I_BadP:
    xor eax,eax             ;Get "null" length & error flags.
    mov dx,RPDON+RPERR
    jmp I_Exit              ;Go set "init" packet values & exit.
I_ClrSt:
    mov dx,RPDON            ;Get initialization "success" code.
    mov ax,12h+4+SIZERMCODE+5
I_Exit:
    mov esi,[dwRequest]     ;Set result values in "init" packet.
    mov [esi].RP.RPSize,ax
    mov [esi].RP.RPStat,dx
    mov [esi].RP.RPUnit,0
    mov eax, edx
    ret
I_Init endp
;
; Subroutine to "validate" an IDE unit as an ATAPI CD-ROM drive.
;
I_ValDV proc
ifdef _DEBUG
    mov edi,offset DbgMsg4_1
    mov ax,[ebx].UPARM.wIDEBase
    call WordOut
    mov edx,offset DbgMsg4
    call I_DisplayS
endif
    mov [IEMsg],0       ;Reset our error-message pointer.
    call StopDMA        ;Stop previous DMA & select drive.
    call TestTO         ;Await controller-ready (sets DX to ATA cmd port)
    mov edi,offset TOMsg;Get "select timeout" message ptr.
    jc  I_Val7          ;If timeout, go post pointer & exit.
ifdef _DEBUG
    pushfd
    pushad
    mov edx,offset DbgMsg5
    call I_DisplayS
    popad
    popfd
endif
    mov al,0A1h         ;Issue "Identify Packet Device" cmd.
    out dx,al
    call TestTO         ;Await controller-ready.
    mov edi,offset IDMsg;Get "Identify" message pointer.
    jc  I_Val7          ;If timeout, go post pointer & exit.
    test al,DRQ         ;Did we also get a data-request?
    jz  I_Val6          ;No, post "not ATAPI" ptr. & exit.
    sub edx,7           ;Point back to IDE data register.
    mov ecx,128
    sub esp,ecx
    sub esp,ecx
    mov edi,esp
    rep insw
    mov ecx,128         ;skip the last half
@@:
    in  ax,dx
    loop @B
    
    mov esi,esp
    mov edi,offset XCMsg;Point to drive "name" input buffer.
    mov cl,20           ;Read & swap words 27-46 into buffer.
    push esi
    lea esi,[esi+27*2]  ;(Manufacturer "name" of this drive).
@@:
    lodsw
    xchg al,ah
    stosw
    loop @B
    pop esi
    mov al,[esi+53*2]
    mov [UFlag],al      ;Save UltraDMA "valid" flags.
    mov dx,[esi+88*2]
    mov [UMode],dh      ;Save current UltraDMA "mode" value.
                        ;"supported" UDMA "modes" is in DL

    mov ax,[esi+0*2]    ;Get I.D. word 0, main device flags.
if MWDMA
    mov ch,[esi+63*2+1] ;copy multiword flags to CH
endif    
    add esp,128*2       ;restore ESP
    
    and ax,0DF03h       ;Mask off flags for an ATAPI CD-ROM.
    cmp ax,08500h       ;Do device flags say "ATAPI CD-ROM"?
    je  I_Val9          ;Yes, see about UltraDMA use.
I_Val6:
    mov edi,offset NCMsg;Get "not an ATAPI CD-ROM" msg. ptr.
I_Val7:
    mov [IEMsg],edi     ;Post desired error-message pointer.
    stc                 ;Set carry flag on (error!).
I_Val8:
    ret
I_Val9:
ifdef _DEBUG
    push edx
    mov edx,offset DbgMsg6
    call I_DisplayS
    pop edx
endif
    test @byte [ebx].UPARM.wDMABase,7  ;Will we be using UltraDMA?
    jnz I_Val8                      ;No, go exit above.
    test @byte [UFlag],4            ;Valid UltraDMA "mode" bits?
    jz  noudma                      ;No, jump

if SETMODE
    cmp [MaxUM],-1      ;/Mn switch used?
    jz nomopt
    movzx edx,dl        ;supported UDMA modes in EDX now
    bsr eax,edx
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
    mov edi,offset SEMsg;Get "Set Mode error" message ptr.
    jc I_Val7           ;If timeout, go post pointer & exit.
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
    mov edi,offset UDMode-1
    call WordOut
    mov byte ptr [edi-4],'-'    ;restore first byte
    clc
    ret
I_ValDV endp
;
; Subroutines to do all initialization "external" calls.
;
I_PCID:
    mov [ebp].Client_Reg_Struc.Client_EDI, eax
    mov [ebp].Client_Reg_Struc.Client_EBX, ebx
    mov al,00Ah         ;Set "PCI doubleword" request code.
I_Int1A:                ;<--- entry al = 1, 3
    mov ah,0B1h         ;PCI BIOS -- execute desired request.
    mov @word [ebp].Client_Reg_Struc.Client_EAX, ax
    VMMCall Begin_Nest_Exec
    mov eax, 1Ah
    VMMCall Exec_Int
    VMMCall End_Nest_Exec
    mov ah,@byte [ebp].Client_Reg_Struc.Client_EFlags
    sahf
    mov eax,[ebp].Client_Reg_Struc.Client_EAX
I_In1AX:
    ret

I_DisplaySQ:
    test [bFlags],FL_Q
    jnz I_In1AX

I_DisplayS proc
    push esi
    mov esi, edx
    VMMCall Begin_Nest_Exec
@@nextitem:
    lodsb
    cmp al,0
    jz  I_DisplayS_done
    mov @byte [ebp].Client_Reg_Struc.Client_EDX, al
    mov @byte [ebp].Client_Reg_Struc.Client_EAX+1, 2
    mov eax, 21h
    VMMCall Exec_Int
    jmp @@nextitem
I_DisplayS_done:
    VMMCall End_Nest_Exec
    pop esi
    ret
I_DisplayS endp

DllMain proc stdcall hModule:dword, dwReason:dword, dwRes:dword

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
        VMMCall Allocate_V86_Call_Back
        jc failed

        mov edi, dwBase
        mov @word [edi+4],0C800h    ;driver attributes
        mov @word [edi+6],REQOFS+4
        mov @word [edi+8],REQOFS+4+SIZERMCODE
        mov @word [edi+20],0

        add edi, REQOFS+4
        mov esi, offset rmcode
        mov ecx, SIZERMCODE+1
        rep movsb
        stosd

        VMMCall Get_Cur_VM_Handle

;--- set EBP to the client pointer before calling I_Init

        push ebp
        mov ebp,[ebx].cb_s.CB_Client_Pointer
        call I_Init
        pop ebp

        cmp ax,RPDON
        setz al
        movzx eax,al
;    .endif
done:
    ret
failed:
    xor eax, eax
    ret

DllMain endp

    end DllMain

