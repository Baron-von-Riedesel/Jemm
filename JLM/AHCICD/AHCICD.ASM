
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

;
; DOS "Request Packet" Layout.
;
RP      struct
RPHLen  db  ?       ;+0 Header byte count.
RPSubU  db  ?       ;+1 Subunit number.
RPOp    db  ?       ;+2 Command code.
RPStat  dw  ?       ;+3 Status field.
        db 8 dup (?);+5 .. +12 (reserved).
RPUnit  db  ?       ;+13 Number of units found.
RPSize  dd  ?       ;+14 
CmdLine dd  ?       ;+18 Command-line data pointer.
RP      ends

RPERR   equ 08003h      ;Packet "error" flags.
RPDON   equ 00100h      ;Packet "done" flag.
RPBUSY  equ 00200h      ;Packet "busy" flag.
;
; IOCTL "Request Packet" Layout.
;
IOC struct
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
RL struct
        db  13  dup (?) ;Request "header" (unused by us).
bAMode  db  ?       ;+13 Addressing mode.
dwAddr  dd  ?       ;+14 Data-transfer address.
wSecCnt dw  ?       ;+18 Data-transfer sector count.
dwStart dd  ?       ;+20 Starting sector number.
bDMode  db  ?       ;+24 Data-transfer mode (raw/cooked).
bILSize db  ?       ;+25 Interleave size.
bILSkip db  ?       ;+26 Interleave skip factor.
RL  ends

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

;--- command list header

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

;--- cmds 00-0E
VECTOR  DD      Init,ERROR3,ERROR3,IOCTLI,ERROR3,ERROR3,ERROR3,ERROR3
        DD      ERROR3,ERROR3,ERROR3,ERROR3,ERROR3,EXIT,EXIT
LVECTOR equ ($ - offset VECTOR) / sizeof dword

;--- cmds 80-82
VECT2   DD      ReadL,ERROR3,EXIT
LVECT2  equ ($ - offset VECT2) / sizeof dword

;--- IOCTL subcmds
IVEC    DD      IOC_GETHDR,ERROR3,ERROR3,ERROR3,ERROR3,ERROR3,IOC_DEVST,IOC_SECSIZ
        DD      ERROR3,IOC_MEDIA
LIVEC   equ ($ - offset IVEC) shr 2


wPort   DW 6 dup (0)	; port offsets (100h,180h,...)
wSecCnt DW 0	; #sectors to read
ERRTAB  DB 12,12,2,4,12,0,15,8,8,12,12,12,12,12,12,12
bCntArg db 1	; default value for /C option
bCount  db 0	; found units (during init)
bQuiet  db 0	; /Q option
bBanner db 0	; 1=banner displayed

MSG4    DB '0 AHCI Optical Disk(s) Found',13,10,0

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
	CLD
	mov ebx, [ppReq]
	movzx eax,word ptr [ebx+0]
	movzx ebx,word ptr [ebx+2]
	shl ebx, 4
	add ebx, eax			;Point to DOS request packet.
	mov [pRequest], ebx		;linear address request header

	mov [ebx].RP.RPStat,RPDON ;Init status to "done".

	MOV AL, [EBX].RP.RPOp

	@dprintf <'DevInt enter, Op=%X',13,10>, eax

	AND AL,AL
	JZ @F
	MOV AL,[bCount]
	CMP [EBX].RP.RPSubU,AL
	MOV AL,1
	JNC ERRORX
@@:
	MOV ESI, OFFSET VECTOR
	mov CL, LVECTOR
	MOVZX EAX, [EBX].RP.RPOp
	and al, al
	JNS @F
	MOV ESI, OFFSET VECT2
	and AL, 7Fh
	mov CL,LVECT2
@@:
	CMP AL, CL
	JNC ERROR3
	JMP DWORD PTR [ESI+EAX*4]
ERROR3::
	MOV AL,3
