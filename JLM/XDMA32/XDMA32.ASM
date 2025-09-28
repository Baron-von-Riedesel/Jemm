;
; XDMA32.ASM  - a JLM driver for UltraDMA hard-disks
; based on XDMA v3.3 by Jack R. Ellis
; released under the GNU GPL license v2 (see GNU_GPL.TXT for details)
;
; The source is to be assembled with JWasm or Masm v6+!
;
; XDMA32 switch options are as follows:
;
; /B   Always use XMS buffer. Without this option, the XMS buffer is
;      used only if the user buffer isn't dword-aligned.
; /F   Enables "Fast UltraDMA". Data input requests that cross an
;      DMA "64K boundary" are executed using a 2-element DMA
;      "scatter/gather" list, one for data up to the boundary, and one
;      for data beyond it.
; /L   Limits DMA to "low memory" below 640K. /L is REQUIRED to use
;      UMBPCI or any similar driver whose upper-memory areas do not
;      allow DMA.    /L causes I-O requests past 640K to go through
;      the driver's buffer.
; /Mn  set/restrict UDMA mode.
; /Q   Quiet mode.
; /W   also handle non-UDMA disks which can do multiword-DMA.
;
; On exit from successful I-O requests, the AH-register is zero and the
; carry flag is reset.   If an error occurs, the carry flag is SET, and
; the AH-register has one of the following codes:
;
;   Code 08h - DMA timed out.
;        0Fh - DMA error.
;        20h - Controller busy before I-O.
;        21h - Controller busy after I-O.
;        AAh - Disk not ready before I-O.
;        ABh - Disk not ready after I-O.
;        CCh - Disk FAULT before I-O.
;        CDh - Disk FAULT after I-O.
;        E0h - Hard error at I-O end.
;        FFh - XMS memory error.

    .386
    .model flat
    option casemap:none
    option dotname
    option proc:private

    include jlm.inc

ifndef ?PCISCAN
?PCISCAN equ 1
endif

NUMDSK  equ 8           ;max HDs supported
NUMCTRL equ 4           ;max IDE controllers supported
SAVESTAT equ 1          ;save/restore client state on init
SETBM   equ 1           ;set busmaster flag in PCI status
SCATTER equ 1           ;support /F option to use DMA scatter/gather lists
                        ;if a 64 kb boundary is crossed.
IRQWND  equ 1           ;allow interrupts during memory copy
LBACHECK equ 1          ;check if disk supports LBA
MWDMA   equ 1           ;support /W option to accept multi-word DMA
SETMODE equ 1           ;support /Mn option to set UDMA mode
NOHIGHLBA equ 1         ;avoid 4 OUTs for LBA28
BUFONLY equ 1           ;support /B option
HDNUM   equ 0           ;1=rely on value at 0040:0075
;
; General Program Equations.
;
VERSION equ <' V1.5, 15-10-2022'>
RDYTO   equ 08h         ;389-msec minimum I-O timeout.
BIOSTMR equ 046Ch       ;BIOS "tick" timer address.
HDISKS  equ 0475h       ;BIOS hard-disk count address.
HDIOFS  equ 048Eh       ;BIOS flag for HD IRQ

CR      equ 00Dh        ;ASCII carriage-return.
LF      equ 00Ah        ;ASCII line-feed.

@byte   equ <byte ptr>
@word   equ <word ptr>
@dword  equ <dword ptr>
;
; Driver Return Codes.
;
DMATIMO equ 0E8h        ;DMA timeout code, 008h at exit.
DMAERR  equ 0EFh        ;DMA error   code, 00Fh at exit.
CTLRERR equ 000h        ;Ctlr. busy  code, 020h/021h at exit.
DISKERR equ 08Ah        ;Disk-busy   code, 0AAh/0ABh at exit.
FAULTED equ 0ACh        ;Disk FAULT  code, 0CCh/0CDh at exit.
HARDERR equ 0BFh        ;Hard-error  code, 0E0H at exit.
XMSERR  equ 0FFh        ;XMS memory-error code.
;
; IDE Controller Register Definitions.
;
CDATA   equ 0h          ;offset Data port.
CSECCT  equ CDATA+2     ;offset I-O sector count.
CDSEL   equ CDATA+6     ;offset Disk-select and upper LBA.
CCMD    equ CDATA+7     ;offset Command register.

CSTAT   equ CDATA+7     ;Primary status register.
;CSTAT2  equ CDATA+206h  ;Alternate status register. (legacy only)
;
; Controller Status and Command Definitions.
;
BSY     equ 080h        ;IDE controller is busy.
RDY     equ 040h        ;disk device is "ready".
FLT     equ 020h        ;IDE disk has a "fault".
DRQ     equ 008h        ;IDE data request.
ERR     equ 001h        ;IDE general error flag.

DRCMD   equ 0C8h        ;DMA read command (write is 0CAh, LBA48 commands are 025h/035h).
SETFEAT equ 0EFh        ;Set Features command.
SETM    equ 003h        ;Set Mode subcommand.

DMI     equ 004h        ;DMA interrupt occured.
DME     equ 002h        ;DMA error occurred.
;
; LBA "Disk Address Packet" Layout.
;
DAP struc
DapPL   db  ?       ;Packet length.
        db  ?       ;(Reserved).
DapSC   db  ?       ;I-O sector count.
        db  ?       ;(Reserved).
DapBuf  dd  ?       ;I-O buffer address (segment:offset).
LBA01   dw  ?       ;48-bit logical block address (LBA).
LBA25   dd  ?
LBA67   dw  ?       ; it's actually a QWORD
DAP ends
;
; DPTE "Device Parameter Table Extension" Layout
; that's the structure the lpCfg member in EDD20 points to.
;
DPTE struc
wIDEBase    dw ?    ;IDE port base
wIDEAlt     dw ?    ;alternate control port
bFlags      db ?    ;drive flags (bit 4=1 -> drive is slave)
            db ?    ;proprietary info
bIRQ        db ?    ;IRQ for drive
;--- there's some more fields...
DPTE ends

;--- structure used by Int 13h, ah=48h

EDD10 struc
cbSize  dw ?	;+0 size (26 for v1.x, 30 for v2.x, 66 for v3.0)
flags   dw ?	;+2 see below
dwCyls  dd ?	;+4 number of physical cylinders on drive
dwHeads dd ?	;+8 number of physical heads on drive
dwSecs  dd ?	;+12 number of physical sectors per track
numSecs dq ?	;+16 total number of sectors on drive
secSize	dw ?	;+24 bytes per sector
EDD10 ends

EDD20 struc
      EDD10 <>
lpCfg dd ?	;+26 EDD configuration parameters ( or -1 if invalid )
EDD20 ends

EDD30 struct
        EDD20 <>
wSig      dw ?			;+1E
bLength   db ?			;+20 length of path
          db 3 dup (?)	;    reserved        
szBus     db 4 dup (?)	;+24
szIFType  db 8 dup (?)	;+28
qwIFPath  db 8 dup (?)	;+30
szDevPath db 8 dup (?)	;+38
          db ?			;+40
bChecksum db ?			;+41
          db 8 dup (?)  ;+42
EDD30 ends

;--- bits for flags above
EDDF_DMA_BOUNDARY   equ 01h ;DMA boundary errors handled transparently
EDDF_CHS_VALUD      equ 02h ;cylinder/head/sectors-per-track information is valid
EDDF_REMOVABLE      equ 04h ;removable drive
EDDF_WRITE_VERIFY   equ 08h ;write with verify supported
EDDF_CHANGE_LINE    equ 10h ;drive has change-line support (required if drive >= 80h is removable)
EDDF_LOCKABLE       equ 20h ;drive can be locked (required if drive >= 80h is removable)
EDDF_CHS_IS_MAX     equ 40h ;CHS information set to maximum supported values, not current media
;--- 15-7	reserved (0)
;Note:	bits 4-6 are only valid if bit 2 is set


;
; DOS "Request Packet" Layout.
;
RP struc
RPHLen  db ?        ;Header byte count.
RPSubU  db ?        ;Subunit number.
RPOp    db ?        ;Opcode.
RPStat  dw ?        ;Status word.
        db 8 dup (?);(Unused by us).
