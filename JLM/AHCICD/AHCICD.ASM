
;--- JLM to read CD/DVD in AHCI mode.
;--- "cooked" mode is supported only.

	.386
	.model flat
	option casemap:none
	option proc:private

	include jlm.inc

REQOFS   equ 16h
SLCOOKED equ 2048

;--- macros

CStr macro text:vararg
local sym
	.const
sym db text,0
	.code
	exitm <offset sym>
endm

@dprintf macro text,args:vararg
local sym
ifdef _DEBUG
	.const
sym db text,0
	.code
	ifnb <args>
		invoke printf, offset sym, args
	else
		invoke printf, offset sym
	endif
endif
endm

;--- structs

DOSDRV struct
		dd ?
wAttr	dw ?
ofsStr	dw ?
ofsInt	dw ?
name_	db 8 dup (?);+10
		dw ?		;+18
		db ?		;+20
bUnits	db ?
DOSDRV ends

;--- DOS "Request Packet" Layouts.

RPH struct
RPHLen  db  ?       ;+0 Header byte count.
bSubU   db  ?       ;+1 Subunit number.
bOp     db  ?       ;+2 Command code.
wStat   dw  ?       ;+3 Status field.
        db 8 dup (?);+5 .. +12 (reserved).
RPH ends

RPERR   equ 08003h      ;Packet "error" flags.
RPDON   equ 00100h      ;Packet "done" flag.
RPBUSY  equ 00200h      ;Packet "busy" flag.

;--- Init "Request Packet" Layout

RPInit struct
        RPH <>
bUnit   db  ?       ;+13 Number of units found.
dwFree  dd  ?       ;+14 return: far16 ptr first free byte behind driver
CmdLine dd  ?       ;+18 Command-line data pointer.
RPInit  ends

;--- IOCTL "Request Packet" Layout

RPIOC struct
        RPH <>
        db  ?       ;+13 Media descriptor byte (Unused by us).
dwAddr  dd  ?       ;+14 Data-transfer address.
wLength dw  ?       ;+18 Data-transfer length.
        dw  ?       ;+20 Starting sector (unused by us).
        dd  ?       ;+22 Volume I.D. pointer (unused by us).
RPIOC ends

;--- Read Long "Request Packet" Layout

RPRL struct
        RPH <>
bAMode  db  ?       ;+13 Addressing mode.
dwAddr  dd  ?       ;+14 Data-transfer address.
wSecCnt dw  ?       ;+18 Data-transfer sector count.
dwStart dd  ?       ;+20 Starting sector number.
bDMode  db  ?       ;+24 Data-transfer mode (raw/cooked).
bILSize db  ?       ;+25 Interleave size.
bILSkip db  ?       ;+26 Interleave skip factor.
RPRL  ends

;--- AHCI structures

HBA struct
dwCAP   dd ?	;+0 HBA capabilities
dwGHC   dd ?	;+4 global HBA control
dwIS    dd ?	;+8 interrupt status
dwPI    dd ?	;+12 ports implemented
HBA ends

PORT struct
dqCLB   dq ?	;+0  Command list base
dqFB    dq ?	;+8  (received) FIS base
dwIS    dd ?	;+16 interrupt status
dwIE    dd ?	;+20 interrupt enable
dwCMD   dd ?	;+24 command and status
        dd ?	;+28
dwTFD   dd ?	;+32 task file data
dwSIG   dd ?	;+36 signature
dwSSTS  dd ?	;+40 SATA status
dwSCTL  dd ?	;+44 SATA control
dwSERR  dd ?	;+48 SATA error
dwSACT  dd ?	;+52 SATA active
dwCI    dd ?	;+56 command issued
PORT ends

;--- flags dwIS field
PIS_CPDS equ 80000000h
PIS_TFES equ 40000000h
PIS_HBFS equ 20000000h
PIS_HBDS equ 10000000h
PIS_SDBS equ 00000008h	; set device bits interrupt
PIS_DSS  equ 00000004h	; DMA setup FIS interrupt
PIS_PSS  equ 00000002h	; PIO setup FIS interrupt
PIS_DHRS equ 00000001h	; device to host register FIS interrupt