ERRORX::
	MOV AH,81H
	@dprintf <'DevInt exit, error=%X',13,10>, eax
	STC
	JMP EXIT1
EXIT::
	MOV AX, RPDON
	@dprintf <'DevInt exit, ok',13,10>
	CLC
EXIT1:
	mov EBX, [pRequest]
	MOV [EBX].RP.RPStat, AX
	VMMCall Simulate_Far_Ret
	RET
DevInt endp

;--- IO Ctl Input
;--- calls GETHDR, DEVST, SECSIZ, MEDIA

IOCTLI:
	movzx esi, word ptr [ebx].RP.RPSize+2
	shl esi, 4
	movzx eax, word ptr [ebx].RP.RPSize+0
	add esi, eax
	MOVzx eax, byte ptr [ESI]
	@dprintf <'DevInt, ioctl input, buffer=%X, al=%X',13,10>, esi, eax
	CMP AL,LIVEC
	JNC ERROR3
	JMP DWORD PTR [eax*4+offset IVEC]

IOC_GETHDR:
	mov eax, [pBase]
	shl eax, 12
	@dprintf <'DevInt, ioctl input, gethdr, return=%X',13,10>, eax
	MOV [ESI+1], eax
	JMP EXIT

IOC_DEVST:
	MOV DWORD PTR [ESI+1], 2	;DOOR LOCK ? OPEN=1 UNLOCK=2
	JMP EXIT

IOC_SECSIZ:
	MOV WORD PTR [ESI+2], SLCOOKED
	JMP EXIT

IOC_MEDIA proc
	@dprintf <'DevInt, ioctl input, media',13,10>
	xor edi, edi
	CALL Setup		; set EDI=command table, ebx=port offset

;--- write packet data ( 12 bytes )
;--- 0: 48 - cmd "get event status notification"
;--- 1: 01 - bit 0=1 immediate
;--- 4: 10 - notification class request, bit 4=1 is "media"
;--- 7-8: 0008 - allocation length ( hibyte first )

;--- ACMD.00: 4A,01,00,00
;--- ACMD.04: 10,00,00,00
;--- ACMD.08: 08,00,00,00
	mov [edi].CT.Pkt0, 14AH
	mov [edi].CT.Pkt1, 10H
	mov [edi].CT.Pkt2, 8

	CALL Req8
	AND AL, AL
	JNZ MEDCHG

;--- request has returned 8 bytes,
;--- 0-3: event header (0-1 event data length, hibyte first)
;--- 4-7: event data ( 0=media event [bit 0-3], 1=media status [bit 0-1])	

	mov eax, [pBuff]
	MOV AX, [eax+4]

	AND AL, AL
	JNZ MEDCHG
	TEST AH, 2  ; bit 1=1 if media present
	JZ MEDCHG
	MOV BYTE PTR [ESI+1], 1
	JMP MEDEND
MEDCHG:
	MOV BYTE PTR [ESI+1], 0
MEDEND:
	CALL Setup
	CALL ReqSense

	mov eax, [pBuff]
	MOV AL, [eax+2]

	AND AL, 15
	JZ EXIT
	MOV BYTE PTR [ESI+1], 0
	CMP AL, 6
	JZ MEDEND
	JMP EXIT
IOC_MEDIA endp

;--- read sector(s)
;--- in: ebx=RL

ReadL proc
	@dprintf <'DevInt, readl',13,10>
	CMP [EBX].RL.bAMode, 0
	JNZ ERROR3
	CMP [EBX].RL.bDMode, 0
	JNZ ERROR3

	MOVzx EAX, word ptr [EBX].RL.dwAddr+0
	movzx EDX, word ptr [ebx].RL.dwAddr+2
	shl edx, 4
	add eax, edx
	MOV [pDest], EAX

	MOV AX, [EBX].RL.wSecCnt
	MOV [wSecCnt], AX
	MOV EAX, [EBX].RL.dwStart
	MOV [dwSector], EAX
	xor edi, edi