RPUnit  db ?        ;Number of units found.
RPSize  dd ?        ;Resident driver size.
RPCL    dd ?        ;Command-line data pointer.
RP ends

RPERR   equ 08003h      ;Packet "error" flags.
RPDONE  equ 00100h      ;Packet "done" flag.

CStr macro text:VARARG
local sym
	.code .text$01
sym db text,0
	.code
	exitm <offset sym>
endm

@dprintf macro text,args:vararg
ifdef _DEBUG
	ifnb <args>
		invoke printf, CStr(text), args
	else
		invoke printf, CStr(text)
	endif
endif
endm

	.data

dwBase      dd 0    ;linear address driver base ( conv. memory )
dwCmdLine   dd 0
dwBufferLin dd 0    ;linear address XMS buffer
dwBufferPhy dd 0    ;physical address XMS buffer (64 kb aligned)
PrvI13      dd 0    ;old real-mode int 13 vector
XMSEntry    dd 0    ;XMS "entry" address, set by Init
XMSHdl      dd 0    ;XMS memory "handle", set by Init
wBaseSeg    dd 0    ;conventional memory segment ( supplied by loader)
PRDAd       dd 0    ;PRD 32-bit command addr. (Init set).

;--- values for bFlags

FL_Q    equ 1       ;/Q option set
if SCATTER
FL_F    equ 2       ;/F option
endif
if MWDMA
FL_W    equ 4       ;/W option
endif
FLB_BUSY equ 7      ;bit 7 is "busy" flag

bFlags  db  0       ;various flags (cmdline params, busy, ...)
if SETMODE
MaxUM   db  -1      ;UDMA "mode" limit set by /Mn option.
endif
BiosHD  db  0       ;(Number of BIOS disks, during Init).
HDCount db  0       ;(BIOS hard-disk count, during Init).

	align 4

;--- the following is written to the IDE port
;--- SecCt2/LBA2447 and SecCt/LBA0023 must be consecutive

SecCt2  db  0       ;IDE "upper" sector count.
LBA2447 db  0,0,0   ;IDE "upper" LBA48 bits 24-47.
SecCt   db  0       ;IDE "lower" sector count.
LBA0023 db  0,0,0   ;IDE "lower" LBA bits 0-23.

DSIOCmd label word
DSCmd   db  0       ;IDE disk-select, LBA28 bits 24-27.
IOCmd   db  0       ;IDE command byte.

HDUnit  db  0       ;Current BIOS unit number.

	align 4

VDSLn   dd  0           ;buffer length
VDSOf   dd  0           ;linear address of buffer

;--- values for DMA controller - must be consecutive
IOAdr   dd  0           ;DMA physical address
IOLen   dd  80000000h   ;DMA byte count and "end" flag.
if SCATTER
IOAdr2  dd  0
IOLen2  dd  80000000h
endif

IDEAd   dw  1F0h, 1F0h, 170h, 170h
if NUMDSK gt 4
        dw  NUMDSK-4 dup (-1);IDE port base
endif

IDEAlt  dw  3F6h, 3F6h, 376h, 376h
if NUMDSK gt 4
        dw  NUMDSK-4 dup (-1);IDE port base
endif

DMAAd   dw  NUMDSK dup (-1) ;DMA port base

Units   db  NUMDSK dup (-1) ;IDE "active units" table (Init set).
SelCmd  db  0E0h,0F0h,0E0h,0F0h
if NUMDSK gt 4
        db  NUMDSK-4 dup (0)
endif
CHSSec  db  NUMDSK dup (0)  ;CHS sectors/head   table (Init set).
CHSHd   db  NUMDSK dup (0)  ;CHS heads/cylinder table (Init set).

;--- stored IDE controllers (bus/dev/fn) by PCI scan
controllers dw NUMCTRL dup (-1)

;--- flags for PCI IDE controller programming interface
; 7 bus mastering (read-only)
; 6-4   reserved (read-only)
; 3 secondary IDE mode bit is writable (read-only)
; 2 secondary IDE mode (0 = legacy, 1 = native)
; 1 primary IDE mode bit is writable (read-only)
; 0 primary IDE mode (0 = legacy, 1 = native)

;
; Initialization Tables And Variables.
;

if MWDMA
MWModes label word
    dw 004       ;Mode 0
    dw 013       ;Mode 1
    dw 016       ;Mode 2
endif
UModes label word
    dw 016       ;Mode 0, ATA-16  UDMA mode table
    dw 025       ;Mode 1, ATA-25
    dw 033       ;Mode 2, ATA-33
    dw 044       ;Mode 3, ATA-44  (Unusual but possible).
    dw 066       ;Mode 4, ATA-66
    dw 100       ;Mode 5, ATA-100
    dw 133       ;Mode 6, ATA-133
    dw 166       ;Mode 7, ATA-166

	include identify.inc
;SIZENAME    equ 40
SIZENAME    equ sizeof IDENTIFY_DEVICE_DATA.ModelNumber

DNMsg   db  ', '
DName   db 26*2 dup (0)    ;the model number is actually 20 words only

	.code

	include printf.inc

;
; Driver Entry Routine.  For CHS requests, the registers contain:
;
;   AH      Request code.  We handle 002h read and 003h write.
;   AL      I-O sector count.
;   CH      Lower 8 bits of starting cylinder.
;   CL      Starting sector and upper 2 bits of cylinder.
;   DH      Starting head.
;   DL      BIOS unit number.  We handle 080h and up (hard-disks).
;   ES:BX   I-O buffer address.
;
; For LBA requests, the registers contain:
;
;   AH      Request code.  We handle 042h read and 043h write.
;   DL      BIOS unit number.  We handle 080h and up (hard-disks).
;   DS:SI   Pointer to Device Address Packet ("DAP"), described above.
;
;--- for JLMs all registers are in a client structure and EBP will
;--- point to it.

Entry:

ifdef _DEBUG
	cmp @byte [ebp].Client_Reg_Struc.Client_EAX+1, 42h
	jz @F
	cmp @byte [ebp].Client_Reg_Struc.Client_EAX+1, 43h
	jnz stdpr1
@@:
	movzx esi,@word [ebp].Client_Reg_Struc.Client_DS
	movzx ecx,@word [ebp].Client_Reg_Struc.Client_ESI
	shl esi, 4
	add esi, ecx
	@dprintf <"Entry(I13), ax=%X, dx=%X, DAP=%X, buffer=%X, sect=%X",13,10>,\
		word ptr [ebp].Client_Reg_Struc.Client_EAX,\
		word ptr [ebp].Client_Reg_Struc.Client_EDX, esi, [esi].DAP.DapBuf, dword ptr [esi].DAP.LBA01
	jmp stdpr2
stdpr1:
	@dprintf <"Entry(I13), ax=%X, dx=%X, buffer=%X:%X",13,10>,\
		word ptr [ebp].Client_Reg_Struc.Client_EAX,\
		word ptr [ebp].Client_Reg_Struc.Client_EDX,\
		word ptr [ebp].Client_Reg_Struc.Client_ES,\
		word ptr [ebp].Client_Reg_Struc.Client_EBX
stdpr2:
endif

    mov edx,[ebp].Client_Reg_Struc.Client_EDX
    mov edi,0                   ;Reset active-units table index.
@LastU  equ $-4                 ;(Last-unit index, set by Init).
NextU:
    dec edi                     ;Any more active units to check?
    js QuickX                   ;No, request NOT for us -- exit quick!
    cmp dl,[edi+Units]          ;Does request unit match our table?
    jne NextU                   ;No, see if more table entries remain.
    bts @dword [bFlags],FLB_BUSY;set "busy" flag
    jc IsBusy                   ;exit with error AH=01 if driver is busy