;--- flags dwCMD field
PCMD_CR  equ 8000h	; RO, 1=command list DMA engine running
PCMD_FR  equ 4000h	; RO, 1=FIS Receive running
PCMD_FRE equ 0010h	; RW, 1=FIS Receive Enable
PCMD_CLO equ 0008h	; RW, 1=command list override
PCMD_POD equ 0004h	; RW, Power On Device
PCMD_SUD equ 0002h	; RW, Spin Up Device
PCMD_ST  equ 0001h	; RW, Start (HBA may process the command list)


;--- AHCI command list header

CLH struct
flags1  db ?	;+0  P[7]=Prefetchable, W[6]=Write, A[5]=ATAPI, CFL[4:0]=Command FIS Length
flags2  db ?	;+1  PMP[15:12]=Port Multiplier Port, R[11]=Reserved, C[10]=Clear Busy, B[9]=BIST, R[8]=Reset
PRDTL   dw ?	;+2  Physical Region Descriptor Table Length
PRDBC   dd ?	;+4  Physical Region Descriptor Byte Count
CTBA0   dd ?	;+8  Command Table Base Address
CTBA_U0 dd ?	;+12 Command Table Base Address Upper
CLH ends

PRDT struct
dwBase   dd ?	;+0 base
dwBaseU  dd ?	;+4 base upper
dwRsvd   dd ?	;+8 reserved
dwCnt    dd ?	;+12 cnt  
PRDT ends

;--- AHCI command table

CT struct
cfis0  dd ?
cfis1  dd ?
cfis2  dd ?
cfis3  dd ?
       org 40h	; offset ATAPI in command table
Pkt0   dd ?
Pkt1   dd ?
Pkt2   dd ?
       org 80h	; offset PRDT in command table
p0     PRDT <>
CT ends

; packet commands:
; - 003h:  request sense
; - 01Bh:  start/stop unit
; - 01Eh:  prevent/allow media removal
; - 025h:  read capacity
; - 028h:  read (cooked)
; - 02Bh:  seek
; - 042h:  read sub-channel
; - 043h:  read TOC
; - 047h:  play audio MSF
; - 04Ah:  get event status notification
; - 04Bh:  pause/resume
; - 05Ah:  mode sense
; - 0BEh:  read CD (raw)

if 0
Packet struct
PktOPC  db  0       ;+0 packet command.
        db  0       ;+1 Unused (LUN and reserved).
PktLBA  dd  0       ;+2 CD-ROM logical block address.
PktLH   db  0       ;+6 "Transfer length" (sector count).
PktLn   dw  0       ;+7 Middle- and low-order sector count.
PktRM   db  0       ;+9 Read mode ("Raw" Read Long only).
        dw  0       ;+10 Unused ATAPI "pad" bytes (required).
Packet ends
endif

	.data

ppReq       dd 0	; linear address where request header is stored
pRequest    dd 0	; linear address request header
pBase       dd 0	; linear address driver base
pDest       dd 0	; linear address destination
pHBA        dd 0	; linear address HBA
pBuff       dd 0	; linear address sector buffer
dwBuffPh    dd 0	; physical address sector buffer
dwSector    dd 0	; current sector to read

wPort   dw 6 dup (0); port offsets of max. 6 CD/DVDs
wSecCnt dw 0		; #sectors to read
bCntArg db 0		; default value for /C option
bCount  db 0		; found units (during init)
bQuiet  db 0		; /Q option
bBanner db 0		; 1=banner displayed

szMsg4  db '0 AHCI Optical Disk(s) Found',13,10,0

	.const

ERRTAB  db 12,12,2,4,12,0,15,8,8,12,12,12,12,12,12,12