ReadLP:
	CMP [wSecCnt], 0
	JZ EXIT
	CALL Setup			; set EDI=command table, ebx=port offset

;--- write packet data ( 12 bytes )
;--- 0: cmd 28 ( read )
;--- 1: flags
;--- 2-5: LBA (high byte first)
;--- 6: group no
;--- 7-8: transfer length [sector count] ( high byte first )
;--- 9: control

	MOV ECX, [dwSector]
	movzx eax, cx
	SHR ECX, 16
	XCHG AL, AH
	XCHG CL, CH
	SHL ECX, 16
	MOV CL, 28H

;--- ACMD.00: 28h (opcode "read cooked"),00,Sector.04,Sector.03
;--- ACMD.04: Sector.02, Sector.01, group#, length.02
;--- ACMD.08: length.01,00,00,00
	mov [edi].CT.Pkt0, ecx
	mov [edi].CT.Pkt1, eax
	mov [edi].CT.Pkt2, 1

	@dprintf <'DevInt, ReadL, calling ReqECX',13,10>
	MOV ECX, 800007FFH	; PRDT.0C: FF,07,00,80  (PRC=7FF transfer 2048 bytes, 80=I)
	CALL ReqECX
	AND AL,AL
	JZ GOOD
	CALL Setup
	CALL ReqSense
	AND AL,AL
	JNZ ERRORX
	mov eax, [pBuff]
	MOV AL, [eax+2]
	AND AL, 15
	mov EBX, OFFSET ERRTAB
	XLAT
	JMP ERRORX

GOOD:
	MOV ECX, SLCOOKED / sizeof dword
	mov EDI, [pDest]
	mov esi, [pBuff]
	@dprintf <'DevInt, readl, GOOD, src=%X, dst=%X',13,10>, esi, edi
	CLD
	REP MOVSD

	ADD [pDest], SLCOOKED
	INC [dwSector]
	DEC [wSecCnt]
	JMP ReadLP
ReadL endp

;--- in:
;--- ebx=RP if edi==0
;--- out:
;--- ebx=port offset
;--- edi=linear address ATAPI command table

Setup proc
	cmp edi, 0			; first call?
	jnz @F
	MOVZX EAX, byte ptr [EBX+1]
	MOVZX EBX, [eax*2][wPort]
	add ebx, [pHBA]

;--- get command list/table bases.
;--- those are physical addresses and hence "should" be translated to linear ones.

	mov eax, dword ptr [ebx].PORT.dqCLB	; get command list base
	mov edi, [eax].CLH.CTBA0			; get command table base address

	@dprintf <'DevInt, setup, port=%X cmdlist=%X cmdtable=%X',13,10>, ebx, eax, edi

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

	MOV ECX, [dwBuffPh]
	mov [edi].CT.p0.dwBase, ecx
	XOR ECX, ECX
	mov [edi].CT.p0.dwBaseU, ecx
	mov [edi].CT.p0.dwRsvd, ecx

	XOR ECX, ECX
	mov [ebx].PORT.dwIE, ecx
	MOV ECX, -1
	mov [ebx].PORT.dwIS, ecx
	mov [ebx].PORT.dwSERR, ecx
	mov ecx, [ebx].PORT.dwCMD
	OR CL, 10H			; P.CMD.FRE
	mov [ebx].PORT.dwCMD, ecx
	OR CL, 1			; P.CMD.ST
	mov [ebx].PORT.dwCMD, ecx
	@dprintf <'DevInt, setup done, waiting',13,10>
@@:
	mov eax, [ebx].PORT.dwCMD
	TEST AX, 8000H		; P.CMD.CR
	JZ @B
	RET
Setup endp

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
	MOV ECX, 80000007H	; PRDT.12: 07,00,00,80 (PRC=7; read 8 bytes, 80=I)