;	@dprintf <"Entry(I13), IDE/Alt/DMA=%X/%X/%X",13,10>, [edi*2+IDEAd], [edi*2+IDEAlt], [edi*2+DMAAd]
    mov eax,[ebp].Client_Reg_Struc.Client_EAX
    mov dl,0BEh     ;Mask out LBA and write request bits.
    and dl,ah       ; 02/03/42/43 -> 2
    cmp dl,002h     ;Is this a CHS or LBA read or write?
    jne Pass        ;No, let BIOS handle this request.
    shl ah,1        ;02/03 -> 04/06   42/43 -> 84/86
    jns ValCHS      ;No, handle CHS

    movzx ecx,@word [ebp].Client_Reg_Struc.Client_DS
    movzx esi,@word [ebp].Client_Reg_Struc.Client_ESI
    shl ecx, 4
    add esi, ecx

    movzx ebx, @word [esi].DAP.DapBuf+2
    movzx edx, @word [esi].DAP.DapBuf+0
    shl ebx, 4
    add ebx, edx
    mov edx,[esi.DAP.LBA25]         ;Get DAP LBA bits 16-47
    mov al,[esi.DAP.DapSC]          ;Get "DAP" I-O sector count.
    
    cmp [esi.DAP.DapBuf],-1         ;64-bit buffer address?
    mov si,[esi.DAP.LBA01]          ;(Get "DAP" LBA bits 0-15).
    jne ValSC                       ;No, go validate "DAP" sector count.
Pass:
    btr @dword [bFlags],FLB_BUSY    ;Reset driver "busy" flag
QuickX:
    mov eax,[PrvI13]
    mov @word [ebp].Client_Reg_Struc.Client_EIP, ax
    shr eax, 16
    mov @word [ebp].Client_Reg_Struc.Client_CS, ax
    ret
IsBusy:
    lahf            ;store Carry flag in AH
    mov al,1        ;and error code in AL
    jmp GoOut
    align 4
ValCHS:
    mov ecx,[ebp].Client_Reg_Struc.Client_ECX
    xchg eax,ecx    ;CHS -- save request code and sector count in CX

    mov si,0003Fh   ;Set SI-reg. to starting sector.
    and esi,eax
    dec esi
    shr al,6        ;Set AX-reg. to starting cylinder.
    xchg al,ah
    xchg eax,edx    ;ah=head, dx=start cyl
    mov al,[edi+CHSSec];Get disk CHS sectors/head value.
    or al,al        ;Were disk CHS values legitimate?
    jz Pass         ;No?  Let BIOS do this request!
    push eax        ;Save CHS sectors/head value.
    mul ah          ;Convert head to sectors.
    add si,ax       ;Add result to starting sector.
    pop eax         ;Reload CHS sectors/head value.
    mul [edi+CHSHd] ;Convert cylinder to sectors.
    mul dx
    add si,ax       ;Add to head/sector value.
    adc edx,0
    movzx edx, dx   ;Reset upper LBA address bits.

    xchg eax,ecx    ;restore request code and sector count in AX

    movzx ecx,@word [ebp].Client_Reg_Struc.Client_ES
    movzx ebx,@word [ebp].Client_Reg_Struc.Client_EBX
    shl ecx, 4
    add ebx, ecx    ;set linear buffer address in EBX

;--- here LBA bits in EDX:SI, linear address buffer in EBX
;--- sector count in AL, cmd in AH

ValSC:
    dec al                  ;Is sector count zero or over 128?
    js Pass                 ;Yes?  Let BIOS handle this "No-No!".
    inc eax                 ;Restore sector count
    cld                     ;Ensure FORWARD "string" commands.
    mov @word [LBA0023],si  ;Save LBA bits 0-15 and 24-47.
    mov [LBA0023+2],dl      ;Save LBA bits 16-23, to free DL-reg.
    mov [LBA2447],dh
    mov esi, edx
    shr esi, 16
    mov @word [LBA2447+1],si
    mov [VDSOf],ebx         ;Save user buffer linear address.

    or @byte [ebp].Client_Reg_Struc.Client_EFlags+1,2   ;set client IF


    shr dx,12           ;Shift out LBA bits 16-27.
    or si,dx            ;Anything in LBA bits 28-47?
    jnz LBA48           ;Yes, use LBA48 read/write command.
    xchg dh,[LBA2447]   ;LBA28 -- reload & reset bits 24-27.

    or ah,(DRCMD+1)     ;Get LBA28 read/write command + 5.
    jmp GetAdr          ;Go get IDE and LBA address bytes.
    align 4
LBA48:
    shl ah,3            ;LBA48 -- translate command 04h/84h -> 20h, 06h/86h -> 30h.
GetAdr:
    mov dl,[edi+SelCmd]
    or dl,dh            ;"Or" in LBA28 bits 24-27 (if any).
    mov dh,005h         ;Get final IDE command byte.
    xor dh,ah           ;(LBA28 = C8h/CAh, LBA48 = 25h/35h).
    mov [DSIOCmd],dx    ;Set IDE command bytes (DSCmd + IOCmd).
    mov [SecCt],al      ;Set I-O sector count.
    movzx eax,al
    shl eax,9
    mov [VDSLn],eax     ;Set buffer lengths.
    mov ecx,eax
    bts eax,31          ;Set DMA list "end" flag.
    mov [IOLen],eax

if BUFONLY
@BufPatch:
endif
    test bl,3h          ;Is user I-O buffer 32-bit aligned?
    jnz BufIO           ;No, use buffered I-O routines below.

    mov esi,ebx         ;get user buffer into ESI
if SCATTER
    test [bFlags],FL_F  ;if /F not set, check 64 kB boundary
    setz dl
else
    mov dl,1            ;check for 64 kB boundary crossing
endif
    VxDCall VDMAD_Lock_DMA_Region   ; lock region esi, size ecx, dl[0] check 64 kb crossing
    jc BufIO            ;Error -- do buffered I-O.
    mov [IOAdr], edx
;	@dprintf <"Entry(I13), lock ok, addr=%X",13,10>, edx

    cmp @word [IOAdr+2],-1  ;DMA I-O above our limit?
@DMALmt equ $-1         ;(If 640K limit, ffff is patched to 9fff by Init).
    ja BufIO            ;Yes, use buffered I-O routines below.
if SCATTER
    test [bFlags],FL_F  ;/F option set?
    jz @F
    mov eax, edx
    mov ecx,[VDSLn]     ;Get lower ending DMA address.
    dec ecx             ;(IOLen - 1 + IOAdr).
    add ax,cx           ;Would input cross a 64K boundary?
    jnc @F              ;No, set DMA flag & do transfer.
    inc ax              ;Get bytes above 64K boundary.
    cmp ax,64           ;Is this at least 64 bytes?
    jb BufIO            ;No, use buffer
    inc cx              ;Get bytes below 64K boundary.
    sub cx,ax
    cmp cx,64           ;Is this at least 64 bytes?
    jb BufIO            ;No, use buffer
    mov @word [IOLen2],ax   ;Set 2nd command-list byte count.
    movzx eax,cx        ;Set 1st command-list byte count.
    mov [IOLen],eax
    add eax,[IOAdr]     ;Set 2nd command-list address.
    mov [IOAdr2],eax
@@:
endif
    call DoDMA          ;Do direct DMA I-O with user's buffer.
Done:
    lahf
    btr @dword [bFlags],FLB_BUSY    ;Reset driver "busy" flag
GoOut:
    mov @byte [ebp].Client_Reg_Struc.Client_EAX+1, al   ;Set error code in exiting AH-reg.
    push eax
    @VMMCall Simulate_Iret
    pop eax
    and @byte [ebp].Client_Reg_Struc.Client_EFlags,not 1
    and ah,1
    or @byte [ebp].Client_Reg_Struc.Client_EFlags,ah
    ret
    align 4

BufIO:
;	@dprintf <"Entry(I13), BufIO",13,10>
    test [IOCmd],012h   ;Is this a write request?
    jnz BufOut          ;Yes, use output routine

if 0;def _DEBUG
	push edi
	mov edi, dwBufferLin
	mov ecx, VDSLn
	shr ecx, 2
	mov eax, 0f6f6f6f6h
	rep stosd
	pop edi
endif

;--- buffered read: read into DMA buffer, then copy to conv. memory

    call BufDMA     ;Input all data to driver XMS buffer.
    jc Done         ;If error, post return code & exit!
    mov ecx, [VDSLn]
    mov edi, [VDSOf]
    mov esi, [dwBufferLin]
if IRQWND
    @VMMCall MoveMemory