rmcode label byte
	db 2Eh, 89h, 1eh, REQOFS+0, 0	;mov cs:[16h],bx
	db 2Eh, 8Ch, 06h, REQOFS+2, 0	;mov cs:[18h],es
	db 0CBh 						;retf
SIZERMCODE equ $ - offset rmcode	
	db 0EAh 						;jmp ssss:oooo

	.data?

;--- sector buffer, para aligned.
;--- perhaps better to use the VDS buffer as xcdrom32 does?

buffer db SLCOOKED+16 dup (?)

	.code

ifdef _DEBUG
	include printf.inc
endif

DevInt proc

	.const

	align 4

;--- cmds 00-0E
Vector label dword
	dd Init		; 0 Init
	dd Error3	; 1 media check (block devices)
	dd Error3	; 2 build bpb (block devices)
	dd IOCtlInp	; 3 ioctl input
	dd Error3	; 4 input
	dd Error3	; 5 nondestr. input
	dd Error3	; 6 input status (char devices)
	dd Error3	; 7 input flush (char devices)
	dd Error3	; 8 output
	dd Error3	; 9 output with verify
	dd Error3	;10 output status (char devices)
	dd Error3	;11 output flush (char devices)
	dd Error3	;12 ioctl output
	dd Exit		;13 device open
	dd Exit		;14 device close
;	dd Error3	;15 removable media (block devices)
LVECTOR equ ($ - offset Vector) / sizeof dword

;--- cmds 128-13x
Vect2 label dword
	dd ReadL	;128 CD read long
	dd Error3	;129 CD reserved
	dd Exit		;130 CD read long prefetch
;	dd Error3	;131 CD seek
;	dd Error3	;132 CD play audio
;	dd Error3	;133 CD stop audio
;	dd Error3	;134 CD write long
;	dd Error3	;135 CD write long verify
;	dd Error3	;136 CD resume audio
LVECT2 equ ($ - offset Vect2) / sizeof dword

	.code

	cld
	mov ebx, [ppReq]
	movzx eax,word ptr [ebx+0]
	movzx ebx,word ptr [ebx+2]
	shl ebx, 4
	add ebx, eax			;Point to DOS request packet.
	mov [pRequest], ebx		;linear address request header

	mov [ebx].RPH.wStat, RPDON;Init status to "done".

	mov al, [ebx].RPH.bOp

	@dprintf <'DevInt enter, Op=%X',13,10>, eax

	and al, al
	jz @F
	mov al, [bCount]
	cmp [ebx].RPH.bSubU, al
	mov ax, 8101h
	jnc ExitAX
@@:
	mov esi, offset Vector
	mov cl, LVECTOR
	movzx eax, [ebx].RPH.bOp
	and al, al
	jns @F
	mov esi, offset Vect2
	and al, 7Fh
	mov cl, LVECT2
@@:
	cmp al, cl
	jnc Error3X
	call dword ptr [esi+eax*4]
ExitAX:
	@dprintf <'DevInt exit, ax=%X',13,10>, ax
	mov ebx, [pRequest]
	mov [ebx].RPH.wStat, ax
	VMMCall Simulate_Far_Ret
	ret
Error3X:
	push ExitAX
Error3:
	mov ax, 8103h
	ret
Exit:
	mov ax, RPDON
	ret

DevInt endp

;--- IOCtl Input dispatcher

IOCtlInp proc

	.const

	align 4

;--- IOCTL input subcmds
IVect   label dword
	dd IOC_GetHdr	; 0 get device driver header address
	dd IOC_Error3	; 1 drive head location
	dd IOC_Error3	; 2 reserved
	dd IOC_Error3	; 3 error statistics
	dd IOC_Error3	; 4 audio channel info
	dd IOC_Error3	; 5 raw data bytes
	dd IOC_DevSt	; 6 device status
	dd IOC_SecSize	; 7 sector size
	dd IOC_Error3	; 8 volume size
	dd IOC_Media	; 9 media change status