;--- ReqECX: 
;--- in: ecx: read ECX+1 bytes ( bit 31 = 1, indicating end of table )
;---     edi: cmd table
;---     ebx: port
;--- out: AL=0 ok, AL=12 error


ReqECX proc
	mov [edi].CT.p0.dwCnt, ecx
	mov [ebx].PORT.dwCI, 1	; 1=slot 0
WAITEN:
	mov eax, [ebx].PORT.dwCI
	AND EAX, EAX
	JZ FIN
	mov eax, [ebx].PORT.dwIS
	TEST EAX, 40000000H	; P.IS.30
	JNZ FINERR
	mov eax, [ebx].PORT.dwSERR
	AND EAX, EAX
	JZ WAITEN
FINERR:
	CALL Stop
	MOV AL, 12
	ret
FIN:
	mov eax, [ebx].PORT.dwTFD
	TEST AL, 1
	JNZ FINERR
	CALL Stop
	XOR EAX, EAX
	RET

Stop:
	mov ecx, [ebx].PORT.dwCMD
	OR CL, 8
	AND CL, 0EEH
	mov [ebx].PORT.dwCMD, ecx
	RETN

ReqECX endp

;--- in: EDX = ADDR+80000000h
;--- out: EAX = value

GetPCI proc
	PUSH EDX
	PUSH EBX
	PUSH EDX
	MOV DX, 0CF8H
	IN EAX, DX
	MOV EBX, EAX
	POP EAX
	OUT DX, EAX
	MOV DL, 0FCH
	IN EAX, DX
	MOV DL, 0F8H
	PUSH EAX
	MOV EAX, EBX
	OUT DX, EAX
	POP EAX
	POP EBX
	POP EDX
	RET
GetPCI endp

if 0

;--- in: EDX = ADDR+80000000h, EAX = VALUE

PutPCI proc
	PUSH EDX
	PUSH EBX
	PUSH EAX
	PUSH EDX
	MOV DX, 0CF8H
	IN EAX, DX
	MOV EBX, EAX
	POP EAX
	OUT DX, EAX
	MOV DL, 0FCH
	POP EAX
	OUT DX, EAX
	MOV DL, 0F8H
	MOV EAX, EBX
	OUT DX, EAX
	POP EBX
	POP EDX
	RET
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
	MOV EDX, CStr('AHCI Optical Disk Driver v1.2',13,10,"Inspired by Rudolph R. Loew's AHCICD",13,10)
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
	LODSB
	CMP AL, ' '
	jz nextchar
	CMP AL, 9
	jz nextchar
	cmp al, 13
	jz donecmdl
	cmp al, 0
	jz donecmdl
	CMP AL, '/'
	JNZ errcmdl
	LODSB
	mov ah, [esi]
	or al, 20h
	CMP AX, ':c'
	Jz isOptC
	CMP AX, ':d'
	Jz isOptD
	CMP AL, 'q'
	Jz isOptQ
	jmp errcmdl

isOptD:
	inc esi
	mov edi, [pBase]
	add EDI, DOSDRV.name_
	mov dword ptr [edi+0], '    '
	mov dword ptr [edi+4], '    '
	MOV ECX, sizeof DOSDRV.name_
ARG1:
	LODSB
	CMP AL, ' '
	jbe doneOptD
	CMP AL, 'a'
	JB @F
	CMP AL, 'z'
	JA @F
	SUB AL, 20H
@@:
	STOSB
	LOOP ARG1
	inc esi
doneOptD:
	dec esi
	jmp nextchar
isOptC:
	inc esi
	LODSB
	CMP AL, '0'
	jb errcmdl
	CMP AL, '9'
	Ja errcmdl
	SUB AL, '0'-1
	MOV [bCntArg], AL
	jmp nextchar
isOptQ:
	MOV [bQuiet], 1
	jmp nextchar

donecmdl:

;--- done cmdline processing

	call dispBanner

;--- scan for AHCI devices

	MOV EDX,80000008H