else
    shr ecx, 2
    rep movsd
endif
    clc
    jmp Done        ;Done -- post any return code & exit.
    align 4
;
;--- buffered write: copy conv. memory to DMA buffer, then write
;
BufOut:
    push edi       ;dont destroy EDI!
    mov ecx, [VDSLn]
    mov esi, [VDSOf]
    mov edi, [dwBufferLin]
if IRQWND
    @VMMCall MoveMemory
else
    shr ecx, 2
    rep movsd
endif
    pop edi
    call BufDMA     ;Output all data from XMS buffer.
    jmp Done        ;Done -- post any return code & exit.
_ret:
    ret

    align 4

;
; Subroutine to execute read and write commands.
; EDI=drive
; out: AL=errorcode (00=no error)
;  NC = no error
;
BufDMA:
    mov eax, [dwBufferPhy]
    mov [IOAdr],eax         ;Buffered -- set physical buffer addr.
DoDMA:
    mov dx,[edi*2+DMAAd]    ;Ensure any previous DMA is stopped!
    in al,dx                ;(On some older chipsets, if DMA is
    and al,0F6h             ;  running, reading an IDE register
    out dx,al               ;  causes the chipset to "HANG"!!).

;   mov al,[edi+SelCmd]     ;Select our desired disk.
    mov al,[DSCmd]
    mov dx,[edi*2+IDEAd]
    add edx,CDSEL
    out dx,al

    mov cx, (RDYTO shl 8) or FLT  ;Get timeout & "fault" mask.
    mov esi,BIOSTMR
    add ch,[esi]            ;Set timeout limit in CH-reg.
    call ChkRdy             ;Await controller- and disk-ready.
    jc _ret                 ;If any errors, exit!

;    mov ds:[HDIOFS],al      ;AL is 0. reset BIOS flag for HD IRQ
    mov byte ptr ds:[HDIOFS],0

    mov dx,[edi*2+DMAAd]    ;Reset DMA commands and set DMA mode.
    test [IOCmd],012h       ;Is this a write request?
    jnz @F                  ;Yes, reset DMA command register.
    in al, dx
    or al, 8                ;set "DMA read" command bit.
    out dx, al
@@:
    add edx, 2      ;Point to DMA status register.
    in al, dx       ;Reset DMA status register.
    or al, 6        ;(Done this way so we do NOT alter
    out dx, al      ;  the "DMA capable" status flags!).
    add edx, 2      ;Set PRD pointer to our DMA address.
    mov eax, [PRDAd]
    out dx, eax

    mov eax, dword ptr [SecCt2]
    mov dx,[edi*2+IDEAd]
    add edx, 2
if NOHIGHLBA
    and eax, eax
    jz skip4
endif
    mov cl,4         ;(1st 4 overlayed by 2nd 4 if LBA48!).
@@:
    out dx, al
    inc edx
    shr eax, 8
    dec cl
    jnz @B
    sub edx, 4
skip4:
    mov eax, dword ptr [SecCt]
    mov cl,4
@@:
    out dx, al
    inc edx
    shr eax, 8
    dec cl
    jnz @B

    mov al,[IOCmd]
    inc edx
    out dx, al

if 0

;--- the DRQ status bit is NOT necessarily set
;--- for DMA transfers, so this code should not run.

    mov dx,[edi*2+IDEAlt]
;	@dprintf <"DoDMA waiting for DRQ=1, esi=%X, dx=%X",13,10>, esi, dx
	jmp @F
waitdrq:
	@VMMCall Yield
@@:
    cmp ch,[esi]    ;Too long without 1st data-request?
    je DMAEnd       ;Yes?  Return carry and DMA timeout!
    in al,dx        ;Read IDE alternate status.
    and al,DRQ      ;Has 1st data-request arrived?
    jz waitdrq      ;No, loop back and check again.
endif

    mov dx, [edi*2+DMAAd]
    in al, dx       ;Set DMA Start/Stop bit (starts DMA).
    or al, 1
    out dx, al
    inc edx         ;Point to DMA status register.
    inc edx
@@:
    @VMMCall Yield
    in al,dx        ;Read DMA controller status.
    and al,DMI+DME  ;DMA interrupt or DMA error?
    jnz @F          ;Yes, halt DMA and check results.
    cmp ch,[esi]    ;Has our DMA transfer timed out?
    je @F           ; then exit loop.
    test @byte ds:[HDIOFS],80h	; interrupt occured?
    jz @B
    mov al,DMI
@@:
    dec edx         ;Point back to DMA command register.
    dec edx
    push eax        ;Save ending DMA status.
    in al,dx        ;Reset DMA Start/Stop bit.
    and al,0FEh
    out dx,al
    pop eax         ;Reload ending DMA status.
    cmp al,DMI      ;Did DMA end with only an interrupt?
    jne ErrDMA      ;No?  Go see what went wrong.
    inc edx         ;Reread DMA controller status.
    inc edx
    in al,dx
    test al,DME     ;Any "late" DMA error after DMA end?
    jnz DMAEnd      ;Yes?  Return carry and DMA error!
    inc cl          ;Check "fault" and hard-error at end.

;--- EDI=drive,ESI=BIOS timer counter, CH=max

ChkRdy:
    mov dx,[edi*2+IDEAd]  ;Read IDE primary status.
    add edx,CSTAT
    in al,dx
    test al,BSY+RDY ;Controller or disk still busy?
    jg ChkErr       ;No, go check for "fault" or error.
if 1
    @VMMCall Yield   ;yield CPU 
endif
    cmp ch,[esi]    ;Too long without becoming ready?
    jne ChkRdy      ;No, loop back and check again.
    test al,BSY     ;BAAAD News!  Did controller go ready?
    mov ax,(256*CTLRERR)+DISKERR ;(Get not-ready error codes).
    jmp WhichE      ;Go see which error code to return.
ChkErr:
    and al,cl       ;Disk "fault" or hard-error?
    jz ChkExit      ;No, all is well -- go exit below.
    test al,FLT     ;BAAAD News!  Is the disk "faulted"?
    mov ax,(256*FAULTED)+HARDERR ;(Get hardware error codes).
WhichE:
    jz EndErr       ;If "zero", use AL-reg. return code.
    mov al,ah       ;Use AH-reg. return code of this pair.
EndErr:
    add al,cl       ;Add 1 if error occurred at I-O end.
    stc             ;Set carry flag to denote "error"!
ChkExit:
    ret
ErrDMA:
    test al,DME     ;BAAAD News!  Did DMA end with error?
DMAEnd:
    mov ax,(256*DMAERR)+DMATIMO  ;(Get DMA error codes).
    jmp WhichE      ;Go see which error code to return.

;--- end of "resident" part
;--- (for a JLM, this is irrelevant)

; wait for IDE controller to become "ready"
; out: C if error occured
;--- used for cmds EC (identify), EF (set features)
;--- just the BSY+ERR flags are checked, "device ready" and DRQ are ignored!

WaitRdy proc

    mov esi,BIOSTMR         ;Point to low-memory BIOS timer.
    mov cl,RDYTO            ;Set I-O timeout limit in CL-reg.
    add cl,[esi]
@@:
    @VMMCall Yield
    cmp cl,[esi]            ;Has our command timed out?
    je Error                ;Yes, set CPU carry flag & exit.
    in al,dx                ;Get IDE controller status.
    test al,BSY             ;Controller or disk still busy?
    jnz @B                  ;Yes, loop back and check again.
    test al,ERR             ;Did command cause any errors?
    jz Exit                 ;No, exit
Error:
    stc                     ;Set carry flag (error!) and exit.
Exit:
    ret
WaitRdy endp

;
; Subroutine to "validate" an UltraDMA hard-disk.
; EDI=drive
; checks for ATA device and whether LBA + UDMA bits are set
; On error, Carry is set and ESI -> error msg
; modifies EAX, EBX, ECX, EDX, ESI, EDI
;
I_ValDisk proc
    mov dx,[edi*2+IDEAd]
    mov al,[edi+SelCmd]
    add edx,CDSEL
    out dx,al
    inc edx
    mov al,0ECh             ;Issue "Identify Device" command.
    out dx,al
    call WaitRdy
    mov esi,CStr('Identify ERROR')
    jc I_SErr
    sub edx,CCMD-CDATA      ;Point to IDE data register.
    mov edi,[dwBufferLin]
    mov ecx,256
    mov esi,edi
    rep insw

    push esi
    mov edi,offset DName
    mov cl,26               ;copy "modelnumber", 
    lea esi,[esi+27*2]