;	dd IOC_Error3	;10 audio disk info
;	dd IOC_Error3	;11 audio track info
;	dd IOC_Error3	;12 audio q-channel info
;	dd IOC_Error3	;13 audio sub-channel info
;	dd IOC_Error3	;14 UPC code
;	dd IOC_Error3	;15 audio status info
LIVECT  equ ($ - offset IVect) shr 2

	.code

	movzx esi, word ptr [ebx].RPIOC.dwAddr+2
	shl esi, 4
	movzx eax, word ptr [ebx].RPIOC.dwAddr+0
	add esi, eax
	movzx eax, byte ptr [esi]
	@dprintf <'DevInt, ioctl input, buffer=%X, al=%X',13,10>, esi, eax
	cmp al, LIVECT
	jnc IOC_Error3
	jmp [eax*4][IVect]
IOC_Error3:
	mov ax, 8103h
	retn

IOC_GetHdr:
	mov eax, [pBase]
	shl eax, 12
	@dprintf <'DevInt, ioctl input, gethdr, return=%X',13,10>, eax
	mov [esi+1], eax
IOC_done:
	mov ax, RPDON
	retn

IOC_DevSt:
	mov dword ptr [esi+1], 2	;DOOR LOCK ? OPEN=1 UNLOCK=2
	jmp IOC_done

IOC_SecSize:
	mov word ptr [esi+2], SLCOOKED
	jmp IOC_done

IOCtlInp endp

IOC_Media proc
	@dprintf <'DevInt, ioctl input, media',13,10>
	xor edi, edi
	call Setup		; set EDI=command table, ebx=port offset

;--- write packet data ( 12 bytes )
;--- 0: 4A - cmd "get event status notification"
;--- 1: 01 - bit 0=1 immediate
;--- 4: 10 - notification class request, bit 4=1 is "media"
;--- 7-8: 0008 - allocation length ( hibyte first )

;--- ACMD.00: 4A,01,00,00
;--- ACMD.04: 10,00,00,00
;--- ACMD.08: 08,00,00,00
	mov [edi].CT.Pkt0, 14AH
	mov [edi].CT.Pkt1, 10H
	mov [edi].CT.Pkt2, 8

	call Req8
	and al, al
	jnz MedChg

;--- request has returned 8 bytes,
;--- 0-3: event header (0-1 event data length, hibyte first)
;--- 4-7: event data ( 0=media event [bit 0-3], 1=media status [bit 0-1])	

	mov eax, [pBuff]
	mov ax, [eax+4]

	and al, al
	jnz MedChg
	test ah, 2  ; bit 1=1 if media present
	jz MedChg
	mov byte ptr [esi+1], 1
	jmp MedEnd
MedChg:
	mov byte ptr [esi+1], 0
MedEnd:
	call Setup
	call ReqSense

	mov eax, [pBuff]
	mov al, [eax+2]

	and al, 15
	jz @F
	mov byte ptr [esi+1], 0
	cmp al, 6
	jz MedEnd
@@:
	mov ax, RPDON
	ret
IOC_Media endp

;--- read sector(s)
;--- in: ebx=RL

ReadL proc
	mov al, 3
	cmp [ebx].RPRL.bAMode, 0; High Sierra addressing mode?
	jnz ErrorAL
	cmp [ebx].RPRL.bDMode, 0; 0=cooked, 1=raw
	jnz ErrorAL

	movzx eax, word ptr [ebx].RPRL.dwAddr+0
	movzx edx, word ptr [ebx].RPRL.dwAddr+2
	shl edx, 4
	add eax, edx
	mov [pDest], eax

	mov cx, [ebx].RPRL.wSecCnt
	mov eax, [ebx].RPRL.dwStart
	mov [wSecCnt], cx
	mov [dwSector], eax
	@dprintf <'DevInt, readl, start=%X, sectors=%X, dst=%X',13,10>, eax, cx, pDest
	xor edi, edi