nextHBA:
	CALL GetPCI
	mov al, 0			; clear bits 0-7 (interface doesn't matter)
	CMP EAX, 1060100H	; AHCI device?
	JZ foundHBA
skipHBA:
	ADD EDX, 100H
	CMP EDX, 81000008H
	JC nextHBA
	JMP errnodisk

foundHBA:
	DEC [bCntArg]       ; /C:x argument?
	JNZ skipHBA

	mov dl, 24h			;get ABAR5
	call GetPCI
	mov edi, eax

	@dprintf <'HBA physical addr=%X',13,10>, eax

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

	shr eax, 12		;convert linear address to page#
	shr edi, 12
	push PC_WRITEABLE
	push edi
	push 1
	push eax
	VMMCall _PageCommitPhys
	add esp, 4*4

	mov eax, [ebx].HBA.dwGHC	; get Global HBA Control
	@dprintf <'HBA.GHC=%X',13,10>, eax
	TEST EAX, 80000000H	; AHCI enabled?
	JZ errnoahci

	mov ecx, [ebx].HBA.dwPI	; get ports implemented (bit mask)
	@dprintf <'HBA.Ports=%X',13,10>, ecx

	mov edx, 100h		; port offsets are 100h, 180h, 200h, 280h, ...
	mov edi, offset wPort
nextPort:
	AND ECX, ECX
	JZ donePort
	TEST CL, 1
	JNZ foundPort
skipPort:
	SHR ECX, 1
	ADD EDX, 80H
	JMP nextPort
foundPort:
	mov eax, [ebx+EDX].PORT.dwSIG	; get signature
	CMP EAX, 0EB140101H
	JNZ skipPort
	@dprintf <'found ATAPI device at port=%X',13,10>, edx
	mov eax, [ebx+EDX].PORT.dwSSTS	; get SATA status
	@dprintf <'device status=%X',13,10>, eax
	AND AL, 0FH			; bits 0-3: device detection
	CMP AL, 3			; device detected and communication established?
	JNZ skipPort
	mov eax, edx
	stosw
	CMP edi, offset wPort + sizeof wPort; table end reached?
	jb skipPort
donePort:

	sub edi, offset wPort
	shr edi, 1
	MOV ecx, edi
	cmp ecx, 0
	JZ errnodisk
	MOV [bCount], CL

	mov esi, offset buffer+15
	and esi, not 15		; align buffer to paragraph
	mov [pBuff], esi
	mov ecx, SLCOOKED
	mov edx, 1
	VxDCall VDMAD_Lock_DMA_Region
	mov [dwBuffPh], edx
	@dprintf <'physical address sector buffer=%X',13,10>, edx

	mov ebx, [pBase]
	MOV AL, [bCount]
	mov [ebx].DOSDRV.bUnits, al
	cmp [bQuiet], 0
	jnz @F
	add [MSG4], AL
	MOV EDX, OFFSET MSG4
	call dispString
@@:
	mov ebx, [pRequest]
	MOV WORD PTR [EBX].RP.RPSize+0, REQOFS+4+SIZERMCODE+5
	mov ax, RPDON
	mov [ebx].RP.RPStat, ax
	mov [ebx].RP.RPUnit, 0
	ret

errpr:
	MOV eDX, CStr('_PageReserve() failed',13,10)
	JMP @F
errnoahci:
	MOV eDX, CStr('AHCI Controller not in AHCI Mode',13,10)
	JMP @F
errcmdl:
	MOV eDX, CStr('SYNTAX: DEVICE=JLOAD.EXE AHCICD.DLL [/Q] /D:devname [/C:#]',13,10)
	JMP @F
errnodisk:
	MOV eDX, CStr('No AHCI Optical Disk Found',13,10)
@@:
	call dispBanner
	call dispString
	mov ax, RPERR
	ret
Init endp

DllMain proc stdcall uses esi edi hModule:dword, dwReason:dword, dwRes:dword

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