@@:
    lodsw                   ;copy ID words 27-52 to name
    xchg ah,al
    stosw
    loop @B
    pop edi

    mov esi,CStr(' is no ATA device')
    test @byte [edi+0*2+1],80h  ;ATAPI device?
    jnz I_SErr
if LBACHECK
    mov esi,CStr(' does not support LBA')
    mov al,[edi+49*2+1]
    and al,3                ;mask LBA + DMA bits
    cmp al,3
    jnz I_SErr
endif
    @dprintf <"ValDisk: disk supports DMA & LBA, 53=%X, 88=%X",13,10>, word ptr [edi+53*2], word ptr [edi+88*2]

    mov bl,[edi+53*2]       ;copy "UltraDMA valid" flag to BL
    mov bh,[edi+88*2+1]     ;copy "UltraDMA mode active" flags in BH-reg.

if 0;USECFGDPARMS
;--- if LBA sectors in config data exceeds values returned by BIOS, use them if option /E is given.
;---
	mov eax, [edi].IDENTIFY_DEVICE_DATA.UserAddressableSectors
;    mov [xxx], eax
endif

if SETMODE
    test bl,4           ;values in word at pos 88 valid?
    jz nosetm_udma
    movzx ecx,@byte [edi+88*2]  ;get valid "UltraDMA modes"
    bsr eax, ecx        ;get highest supported UDMA mode in EAX
    jz nosetm_udma      ;jump if no UDMA mode supported
    mov cl,[MaxUM]
    cmp cl,-1           ;/Mn switch used?
    jz @F
    cmp al,cl           ;AL = MIN(highest supported mode, /Mn)
    jb @F
    mov al,cl
@@:
    xor ecx,ecx
    bts ecx,eax
    cmp cl,bh           ;is this mode set already?
    jz nosetm
	jmp setm_udma

;--- check/set multi-word DMA
 if MWDMA
nosetm_udma:
	test [bFlags], FL_W
	jz nosetm
    inc edx             ;Point to IDE "features" register.
    mov al,SETM         ;Set mode-select subcode.
    out dx,al
    inc edx				;Point to IDE sector-count register.
;    mov al,[edi+63*2+1] ;get current MW mode
    movzx ax,byte ptr [edi+63*2]   ;get supported MW modes
	bsr ax, ax
	jz nosetm
	mov ch, al
    or al,020h          ; set multi-word DMA mode
    out dx,al
    add edx,5           ;Point to IDE cmd register.
    mov al,SETFEAT      ;Issue "set features" command.
    out dx,al
    call WaitRdy        ;Await controller-ready.
    mov esi,CStr(' MW-DMA mode set failed')
    jc I_SErr
	mov bh,0
	jmp I_MWYes
 endif
;--- v1.4: if any UDMA mode is active and no /M option given,
;--- don't modify mode.
setm_udma:
	cmp bh, 0
	jz @F
	cmp [MaxUM],-1
	jz nosetm
@@:
    @dprintf <"ValDisk: setting UDMA mode",13,10>

    mov bh,cl           ;save it in BH for later
    push eax
    inc edx             ;Point to IDE "features" register.
    mov al,SETM         ;Set mode-select subcode.
    out dx,al
    inc edx             ;Point to IDE sector-count register.
    pop eax
    or al,040h
setumw:
    out dx,al
    add edx,5           ;Point to IDE cmd register.
    mov al,SETFEAT      ;Issue "set features" command.
    out dx,al
    call WaitRdy        ;Await controller-ready.
    mov esi,CStr(' UDMA mode set failed')
    jc I_SErr
    @dprintf <"ValDisk: UDMA mode set successful",13,10>
nosetm:
 ife MWDMA
nosetm_udma:
 endif
endif

    mov esi,CStr(' is not UltraDMA')
if 0;MWDMA
    test [bFlags],FL_W      ;handle multiword DMA devices?
    jz @F 
    mov ch,[edi+63*2+1]     ;copy multiword flags to AH
    and ch,ch               ;is a MW-DMA mode set?
    jz I_MWYes
    mov bh,0
    jmp I_MWYes
@@:
endif
    test bl,04h             ;UltraDMA bit set?
    jz I_SErr
    or bh,bh                ;any UltraDMA mode set?
    jz I_SErr               ;No?  Exit & display message!
I_MWYes:

if MWDMA
    mov eax,offset UModes   ;Point to UltraDMA mode table.
    and bh,bh
    jnz @F
    mov bh, ch
    mov eax,offset MWModes  ;Point to MW-DMA mode table
@@:
    mov edi, eax
else
    mov edi,offset UModes   ;Point to UltraDMA mode table.
endif
I_NxtM:
    shr bh,1                ;More UltraDMA modes to check?
    jz I_GotM
    inc edi                 ;Point to next mode table value.
    inc edi
    inc ecx                 ;Get next UltraDMA mode number.
    jmp I_NxtM
I_GotM:
    test [bFlags],FL_Q
    jnz I_Exit
    mov ebx,offset DName+SIZENAME   ;Point to end of disk name.
@@:
    cmp ebx,offset DName    ;Are we at the disk-name start?
    je @F                   ;Yes, disk name is all spaces!
    dec ebx                 ;Decrement disk name pointer.
    cmp @byte [ebx],' '     ;Is this name byte a space?
    je @B                   ;No, continue scan for non-space.
    inc ebx                 ;Skip non-space character.
@@:
	mov byte ptr [ebx], 0
	mov ax,[edi]            ;Get disk "mode" value.
	invoke printf, CStr("%s, ATA-%u",13,10), ebx, ax
    clc
I_Exit:
    ret
I_SErr:
    stc
    ret
    align 4

I_ValDisk endp

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

;--- get DMA controller port for a HD.
;--- for a "native" controller, IDE port bases are in registers 0-3:
;--- 0+1=primary base+alternate, 2+3=secondary base+alternate
;--- in: BX=bus/device/func
;---     EDI=drive#
;---     [edi][IDEAd]=IDE port
;--- out: CX=DMA port

I_GetDMAPort proc uses esi

	movzx ebx, bx
	shl ebx, 8
	bts ebx, 31

;--- v1.5: ensure that Busmaster flag is set in command register
if SETBM
	mov eax, ebx
	mov al, 4               ;read command register (byte)
	call getpci
	bts eax, 2              ;busmaster set?
	jc @F
	mov ecx, eax
	mov eax, ebx
	mov al, 4
	call setpci
@@:
endif
	mov eax, ebx
	mov al,16+4*4           ;Get PCI DMA base address (register 4).
	call getpci
	mov ecx, eax
	and cl, 0fch

	mov eax, ebx
	mov al, 8               ;get class code
	call getpci
	shr eax, 8
	or esi, 1111b
	cmp ah, 6               ;SATA controller? then no "legacy" bits
	jz @F
	mov esi, eax
@@:
	mov eax, 1F0h
	bt esi, 0               ;primary native?
	jnc @F
	mov eax, ebx
	mov al,16+0*4           ;Get primary IDE base address
	call getpci
	and al, 0fch
@@:
	@dprintf <"GetPorts: cmp pri base=%X-%X",13,10>, eax, word ptr [edi*2+IDEAd]
	cmp ax,[edi*2+IDEAd]
	jz found
	mov eax, 170h
	bt esi, 2               ;secondary native?
	jnc @F
	mov eax, ebx
	mov al,16+2*4           ;Get secondary IDE base address
	call getpci
	and al, 0fch
@@:
	@dprintf <"GetPorts: cmp sec base=%X-%X",13,10>, eax, word ptr [edi*2+IDEAd]
	cmp ax,[edi*2+IDEAd]
	stc
	jnz exit 
	add ecx, 8
found:
	@dprintf <"GetPorts: DMA=%X",13,10>, ecx
	clc
exit:
	ret
	align 4