ReadLP:
	cmp [wSecCnt], 0
	jz Exit
	call Setup			; set EDI=command table, ebx=port offset

;--- write packet data ( 12 bytes )
;--- 0: cmd 28 ( read )
;--- 1: flags
;--- 2-5: LBA (high byte first)
;--- 6: group no
;--- 7-8: transfer length [sector count] ( high byte first )
;--- 9: control

	mov ecx, [dwSector]
	movzx eax, cx
	shr ecx, 16
	xchg al, ah
	xchg cl, ch
	shl ecx, 16
	mov cl, 28H

;--- ACMD.00: 28h (opcode "read cooked"),00,Sector.04,Sector.03
;--- ACMD.04: Sector.02, Sector.01, group#, length.02
;--- ACMD.08: length.01,00,00,00
	mov [edi].CT.Pkt0, ecx
	mov [edi].CT.Pkt1, eax
	mov [edi].CT.Pkt2, 1

	mov ecx, 800007FFH	; PRDT.0C: FF,07,00,80  (PRC=7FF transfer 2048 bytes, 80=I)
	call ReqECX
	and al, al
	jnz readerr
	push edi
	mov ecx, SLCOOKED / sizeof dword
	mov edi, [pDest]
	mov esi, [pBuff]
	cld
	rep movsd
	pop edi
	add [pDest], SLCOOKED
	inc [dwSector]
	dec [wSecCnt]
	jmp ReadLP
readerr:
	call Setup
	call ReqSense
	and al, al
	jnz ErrorAL
	mov eax, [pBuff]
	mov al, [eax+2]
	and al, 15
	mov ebx, offset ERRTAB
	xlat
ErrorAL:
	mov ah, 81h
	@dprintf <'DevInt, readl, error, ax=%X',13,10>, ax
	ret
Exit:
	@dprintf <'DevInt, readl, ok',13,10>
	mov ax, RPDON
	ret
ReadL endp

;--- in:
;--- ebx=RP if edi==0
;--- out:
;--- ebx=port offset
;--- edi=linear address ATAPI command table

Setup proc
	cmp edi, 0			; first call?
	jnz @F
	movzx eax, byte ptr [ebx+1]
	movzx ebx, [eax*2][wPort]
	add ebx, [pHBA]

;--- get command list/table bases.
;--- those are physical addresses and hence "should" be translated to linear ones.

	mov eax, dword ptr [ebx].PORT.dqCLB	; get command list base
	mov edi, [eax].CLH.CTBA0			; get command table base address

	@dprintf <'DevInt, setup, cmdlist=%X',13,10>, eax

;--- CLH.00: 25,00,01,00 [CFL=5 dwords, A=1, PRD table length=1]
;--- CLH.04: 00,00,00,00 [PRD byte count=0]
	mov dword ptr [eax].CLH.flags1, 10025H
	mov [eax].CLH.PRDBC, 0

@@:
;--- CT.00: 27,80,A0,01 [27=H2D register FIS,80=set command register,A0=ATAPI packet command,01=Features]
;--- CT.04: 00,FF,FF,00 [LBA low,mid,high,device]
;--- CT.08: 00,00,00,00 [LBA (exp) low,mid,high,features]
;--- CT.0C: 01,00,00,00 [sector count, sector count,res,control]
	mov [edi].CT.cfis0, 1A08027H
	mov [edi].CT.cfis1, 0FFFF00H
	mov [edi].CT.cfis2, 0
	mov [edi].CT.cfis3, 1

;--- set base; must be physical address

	mov ecx, [dwBuffPh]
	mov [edi].CT.p0.dwBase, ecx
	xor ecx, ecx
	mov [edi].CT.p0.dwBaseU, ecx
	mov [edi].CT.p0.dwRsvd, ecx

	xor ecx, ecx
	mov [ebx].PORT.dwIE, ecx
	or ecx, -1
	mov [ebx].PORT.dwIS, ecx
	mov [ebx].PORT.dwSERR, ecx
	mov ecx, [ebx].PORT.dwCMD
	or cl, PCMD_FRE		; enable FIS receive
	mov [ebx].PORT.dwCMD, ecx
	or cl, PCMD_ST		; start processing command list
	mov [ebx].PORT.dwCMD, ecx
	@dprintf <'DevInt, setup, port=%X, cmdtable=%X, waiting',13,10>, ebx, edi
@@:
	mov eax, [ebx].PORT.dwCMD
	test ax, PCMD_CR	; command list running?
	jz @B
	ret
Setup endp

;--- initiate "request sense notification" cmd

ReqSense proc

;--- write packet data ( 12 bytes )
;--- 0: cmd 03 ( request sense )
;--- 1-3: reserved
;--- 4: allocation length
;--- 5: control

;--- ACMD.00: 03,00,00,00
;--- ACMD.04: 08,00,00,00
;--- ACMD.08: 00,00,00,00
	mov [edi].CT.Pkt0, 3
	mov [edi].CT.Pkt1, 8
	mov [edi].CT.Pkt2, 0

ReqSense endp

;--- fall thru!!!

;--- Req8: read 8 bytes into buffer

Req8:
	mov ecx, 80000007H	; PRDT.12: 07,00,00,80 (PRC=7; read 8 bytes, 80=I)

;--- ReqECX: 
;--- in: ecx: read ECX+1 bytes ( bit 31 = 1, indicating end of table )
;---     edi: cmd table
;---     ebx: port
;--- out: AL=0 ok, AL=12 error

ReqECX proc
	mov [edi].CT.p0.dwCnt, ecx
	mov [ebx].PORT.dwCI, 1	; bitmask, 1=slot 0 command issued
contwait:
	mov eax, [ebx].PORT.dwCI
	and eax, eax
	jz done
	mov eax, [ebx].PORT.dwIS
	test eax, PIS_TFES
	jnz error
	VMMCall Yield
	mov eax, [ebx].PORT.dwSERR
	and eax, eax
	JZ contwait
error:
	call Stop
	mov al, 12
	ret
done:
	mov eax, [ebx].PORT.dwTFD
	test al, 1
	jnz error
	call Stop
	xor eax, eax
	ret

Stop:
	mov ecx, [ebx].PORT.dwCMD
	or cl, PCMD_CLO
	and cl, 0EEH		; good idea to reset PCMD_ST and PCMD_FRE here?
	mov [ebx].PORT.dwCMD, ecx
	retn

ReqECX endp

;--- read PCI config address/data ports
;--- in: edx = addr+80000000h
;--- out: eax = value

GetPCI proc
	push edx
	mov eax, edx
	mov dx, 0cf8h
	out dx, eax
	mov dl, 0fch
	in eax, dx
	pop edx
	ret
GetPCI endp

SavePCI proc
	mov dx, 0cf8h
	in eax, dx
	mov ebx, eax
	ret
SavePCI endp

RestPCI proc
	mov dx, 0cf8h
	mov eax, ebx
	out dx, eax
	ret
RestPCI endp

if 0

;--- in: edx = addr+80000000h, eax = value

PutPCI proc
	push edx
	push eax
	mov eax, edx
	mov dx, 0cf8h
	out dx, eax
	mov dl, 0fch
	pop eax
	out dx, eax
	pop edx
	ret
PutPCI endp

endif

;--- display string EDX

dispString proc
	push esi
	mov esi, edx
	VMMCall Begin_Nest_Exec
nextitem:
	lodsb
	cmp al,0
	jz done
	mov byte ptr [ebp].Client_Reg_Struc.Client_EDX, al
	mov byte ptr [ebp].Client_Reg_Struc.Client_EAX+1, 2
	mov eax, 21h
	VMMCall Exec_Int
	jmp nextitem
done:
	VMMCall End_Nest_Exec
	pop esi
	ret