I_GetDMAPort endp

;--- get Ultra-DMA port for EDD 2.0 (or 3.0 if no BIOS disk has been found)
;--- inp: EDI=drive
;--- out: NC + DMA controller port base in CX
;--- C on errors

;--- PCI command register
;--- 0001: I/O access enabled
;--- 0002: memory access enabled
;--- 0004: BM access enabled
;--- 0008:

I_GetUDMAC proc
	mov esi, offset controllers
NextIF:
	lodsw
	cmp ax,-1
	jz error
	movzx ebx, ax
ifdef _DEBUG
	shr eax, 8
	movzx eax, al
	mov edx, ebx
	shr edx, 3
	and edx, 1Fh
	mov ecx, ebx
	and ecx, 7
	@dprintf <"GetUDMAC: check IDE controller Bus/Dev/Fn=%u/%u/%u",13,10>, eax, edx, ecx
endif
ife SETBM
	mov eax, ebx
	shl eax, 8
	bts eax, 31
	mov al, 4               ;Get PCI command + status register
	call getpci
	mov ecx, eax
	@dprintf <"GetUDMAC: cmd+status register=%X",13,10>, ecx
	and ecx,4+1             ;Mask Bus-Master and I-O Space bits.
	cmp ecx,4+1             ;Is this how our controller is set up?
	jnz @F
endif
	call I_GetDMAPort
	jnc exit
@@:
	cmp esi, offset controllers + sizeof controllers
	jb NextIF               ; go try next one.
error:
	stc
exit:
	ret
	align 4
I_GetUDMAC endp

;--- get cmdline parameters
;--- modifies ESI

I_GetParams proc
    mov esi,[dwCmdLine]
I_NxtC:
    lodsb
    cmp al,0
    je I_Term
    cmp al,LF
    je I_Term
    cmp al,CR
    je I_Term
    cmp al,'-'
    je I_NxtS
    cmp al,'/'
    jne I_NxtC      ;No, check next command-line byte.
I_NxtS:
    mov ax,[esi]
    or ax,2020h     ;convert to lower-case
    cmp al,'l'      ;/L?
    jne I_ChkQ      ;No, go see if byte is "Q" or "q".
    mov @byte [@DMALmt],009h ;Set 640K "DMA limit" above.
    inc esi         ;Point to next command-line byte.
I_ChkQ:
    cmp al,'q'      ;/Q?
    jnz @F
    or [bFlags],FL_Q
    inc esi
@@:
if SCATTER
    cmp al,'f'      ;/F?
    jnz @F
    or [bFlags],FL_F
    inc esi
@@:
endif
if MWDMA
    cmp al,'w'      ;/W?
    jnz @F
    or [bFlags],FL_W
    inc esi
@@: 
endif
if SETMODE
    cmp al,'m'      ;/M?
    jne @F
    inc esi         ;Bump pointer past "mode" switch.
    cmp ah,'7'
    ja I_NxtC
    sub ah,'0'
    jb I_NxtC
    mov [MaxUM],ah  ;Set maximum UltraDMA "mode" above.
    inc esi         ;Bump pointer past "mode" value.
@@:
endif
if BUFONLY
    cmp al,'b'      ;/B?
    jnz @F
    inc esi
BUFOFS equ offset BufIO - (offset @BufPatch + 5)
    mov @byte [@BufPatch], 0E9h
    mov @dword [@BufPatch+1], BUFOFS
    jmp I_NxtC
@@:
endif
    jmp I_NxtC      ;Continue scanning for a terminator.
I_Term:
    ret
    align 4
I_GetParams endp

;--- Init XMS
;--- on errors, set Carry and error msg in ESI

InitXMS proc
    mov ax, 4300h           ;Inquire about an XMS manager.
    push 2Fh
    call IntXX
    mov eax, [ebp].Client_Reg_Struc.Client_EAX
    cmp al,080h             ;Is an XMS manager installed?
    jne I_XErr1             ;No, display message & disable XMS.
    mov ax, 4310h           ;Get XMS manager "entry" address.
    push 2Fh
    call IntXX
    mov bx, @word [ebp].Client_Reg_Struc.Client_ES
    shl ebx, 16
    mov bx, @word [ebp].Client_Reg_Struc.Client_EBX
    mov [XMSEntry], ebx

    mov ah,009h             ;Ask XMS manager for 128K of memory.
    mov dx,128
    call I_XMS
    jnz I_XErr2              ;If error, display msg. & disable XMS.
    mov edx,[ebp].Client_Reg_Struc.Client_EDX
    mov [XMSHdl],edx        ;Save XMS buffer handle number.

    mov ah,00Ch             ;"Lock" our XMS memory.
    call I_XMS
    jnz I_XErr3             ;If error, display msg. & disable XMS.

    mov eax,[ebp].Client_Reg_Struc.Client_EDX
    shl eax,16              ;Get unaligned XMS buffer address.
    mov ax,@word [ebp].Client_Reg_Struc.Client_EBX
    add eax,65536-1         ;Find 1st 64K boundary after start.
    xor ax,ax
    mov [dwBufferPhy],eax   ;Set physical buffer address
    ret
I_XErr1:
    mov esi,CStr('No XMS manager')
    stc
    ret
I_XErr2:
    mov esi,CStr('XMS 128 kB memory allocation failed')
    stc
    ret
I_XErr3:
    mov esi,CStr('XMS lock memory error')
    stc
    ret
    align 4
InitXMS endp

;--- in: EDI=drive#
;---     CX=DMA port
;--- display current values for disk
;--- out: 
;---     DMAAd
;---     CHSHd
;---     CHSSec

I_SetDisk proc
    and cl,0FCh
    mov [edi*2+DMAAd],cx

    test [bFlags],FL_Q
    jnz I_NoDskDisp
	mov esi, CStr('Master')
	test [edi+SelCmd],10h   ;Is this disk the master?
	jz @F                   ;Yes, display "master" name.
	mov esi, CStr('Slave')
@@:
	invoke printf, CStr("HD %u, %s, ATA/DMA ports %X/%X"), edi, esi, [edi*2][IDEAd], [edi*2][DMAAd]

I_NoDskDisp:

    mov ah,08h              ;Get BIOS CHS values for this disk.
    call Int13
    jc  I_CHSE              ;If BIOS error, zero sectors/head.
    mov ecx,[ebp].Client_Reg_Struc.Client_ECX
    mov edx,[ebp].Client_Reg_Struc.Client_EDX
    @dprintf <"SetDisk: int 13, ax=8 ok, cx=%X dx=%X",13,10>, cx, dx
    and ecx,03Fh            ;Get sectors/head value (low 6 bits).
    inc dh                  ;Get heads/cylinder (BIOS value + 1).
    jnz I_SetC              ;If non-zero, save disk's CHS values.
I_CHSE:
    xor cl,cl               ;CHS error!  Zero disk's sectors/head.
I_SetC:
    mov [edi+CHSHd],dh      ;Save disk's CHS values in our tables.
    mov [edi+CHSSec],cl
    push edi
    call I_ValDisk
    pop edi
    jc I_ErrD               ;If any errors, DELETE this disk!
    cmp [edi+CHSSec],0      ;Were disk's CHS values legitimate?
    jne exit                ;Yes, check for more disks to use.
    mov esi,CStr("** BIOS must do above disk's CHS I-O")
I_ErrD:
    invoke printf, CStr("%s",13,10), esi ;Display error for this disk.
    stc
exit:
    ret
I_SetDisk endp

;
; initialization
;
InitXDMA proc
    cld
    @dprintf <"InitXDMA entry, eflags=%X",13,10>, [ebp].Client_Reg_Struc.Client_EFlags
    call I_GetParams        ;get cmdline params
	test [bFlags],FL_Q
	jnz @F
	invoke printf, CStr("XDMA32",VERSION,CR,LF)
@@:
    mov [ebp].Client_Reg_Struc.Client_EDI, 0    ;Get PCI BIOS "I.D." code.
    mov ax, 0B101h
    push 1ah
    call IntXX
    mov edx, [ebp].Client_Reg_Struc.Client_EDX
    mov esi,CStr('PCI BIOS Invalid')
    cmp edx," ICP"          ;Is PCI BIOS V2.0C or newer?
    jne I_Err               ;Go display error message and exit.

    @dprintf <"PCI BIOS detected",13,10>

;--- get all PCI IDE controllers
;--- todo: also get SATA controllers with AHCI disabled.

	mov esi, 80000008h
	mov edi, offset controllers
nextctrl:
	mov eax, esi
	call getpci
	shr eax, 8
	and al, 80h
	cmp eax, 10180h
	jnz @F
	mov eax, esi
	shr eax, 8
	stosw
ifdef _DEBUG
	movzx eax, ax
	mov ecx, eax
	shr ecx, 3
	and ecx, 1Fh
	mov edx, eax
	and edx, 7
	shr eax, 8
	@dprintf <"PCI IDE controller found at %u/%u/%u",13,10>, eax, ecx, edx
endif
	cmp edi, offset controllers + sizeof controllers
	jnc donectrl
@@:
	@VMMCall Yield
	add esi, 100h
	cmp esi, 81000008h
	jb nextctrl
donectrl:

    mov ax,03513h           ;Get and save current Int 13h vector.
    push 21h
    call IntXX
    mov bx, @word [ebp].Client_Reg_Struc.Client_ES
    shl ebx, 16
    mov bx, @word [ebp].Client_Reg_Struc.Client_EBX
    mov [PrvI13], ebx

    call InitXMS            ;init XMS
    jc I_Err

    @dprintf <"XMS allocated",13,10>

    push 0
    push 16
    push PR_SYSTEM
    @VMMCall _PageReserve    ;allocate a 64 kB block of address space
    add esp,3*4
    mov esi,CStr('No address space for buffer')
    cmp eax,-1
    jz I_Err
    mov dwBufferLin, eax
    shr eax, 12             ;convert linear address to page number

    @dprintf <"Init: Buffer Address Space allocated",13,10>

    push PC_INCR or PC_WRITEABLE
    mov edx, [dwBufferPhy]
    shr edx, 12
    push edx
    push 16
    push eax
    @VMMCall _PageCommitPhys ;backup address space with XMS memory
    add esp,4*4

    @dprintf <"Init: Buffer committed",13,10>

;    mov ecx,offset Entry - offset startcode
;    mov esi,offset startcode
    mov ecx,4*4             ; max 16 byte
    mov esi,offset IOAdr
    xor edx, edx
    VxDCall VDMAD_Lock_DMA_Region
;    add [PRDAd],edx         ;Set relocated 32-bit PRD address.
    mov [PRDAd], edx        ;Set relocated 32-bit PRD address.
    @dprintf <"Init: DMA PRD address=%X",13,10>, edx

if HDNUM
    mov al,ds:[HDISKS]      ;Did BIOS find any hard-disks?
else
    mov [HDUnit],80h        ;set hard-disk unit number
    mov ah,08h              ;get info
    call Int13              ;AX,BX,DL set in Int13
    jc I_None
    mov eax,[ebp].Client_Reg_Struc.Client_EDX
endif
    cmp al,0
    jz I_None               ;No?  Display "No disk" and exit!
    mov [BiosHD],al         ;Save BIOS hard-disk count.

    @dprintf <"Int13 disk scan:",13,10>

;--- scan the HDs, max 2 times
;--- first with int 13h calls (ah=41h)
;--- if none found, try with int 1ah ("PCI disk scan").

    mov [HDUnit],80h        ;Reset hard-disk unit number
    mov al,[BiosHD]         ;Reset remaining hard-disk count.
    mov [HDCount],al
    xor edi,edi             ;Init unit table index
NextDev:
    mov ah, 41h             ;Get EDD "extensions" for this disk.
    mov bx, 55AAh
    call Int13
    jc I_SkipDrv            ;If none, ignore disk & check for more.
    @dprintf <"Int 13h, ah=41h ok, ax=%X bx=%X cx=%X",13,10>, word ptr [ebp].Client_Reg_Struc.Client_EAX, word ptr [ebp].Client_Reg_Struc.Client_EBX, word ptr [ebp].Client_Reg_Struc.Client_ECX 

;--- in AH EDD version is returned, ah=30 for version EDD 3.0

    mov ebx,[ebp].Client_Reg_Struc.Client_EBX
    mov ecx,[ebp].Client_Reg_Struc.Client_ECX
    cmp bx,0AA55h           ;Did BIOS "reverse" our entry code?
    jne I_SkipDrv           ;No, ignore this disk & check for more.

;--- v1.4: checking bit 2 is not reliable, so checking bit 0 may be sufficient

    test cl,101b            ;Does this disk have "EDD" extensions?
    jz I_SkipDrv            ;No, ignore this disk & check for more.

    mov eax,[wBaseSeg]
    mov @word [ebp].Client_Reg_Struc.Client_DS, ax
    mov eax, 20h            ;don't touch the first 32 bytes
    mov [ebp].Client_Reg_Struc.Client_ESI, eax
    mov esi, [dwBase]
    add esi, eax
    mov eax,[ebp].Client_Reg_Struc.Client_EAX
    mov @dword [esi].EDD20.cbSize, sizeof EDD30  ;set size and clear flags
    mov [esi].EDD20.lpCfg, -1
    cmp ah, 30h
    jnc @F
    mov [esi].EDD20.cbSize, sizeof EDD20
@@:

;--- call int 13h, ah=48h: Get this disk's "EDD" parameters.
;--- v86 DS:SI=EDD, has been set above to wBaseSeg:0020h

    mov ah, 48h
    call Int13
    jc I_ErED               ;Error?  Display msg. & ignore!
    @dprintf <"Int 13h, ah=48h ok, ax=%X, size EDD=%X, DPTE=%X",13,10>, word ptr [ebp].Client_Reg_Struc.Client_EAX, [esi].EDD20.cbSize, [esi].EDD20.lpCfg
    cmp [esi].EDD10.cbSize, sizeof EDD20   ;is it at least EDD20?
    jb I_SkipDrv             ;No, ignore disk & check more.
    movzx ecx, @word [esi].EDD20.lpCfg+0
    movzx edx, @word [esi].EDD20.lpCfg+2
    shl edx, 4
    add edx, ecx            ;EDX=this disk's "DPTE" pointer.
    cmp [esi].EDD10.cbSize, sizeof EDD30   ;EDD 3.0?
    jnc I_IsEDD30
    cmp [esi].EDD20.lpCfg,-1;Valid "DPTE" pointer?
    je I_SkipDrv            ;No, ignore disk & check more.
    mov ebx,15              ;Calculate "DPTE" checksum.
    xor ecx,ecx
@@:
    add cl,[ebx+edx]
    dec ebx
    jns @B
    jecxz I_IsEDD20         ;If checksum O.K., use parameters.
I_ErED:
    invoke printf, CStr('EDD BIOS error!  Unit ignored',CR,LF)
    jmp I_SkipDrv

I_IsEDD20:
    @dprintf <"drive is EDD20, Port=%X, Stat=%X, flgs=%X",13,10>, [edx].DPTE.wIDEBase, [edx].DPTE.wIDEAlt, word ptr [edx].DPTE.bFlags
    mov ax,[edx].DPTE.wIDEBase  ;Get disk's IDE base address.
    and ax,ax
    jz I_ErED
    mov cx,[edx].DPTE.wIDEAlt   ;Get disk's IDE status address.
    mov bl,[edx].DPTE.bFlags
    and bl,10h              ;use the "slave" flags
    or bl,0E0h

    mov [edi*2+IDEAd],ax
    mov [edi*2+IDEAlt],cx
    mov [edi*1+SelCmd],bl

    call I_GetUDMAC
    jc I_SkipDrv
    jmp I_EDDdone

;--- BIOS/drive is EDD30
;--- edx=DPTE (if lpCfg != -1)

I_IsEDD30:
    @dprintf <"drive is EDD30, szIFType=%X",13,10>, dword ptr [esi].EDD30.szIFType
    mov eax, dword ptr [esi].EDD30.szIFType
    cmp eax ,"ATA"          ;ATA interface?
    jz @F
    cmp eax ," ATA"
    jz @F
    cmp eax ,"ATAS"                ;for SATA, check if AHCI mode is disabled!
    jnz I_SkipDrv