dispString endp

dispBanner proc
	cmp bQuiet, 0
	jnz @F
	cmp bBanner, 0
	jnz @F
	mov bBanner, 1
	push edx
	mov edx, CStr('AHCI Optical Disk Driver v1.2',13,10,"Inspired by Rudolph R. Loew's AHCICD",13,10)
	call dispString
	pop edx
@@:
	ret
dispBanner endp

;--- ebp: client reg struct
;--- esi: cmdline

Init proc

;--- scan cmdline args

nextchar:
	lodsb
	cmp al, ' '
	jz nextchar
	cmp al, 9
	jz nextchar
	cmp al, 13
	jz donecmdl
	cmp al, 0
	jz donecmdl
	cmp al, '/'
	jnz errcmdl
	lodsb
	mov ah, [esi]
	or al, 20h
	cmp ax, ':c'
	jz isOptC
	cmp ax, ':d'
	jz isOptD
	cmp AL, 'q'
	jz isOptQ
	jmp errcmdl

isOptD:
	inc esi
	mov edi, [pBase]
	add edi, DOSDRV.name_
	mov dword ptr [edi+0], '    '
	mov dword ptr [edi+4], '    '
	mov ecx, sizeof DOSDRV.name_
nextdevchar:
	lodsb
	cmp al, ' '
	jbe doneOptD
	cmp al, 'a'
	jb @F
	cmp al, 'z'
	ja @F
	sub al, 20H
@@:
	stosb
	loop nextdevchar
	inc esi
doneOptD:
	dec esi
	jmp nextchar
isOptC:
	inc esi
	lodsb
	cmp al, '0'
	jb errcmdl
	cmp al, '9'
	Ja errcmdl
	sub al, '0'
	mov [bCntArg], al
	jmp nextchar
isOptQ:
	mov [bQuiet], 1
	jmp nextchar

donecmdl:

;--- done cmdline processing

	call dispBanner

;--- scan for AHCI devices

	call SavePCI
	mov edx, 80000008H