@@:
    mov al, [esi].EDD30.szDevPath  ;for ATA, device path contains master/slave flag
    shl al, 4
    or al,0E0h
    mov [edi*1+SelCmd],al
    mov eax, dword ptr [esi].EDD30.szBus
    and eax, 0FFFFFFh
    cmp eax ,"ASI"                 ;ISA host bus?
    jnz @F
    mov ax, word ptr [esi].EDD30.qwIFPath   ;for ISA, interface path contains IDE port base
    mov [edi*2+IDEAd],ax
    call I_GetUDMAC
    jnc I_EDDdone
    @dprintf <"GetUDMAC failed for drive",13,10>
    jmp I_SkipDrv

@@:
;--- lpCfg might be -1!
;--- if this happens, we can't distinguish primary and secondary

    cmp [esi].EDD20.lpCfg,-1    ; Valid "DPTE" pointer?
    jz I_SkipDrv
    mov ax,[edx].DPTE.wIDEBase  ; the PCI info doesn't tell if prim or secondary!
    and ax,ax
    jz I_ErED
    mov [edi*2+IDEAd],ax        ; so we need the DPTE
@@:
    mov bh, [esi].EDD30.qwIFPath   ;get interface path (Bus)
    mov bl, [esi].EDD30.qwIFPath+1 ;get interface path (Device)
    mov al, [esi].EDD30.qwIFPath+2 ;get interface path (Function)
    shl bl,3
    and al,7
    or bl,al
    call I_GetDMAPort

ifdef _DEBUG
    jnc I_EDDdone
    @dprintf <"I_GetPorts failed for drive",13,10>
    jmp I_SkipDrv
else
    jc I_SkipDrv
endif
I_EDDdone:
    call I_SetDisk
    jc I_SkipDrv
    mov al,[HDUnit]         ;Activate this disk in main driver.
    mov [edi+Units],al
    inc edi
    cmp edi,NUMDSK          ;free entry in unit table?
    je I_DiskFound
I_SkipDrv:
    inc [HDUnit]            ;Bump BIOS unit
    dec @byte [HDCount]     ;More BIOS disks to check?
    jnz NextDev             ;Yes, loop back and do next one.
    and edi,edi             ;any disk in unit table?
    jnz I_DiskFound

;--- PCI scan

if ?PCISCAN
	cmp [controllers], -1   ; any EIDE controller found?
	jz I_None               ; if no, the PCI scan is useless.

    @dprintf <'PCI disk scan:',CR,LF>
    mov [HDUnit], 80h       ;Reset hard-disk unit number
    mov al,[BiosHD]         ;Reset remaining hard-disk count.
    mov [HDCount], al
    xor edi, edi            ;Init unit table index
NextDev2:
    call I_GetUDMAC
    jc @F
    call I_SetDisk
    jc @F
    mov al,[HDUnit]         ;Activate this disk in main driver.
    mov [edi+Units],al
    inc edi
    cmp edi,NUMDSK          ;free entry in unit table?
    je I_DiskFound
@@:
    inc [HDUnit]            ;Bump BIOS unit
    dec @byte [HDCount]     ;More BIOS disks to check?
    jnz NextDev2            ;Yes, loop back and do next one.
endif
    and edi,edi             ;any disk in unit table?
    jz I_None

I_DiskFound:

    @dprintf <"Scanning done",13,10>

    mov @dword [@LastU],edi ;Post last-unit index in main driver.

    mov esi, offset Entry
    xor edx, edx
    @VMMCall Allocate_V86_Call_Back
    mov esi,CStr('No callbacks available anymore',CR,LF)
    jc I_Err
    mov @word [ebp].Client_Reg_Struc.Client_EDX, ax
    shr eax, 16
    mov @word [ebp].Client_Reg_Struc.Client_DS, ax
    mov ax,02513h
    push 21h
    call IntXX              ;"Hook" this driver into Int 13h.

    mov ax,RPDONE           ;Get initialization "success" code.
    jmp I_Exit
I_None:
    mov esi,CStr('No disk to use')
I_Err:
    mov edx,[XMSHdl]        ;Get XMS memory "handle".
    or dx,dx                ;Did we reserve XMS memory?
    jz @F                   ;No, go display error message.
    call I_ReleaseXMS       ;Get rid of our XMS buffer.
@@:
    invoke printf, CStr("%s; XDMA32 not loaded!",CR,LF), esi
    mov ax,RPDONE+RPERR
I_Exit:
    @dprintf <"Init exit",13,10>
    ret
InitXDMA endp
;
;--- free XMS memory block on errors
;
I_ReleaseXMS proc
    mov ah,00Dh     ;Error -- unlock & free XMS buffer.
    push edx
    call I_XMS
    mov ah,00Ah
    pop edx
I_ReleaseXMS endp

;--- fall thru

I_XMS proc
    mov [ebp].Client_Reg_Struc.Client_EAX, eax
    mov [ebp].Client_Reg_Struc.Client_EDX, edx
    @VMMCall Begin_Nest_Exec
    movzx edx, @word [XMSEntry+0]
    mov cx, @word [XMSEntry+2]
    @VMMCall Simulate_Far_Call
    @VMMCall Resume_Exec
    @VMMCall End_Nest_Exec
    mov eax,[ebp].Client_Reg_Struc.Client_EAX
    dec ax              ;Zero AX-reg. if success, -1 if error.
    ret
I_XMS endp

;--- call int 13h,
;--- ah=08h, DL=dsk
;--- ah=41h, DL=dsk, BX=55AAh
;--- ah=48h, DL=dsk, DS:SI->EDD1/2/3

Int13 proc
    mov @word [ebp].Client_Reg_Struc.Client_EBX, bx
    mov dl,[HDUnit] ;Set BIOS unit in DL-reg.
    mov @byte [ebp].Client_Reg_Struc.Client_EDX, dl
    push 13h
    call IntXX
    ret
Int13 endp

;--- call int 1Ah (ax=B101h)
;--- call int 21h (ah=25h/35h)    
;--- call int 2Fh (ax=4300h, 4310h)
;--- 1A, B101h: install check, in: edi=0, out: edx="PCI ", BX=version

IntXX proc
    mov @word [ebp].Client_Reg_Struc.Client_EAX, ax
    @VMMCall Begin_Nest_Exec
    mov eax, [esp+4]
    @VMMCall Exec_Int
    @VMMCall End_Nest_Exec
    mov ah,@byte [ebp].Client_Reg_Struc.Client_EFlags
    sahf
    ret 4
IntXX endp

DllMain proc stdcall public hModule:dword, dwReason:dword, dwRes:dword

    .if dwReason == 1
        mov esi, dwRes
        movzx ecx,[esi].JLCOMM.wLdrCS
        mov wBaseSeg,ecx
        shl ecx, 4
        mov dwBase, ecx
        mov eax,[esi].JLCOMM.lpCmdLine
        mov dwCmdLine, eax

;--- set EBP to the client pointer before calling InitXDMA

        push ebp
        @VMMCall Get_Cur_VM_Handle   ;get VM handle in EBX
        mov ebp,[ebx].cb_s.CB_Client_Pointer
if SAVESTAT
        sub esp, sizeof Client_Reg_Struc
        mov edi, esp
        @VMMCall Save_Client_State
endif
        push esi
        call InitXDMA
        pop esi
        test [esi].JLCOMM.wFlags, JLF_DRIVER    ;loaded as DOS device driver?
        jz @F
        mov ebx,[esi].JLCOMM.lpRequest
        mov [ebx].RP.RPStat,ax
        mov ecx, [wBaseSeg]
        mov @word [ebx].RP.RPSize+2,cx
        xor ecx, ecx
        mov @word [ebx].RP.RPSize+0,cx
@@:
        cmp ax, RPDONE
        setz al
        movzx edi, al
        @dprintf <"exit DllMain",13,10>
if SAVESTAT
        mov esi, esp
        @VMMCall Restore_Client_State
        add esp, sizeof Client_Reg_Struc
endif
        pop ebp
        mov eax, edi
    .endif
    ret

DllMain endp

    end DllMain