nextHBA:
	call GetPCI
	mov al, 0			; clear bits 0-7 (interface doesn't matter)
	cmp eax, 1060100H	; AHCI device?
	jnz @F
	dec [bCntArg]		; /C:x argument?
	js  foundHBA
@@:
	VMMCall Yield
	add edx, 100H		; next "function"
	cmp edx, 81000008H
	jc nextHBA
	call RestPCI
	jmp errnodisk

foundHBA:
	@dprintf <'found AHCI device at PCI=%X',13,10>, edx

	mov dl, 24h			;get ABAR5
	call GetPCI
	mov edi, eax

	call RestPCI

	@dprintf <'HBA physical addr=%X',13,10>, edi

	push 0
	push 1
	push PR_SYSTEM
	VMMCall _PageReserve
	add esp, 3*4
	cmp eax, -1
	jz errpr
	mov [pHBA], eax
	mov ebx, eax

	@dprintf <'HBA mapped at linear addr=%X',13,10>, eax

	shr eax, 12		; convert linear address to page#
	shr edi, 12
	push PC_WRITEABLE
	push edi
	push 1			; map 1 page ( in theory 2 might be needed )
	push eax
	VMMCall _PageCommitPhys
	add esp, 4*4

	mov eax, [ebx].HBA.dwGHC	; get Global HBA Control
	@dprintf <'HBA.GHC=%X',13,10>, eax
	test eax, 80000000H	; AHCI enabled?
	jz errnoahci

	mov ecx, [ebx].HBA.dwPI	; get ports implemented (bit mask)
	@dprintf <'HBA.Ports=%X',13,10>, ecx

	mov edx, 100h		; port offsets are 100h, 180h, 200h, 280h, ..., 1080h
	mov edi, offset wPort
nextPort:
	shr ecx, 1
	jnc @F
	mov eax, [ebx+edx].PORT.dwSIG	; get signature
	cmp eax, 0EB140101H
	jnz @F
	@dprintf <'found ATAPI device at port=%X',13,10>, edx
	mov eax, [ebx+edx].PORT.dwSSTS	; get SATA status
	@dprintf <'device status=%X',13,10>, eax
	and al, 0FH			; bits 0-3: device detection
	cmp al, 3			; device detected and communication established?
	jnz @F
	mov eax, edx
	stosw
	cmp edi, offset wPort + sizeof wPort; table end reached?
	jz donePort
@@:
	add edx, 80H
	and ecx, ecx
	Jnz nextPort

donePort:
	sub edi, offset wPort
	shr edi, 1
	mov ecx, edi
	cmp ecx, 0
	jz errnodisk
	mov [bCount], cl

	mov esi, offset buffer+15
	and esi, not 15		; align buffer to paragraph
	mov [pBuff], esi
	mov ecx, SLCOOKED
	mov edx, 1
	VxDCall VDMAD_Lock_DMA_Region
	mov [dwBuffPh], edx
	@dprintf <'physical address sector buffer=%X',13,10>, edx

	mov ebx, [pBase]
	mov al, [bCount]
	mov [ebx].DOSDRV.bUnits, al
	cmp [bQuiet], 0
	jnz @F
	add [szMsg4], al
	mov edx, offset szMsg4
	call dispString
@@:
	mov ebx, [pRequest]
	mov word ptr [ebx].RPInit.dwFree+0, REQOFS+4+SIZERMCODE+5
	mov ax, RPDON
	mov [ebx].RPInit.wStat, ax
	mov [ebx].RPInit.bUnit, 0
	ret

errpr:
	mov edx, CStr('_PageReserve() failed',13,10)
	jmp @F
errnoahci:
	mov edx, CStr('AHCI Controller not in AHCI Mode',13,10)
	jmp @F
errcmdl:
	mov edx, CStr('SYNTAX: DEVICE=JLOAD.EXE AHCICD.DLL [/Q] /D:devname [/C:#]',13,10)
	jmp @F
errnodisk:
	MOV edx, CStr('No AHCI Optical Disk Found',13,10)
@@:
	call dispBanner
	call dispString
	mov ax, RPERR
	ret
Init endp

DllMain proc stdcall public uses esi edi hModule:dword, dwReason:dword, dwRes:dword

local pCmdLine:dword

	mov eax, dwReason
	cmp eax, 1
	jnz done

	mov esi, dwRes
	test [esi].JLCOMM.wFlags, JLF_DRIVER
	jz failed
	movzx ecx, [esi].JLCOMM.wLdrCS
	shl ecx, 4
	mov [pBase], ecx
	lea eax, [ecx+REQOFS]
	mov [ppReq], eax
	mov eax, [esi].JLCOMM.lpCmdLine
	mov [pCmdLine], eax
	mov eax, [esi].JLCOMM.lpRequest
	mov [pRequest], eax

	mov esi, offset DevInt
	xor edx, edx
	VMMCall Allocate_V86_Call_Back
	jc failed

	mov edi, [pBase]
	mov [edi].DOSDRV.wAttr, 0C800h		;driver attributes
	mov [edi].DOSDRV.ofsStr, REQOFS+4
	mov [edi].DOSDRV.ofsInt, REQOFS+4+SIZERMCODE
	mov word ptr [edi+20],0 ;clear unit?

	add edi, REQOFS+4
	mov esi, offset rmcode
	mov ecx, SIZERMCODE+1
	rep movsb
	stosd

	VMMCall Get_Cur_VM_Handle

	mov esi, [pCmdLine]

;--- set EBP to the client pointer before calling I_Init

	push ebp
	mov ebp, [ebx].cb_s.CB_Client_Pointer
	call Init
	pop ebp

	cmp ax,RPDON
	setz al
	movzx eax,al
done:
	ret
failed:
	xor eax, eax
	ret

DllMain endp

	end DllMain

