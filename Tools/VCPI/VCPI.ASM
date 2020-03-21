
;*** display VCPI infomation
;*** and use VCPI to switch to protected mode and back

?ENTRIES equ 110h	;PTE entries to display with option -p
?VCPIDBG equ 0		;support VCPI debug interface
?DISPEXC equ 0		;display exceptions in ring 0

	.286
	.model small
	.stack 1024
	.dosseg

desc struct
limit   dw ?
A0015   dw ?
A1623   db ?
attrib  db ?
lim_gr  db ?
A2431   db ?
desc ends

CStr macro text:vararg
local sym
	.const
sym db text,0
	.code
	exitm <offset sym>
endm

	.386P
	option casemap:none
        
cr	equ 13
lf	equ 10

	.data

mygdt label byte                ;GDT
        db 1*8 dup (0)          ;+00h null descriptor
        db 1*8 dup (0)			;+08h
restab  db 3*8 dup (0)          ;+10h descriptors reserved for vcpi host
pmcs    desc <0ffffh,0,0,9Ah,0,0>	;+28h
pmds    desc <0ffffh,0,0,92h,0,0>	;+30h
pmflat  desc <0ffffh,0,0,92h,8fh,0>	;+38h
pmtr    desc <068h-1,0,0,89h,0,0> ;selector for TR	;+40h
if ?VCPIDBG
vcpidbgdesc label dword			;+48
		db 30*8 dup (0)			; 30 descriptors for 386SWAT
endif
SIZGDT	equ $ - mygdt
CSR0	equ pmcs - mygdt
DSR0	equ pmds - mygdt
FLATR0	equ pmflat - mygdt
TRSEL 	equ pmtr - mygdt
HOSTCS	equ restab - mygdt

pdgdt    label fword
         dw SIZGDT-1            ;limit GDTR
basegdt  dd offset mygdt        ;base  GDTR

pdidt    label fword
         dw 80h*8-1             ;limit IDTR
baseidt  dd offset myidt        ;base  IDTR

;--- far32 address of VCPI protected-mode API

vcpiv   label fword
vcpiofs dd 0
		dw HOSTCS		;selector for VCPI host code segment
		dw 0

;--- VCPI structure for switch to protected mode

modesw label byte
vcr3	dd 0					;CR3
vgdtr	dd offset pdgdt 		;linear address PD for GDTR
vidtr	dd offset pdidt 		;linear address PD for IDTR
		dw 0					;LDTR
		dw TRSEL				;TR
		dd offset pmentry		;EIP
		dw CSR0 				;CS

TSSSEG struct
dwLink	dd ?
dqStk0	df ?	;+04
		dw ?
dqStk1	df ?	;+0C
		dw ?
dqStk2	df ?	;+14
		dw ?
_CR3	dd ?	;+1C
_Eip	dd ?	;+20
_Efl	dd ?	;+24
_Eax	dd ?	;+28
_Ecx	dd ?	;+2C
_Edx	dd ?	;+30
_Ebx	dd ?	;+34
_Esp	dd ?	;+38
_Ebp	dd ?	;+3C
_Esi	dd ?	;+40
_Edi	dd ?	;+44
_ES		dd ?	;+48
_CS		dd ?	;+4C
_SS		dd ?	;+50
_DS		dd ?	;+54
_FS		dd ?	;+58
_GS		dd ?	;+5C
_LDT	dd ?	;+60
wFlags  dw ?	;+64
wOffs   dw ?	;+66
TSSSEG ends

;taskseg TSSSEG <>   ;task state segment

dwPage	dd 0		;page to release / allocated
dwFreePages dd 0	;number free pages
dwNumPages dd 1		;no of pages to alloc / free
dwAlloced dd 0		;pages allocated
dwFreed dd 0		;pages freed

;--------- FEDCBA9876543210FEDCBA9876543210
excv	dd 00000000000001100111110100000000B

handle  dw 0		;handle EMS 
segcs   dw 0		;segment CS
segds   dw 0		;segment DS
ptadr   dw 0		;segment page table 0

flags   db 00

UFLAG	equ 1
NFLAG	equ 2
QFLAG	equ 4
PFLAG	equ 8
FFLAG	equ 16
AFLAG	equ 32
RFLAG	equ 64

bRet	db 00
bNoDisp	db 00

if ?VCPIDBG
bVCPIDbg db 0
dfDbgEntry df 0
endif

	.data?

myidt label byte
	db 80h*8 dup (?)

ptab	db 1000h dup (?)
drtab	dd 8 dup (?)

	.code

	include printf.inc

_putchr proc
	mov dl,al
	mov ah,2
	int 21h
	ret
_putchr endp

_crout proc
	invoke printf,CStr(10)
	ret
_crout endp

_wordout proc stdcall uses bx cx dx value:word
	invoke printf,CStr("%04X"),value
	ret
_wordout endp

if ?DISPEXC

?EXC = 0

@defexc macro
	push ?EXC
	jmp defexc
?EXC = ?EXC + 1
	endm

exceptions:
	rept 32
	@defexc
	endm

defexc:
	push ebp
	mov ebp,esp
	pushad
	lea esi,[ebp+4]
	cld
	mov edi,0B8000h
	mov ax,ss:[esi]	;exc no
	call putw
	mov ax,0700h+' '
	stos word ptr es:[edi]
	mov cx,ss:[esi]
	add esi,2
	bt word ptr cs:[excv],cx
	jnc @F
	mov eax,ss:[esi]
	call putd
	mov ax,0700h+' '
	stos word ptr es:[edi]
	add esi,4
@@:
	mov ax,ss:[esi+4]	;CS
	call putw
	mov ax,0700h+':'
	stos word ptr es:[edi]
	mov eax,ss:[esi]	;EIP
	call putd
	mov ax,0700h+' '
	stos word ptr es:[edi]
	add esi,8

	mov eax,ss:[esi]	;EFL
	call putd
	mov ax,0700h+' '
	stos word ptr es:[edi]
	add esi,4

;@@:
;	inc dword ptr es:[edi]
;	jmp @B

	mov cx,[ebp+4]	;exc no
	bt word ptr cs:[excv],cx
	jc @F
	popad
	pop ebp
	add esp,2
	iretd
@@:
	popad
	pop ebp
	add esp,4+2
	iretd

putd:
	push eax
	shr eax,16
	call putw
	pop eax
putw:
	push ax
	mov al,ah
	call putb
	pop ax
putb:
	mov ah,al
	shr al,4
	call putnyb
	mov al,ah
putnyb:
	and al,0Fh
	add al,'0'
	cmp al,'9'
	jbe @F
	add al,7
@@:
	stos byte ptr es:[edi]
	inc edi
	ret
endif

defint proc near
	push eax
	mov al,0Bh
	out 0A0h,al
	in al,0A0h
	and al,al
	jz @F
	mov al,20h
	out 0a0h,al
@@:
	mov al,0Bh
	out 20h,al
	in al,20h
	and al,al
	jz @F
	mov al,20h
	out 0a0h,al
@@:
	pop eax
;	sti			;this is not needed, client runs in ring 0!
	iretd
defint endp

descout proc near
	mov ah,[di+7]		;base bits 31..24
	mov al,[di+4]		;base bits 23..16
	shl eax,16
	mov ax,[di+2]		;base bits 15..0
	mov dx,[di+0]		;limit bits 15..0
	mov cx,[di+5]
	invoke printf, CStr("%08lX:%04X,%04X"),eax,dx,cx
	stc
	ret
descout endp

gethex proc
	xor edx, edx
	mov ch,0
nextitem:
	mov al,es:[si]
	cmp al,'0'
	jb done
	cmp al,'9'
	jbe @F
	or al,20h
	cmp al,'a'
	jb done
	cmp al,'f'
	ja done
	sub al,27h
@@:
	sub al,'0'
	movzx eax,al
	shl edx, 4
	add edx, eax
	inc ch
	inc si
	jmp nextitem
done:
	mov eax, edx
	cmp ch,1
	ret
gethex endp

getdec  proc
	xor edx, edx
	mov ch,0
nextitem:
	mov al,es:[si]
	cmp al,'0'
	jb done
	cmp al,'9'
	ja done
	sub al,'0'
	movzx eax,al
	shl edx, 1
	lea edx, [edx+edx*4]
	add edx, eax
	inc ch
	inc si
	jmp nextitem
done:
	mov eax, edx
	cmp ch,1
	ret
getdec  endp

;--- get cmdline parameters

getparm proc near
	mov si,0080h
	mov bl,byte ptr es:[si]
	inc si
	mov bh,0
	mov byte ptr es:[si+bx],0
getp21:
	mov al,es:[si]
	inc si
	and al,al
	jz getp1
	cmp al,'/'
	jz isoption
	cmp al,'-'
	jz isoption
	cmp al,' '
	jbe getp21
	jmp parerr
getp1:
	clc
	ret
isoption:
	mov al,es:[si]
	and al,al
	jz parerr
	inc si
	or al,20h
	mov ah,al
	cmp al,'r'
	jnz @F
	or [flags],RFLAG
	jmp get_hex
@@:
	cmp al,'f'
	jnz @F
	or [flags],FFLAG
	jmp get_hex
@@:
	cmp al,'p'
	jnz @F
	or [flags],PFLAG
	jmp getp21
@@:
	cmp al,'q'
	jnz @F
	or [flags],QFLAG
	jmp getp21
@@:
	cmp al,'n'
	jnz @F
	or [flags],NFLAG
	jmp getp21
@@:
	cmp al,'u'
	jnz @F
	or [flags],UFLAG
	jmp getp21
@@:
	cmp al,'a'
	jnz parerr
	or [flags],AFLAG
	call skipws
	cmp al,'0'
	jb getp21
	jmp get_dec

;--- get a decimal number

get_dec:
	call skipws
	jz parerr
	call getdec
	jc parerr
	and eax, eax
	jz parerr
	mov dwNumPages, eax
	jmp getp21

;--- get a hex number, then a decimal number

get_hex:
	call skipws
	jz parerr
	call gethex
	jc parerr
	mov dwPage, eax
	call skipws
	jz getp21
	cmp al,','
	jnz getp21
	inc si
	call skipws
	jz parerr
	jmp get_dec
parerr:
	stc
	ret
skipws:
	mov al,es:[si]
	and al,al
	jz @F
	inc si
	cmp al,20h
	jbe skipws
	dec si
@@:
	ret
getparm endp

main proc c

	movzx eax,ax
	movzx ebx,bx
	movzx ecx,cx
	movzx edx,dx
	movzx esi,si
	movzx edi,di
	movzx ebp,bp
	movzx esp,sp

	call getparm
	jnc main_1
	invoke printf, CStr( <'usage: vcpi [ options ]',cr,lf>)
	invoke printf, CStr( <'    -a <nn>: alloc <1|nn> page(s) in protected mode',cr,lf>)
	invoke printf, CStr( <'    -f page,<nn>: free <1|nn contiguous> page(s) in protected mode',cr,lf>)
	invoke printf, CStr( <'    -n: dont try to switch to protected mode (disables -q -f -a)',cr,lf>)
	invoke printf, CStr( <'    -p: display PTEs for conventional memory',cr,lf>)
	invoke printf, CStr( <'    -q: query num pages in protected mode',cr,lf>)
	invoke printf, CStr( <'    -r page,<nn>: free <1|nn contiguous> page(s) in real-mode',cr,lf>)
	invoke printf, CStr( <'    -u: display regions mapped as UMBs',cr,lf>)
	jmp mainex
main_1:
	mov al,flags
	and al,AFLAG or FFLAG or RFLAG or UFLAG
	mov bNoDisp,al

	mov di, offset ptab
	mov cx, (sizeof ptab) / 4
	push ds
	pop es
	xor eax,eax
	rep stosd

	mov ax,3567h
	int 21h
	mov ax,es
	or ax,bx
	jnz main3
	invoke printf, CStr( <"int 67h is zero (no EMM)",cr,lf>)
	mov al,01
	jmp mainex
main3:
								;get memory for page tables
	mov bx,400h
	mov ah,48h
	int 21h
	jc mainex
	mov bx,ax
	movzx eax,ax
	shl eax, 4
	add eax,4096-1			;page directory must be page aligned
	and ax,0f000h

	mov vcr3,eax			;clear bits 0-11 
	mov edi,eax
	add edi,1000h
	shr eax,4
	mov es,ax
							;page directory 1. entry
	or di,1+2+4				;set present, r/w, user
	mov es:[0000],edi		;set PDE for 0-3FFFFFh
	mov ax,es
	add ax,100h
	mov [ptadr],ax

	call pvcpi
	mov al,00
mainex:
	ret
main endp

EMScheck proc

	push ds
	push si
	push di

	mov ax,3567h
	int 21h
	push ds
	pop es

	mov di,000ah
	push cs
	pop ds
	mov si,offset emsstr
	mov cx,8
	repz cmpsb
	mov ax,1
	jz @F			   ;1 = EMS exists
	dec ax			   ;0 = EMS doesn't exist
@@:
	pop di
	pop si
	pop ds
	ret
EMScheck endp

emsstr  db 'EMMXXXX0'

;*** protocol vcpi ***

pvcpi proc near

	mov cl,2
@@:
	mov ax,0DE00h		;is vcpi supported?
	int 67h
	cmp ah,00
	jz pvcpi1
	push cx
	call EMScheck
	pop cx
	and ax,ax
	jz pvcpi1x
	mov ax,4300h
	mov bx,0001h		;get EMS page to ensure EMM is ON
	int 67h
	and ah,ah
	jnz pvcpi1x
	mov [handle],dx
	dec cl
	jnz @B
pvcpi1x:
	invoke printf, CStr( <"no VCPI host found",cr,lf>)
	jmp pvcpiex
pvcpi1:
	cmp bNoDisp, 0
	jnz @F
	movzx ax,bh
	movzx bx,bl
	invoke printf, CStr( <"VCPI version: %u.%u",lf>),ax,bx
@@:
if ?VCPIDBG
	mov ax,0DEF0h
	int 67h
	cmp ah,0
	jnz @F
	mov bVCPIDbg,1
@@:
endif
	call InitProt

	mov es,[ptadr]
	xor di,di			;ES:DI -> page table 0	
	mov si,offset restab;DS:SI -> 3 free GDT descriptors
	mov ax,0DE01h		;get protected mode interface
	int 67h
	cmp ah,00
	jnz de01done
	mov [vcpiofs],ebx
	cmp bNoDisp, 0
	jnz de01done
	invoke printf, CStr( <"Offset of VCPI entry in protected-mode: %08lX",lf>),ebx
	movzx edi,di
	shl edi, 10
	invoke printf, CStr( <"Start free address space: %08lX",lf>), edi
	invoke printf, CStr( <'1. VCPI descriptor: '>)
	mov di,offset restab
	call descout
	invoke _crout
	invoke printf, CStr( <'2. VCPI descriptor: '>)
	mov di,offset restab+8
	call descout
	invoke _crout
	invoke printf, CStr( <'3. VCPI descriptor: '>)
	mov di,offset restab+16
	call descout
	invoke _crout
de01done:

	cmp bNoDisp, 0
	jnz noprot

	mov ax,0DE02h		;maxAddr 4K Page
	int 67h
	invoke printf, CStr( <"highest physical memory address: %08lX",lf>),edx

	mov ax,0DE03h		;num free 4K Pages
	int 67h
	cmp ah,0
	jz @F
	movzx ax,ah
	invoke printf, CStr( <'int 67h, ax=DE03h failed, status AH=%02X',lf>),ax
	jmp de03done
@@:
	mov eax,edx
	shl eax,2
	invoke printf, CStr( <'Free 4K pages: %lu ( %lu kB)',lf>), edx, eax
de03done:
	mov ax,0DE07h		;get CR0
	int 67h
	cmp ah,0
	jnz de07done
	invoke printf, CStr( <"CR0: %08lX",lf>),ebx
de07done:
	mov di,offset drtab
	push ds
	pop es
	mov cx,8
	mov eax,-1
	mov dx,di
	rep stosd
	mov di,dx

	mov ax,0DE08h		;get DRx
	int 67h
	cmp ah,0
	jnz de08done
	invoke printf, CStr( <"DR0-DR3: %08lX %08lX %08lX %08lX",lf>), dword ptr es:[di+0],\
		dword ptr es:[di+4], dword ptr es:[di+8], dword ptr es:[di+12]
	invoke printf, CStr( <"DR6+DR7: %08lX %08lX",lf>),dword ptr es:[di+24], dword ptr es:[di+28]
de08done:
	mov ax,0DE0Ah		;get interrupt vector mappings
	int 67h
	cmp ah,0
	jnz de0adone
	invoke printf, CStr( <"Master/Slave PIC base: %X/%X",lf>), bx, cx
de0adone:

noprot:
	test flags,PFLAG
	jz @F
	call DispPTEs
@@:
	test flags,UFLAG
	jz @F
	call DispUMBs
@@:
	test flags,PFLAG or RFLAG or NFLAG or UFLAG
	jnz @F
	call pmgo			;--- call protected mode
@@:
	test flags,RFLAG
	jz @F
	call rmfree
@@:
	call protocol
pvcpiex:
	mov dx,[handle]
	and dx,dx
	jz pvcpiex1
	mov ax,4500h		;release the EMS page again
	int 67h
pvcpiex1:
	ret
pvcpi endp

;--- display UMBs

DispUMBs proc uses es si

	nop
	invoke printf, CStr( <"Pages used for UMBs:",lf>)
	mov es,[ptadr]
	mov si,0000
	mov cx,100h
	xor edx,edx
nextitem:
	mov eax,es:[si]
	and ax,0F000h
	cmp eax,edx
	jz @F
	mov eax, edx
	shr eax,4
	invoke _wordout,  ax
	mov al,' '
	call _putchr
@@:
	add edx,1000h
	add si,4
	loop nextitem
	invoke _crout
	ret
DispUMBs endp        

;--- display PTEs of 1. MB

DispPTEs proc uses es si

	nop ;MASM bug
	invoke printf, CStr( <"Paging Table",cr,lf>)
	mov es,[ptadr]
	mov si,0000
	mov cx,?ENTRIES
nextitem:
	push cx
	test si,01Fh
	jnz @F
	mov ax,si
	shr ax,2
	invoke _wordout, ax
	mov al,':'
	call _putchr
	mov al,' '
	call _putchr
@@:
	mov eax,es:[si+0]
	push ax
	invoke printf,CStr("%8lX"),eax
	pop ax
	and ax,0FFE7h		;???
	mov es:[si+0],ax	;???
	mov al,' '
	call _putchr
	add si,4
	test si,1Fh
	jnz @F
	invoke _crout
@@:
	pop cx
	loop nextitem
	ret
DispPTEs endp

;--- fill VCPI comm structure
;--- set descriptors

InitProt proc near
	mov ax,cs
	movzx eax,ax
	shl eax, 4
	mov pmcs.A0015,ax
	shr eax,16
	mov pmcs.A1623,al

	mov ax,ds
	movzx eax,ax
	shl eax, 4
	add basegdt, eax
	add baseidt, eax
	add vgdtr, eax
	add vidtr, eax

	mov pmds.A0015,ax
	mov pmtr.A0015,ax
	shr eax,16
	mov pmds.A1623,al
	mov pmtr.A1623,al


	mov bx,0
	mov edi,offset myidt
if ?DISPEXC
	mov ax,offset exceptions
nextitem:
	mov word ptr [di+0],ax
	mov word ptr [di+2],CSR0
	mov word ptr [di+4],0EE00h
	mov word ptr [di+6],0
	inc bl
	add di,8
	add ax,4
	cmp bl,20h
	jnz nextitem
endif
nextitem2:
	mov word ptr [di+0],offset defint
	mov word ptr [di+2],CSR0
	mov word ptr [di+4],0EE00h
	mov word ptr [di+6],0
	inc bl
	add di,8
	cmp bl,80h
	jnz nextitem2
	ret
InitProt endp

;--- switch to protected-mode and back to v86-mode throu VCPI

pmgo proc near

if ?VCPIDBG
	cmp bVCPIDbg,1
	jnz novcpidbg
;	mov dword ptr taskseg.dqStk0+0, esp
;	mov word ptr taskseg.dqStk0+4, DSR0
	mov ebx,vcr3
	mov edx,vcr3  ;linear address (phys==lin here)
	mov ax,0DEF4h
	int 67h
	cmp ah,0
	jz @F
	invoke printf, CStr( <"int 67h, ax=DEF4h failed",cr,lf>)
	mov ah,00
	int 16h
	jmp novcpidbg
@@:
	mov edi,offset vcpidbgdesc
	push ds
	pop es
	mov bx,offset vcpidbgdesc - offset mygdt
	mov ax,0DEF2h
	int 67h
	cmp ah,0
	jz @F
	invoke printf, CStr( <"int 67h, ax=DEF2h failed",cr,lf>)
	mov ah,00
	int 16h
	jmp novcpidbg
@@:
	mov dword ptr dfDbgEntry+0,edx
	mov word ptr dfDbgEntry+4,bx
	mov bx,0
	mov edi,offset myidt
	push ds
	pop es
nextitem:
	mov ax,0DEF3h
	int 67h
	cmp ah,0
	jz @F
	cmp ah,83h	;not needed by the vcpi debugger
	jz @F
	movzx ax,ah
	invoke printf, CStr( <"int 67h, ax=DEF3h failed, ah=%02X, bx=%04X",lf>),ax, bx
	mov ah,00
	int 16h
	jmp novcpidbg
@@:
	inc bx
	add di,8
	cmp bx,20h
	jnz nextitem
novcpidbg:
endif
	cli

	mov [segcs],cs
	mov [segds],ds

	mov ax, ds
	movzx eax, ax
	shl eax, 4
	lea esi, [eax + offset modesw]

	movzx ebx,sp

	mov ax,0DE0Ch
	int 67h
pmentry::						;now in protected mode
	mov ax,DSR0
	mov ss,ax
	mov esp,ebx
	mov ds,ax
	mov ax,FLATR0		;4G selector -> ES
	mov es,ax
	xor ax,ax
	mov fs,ax
	mov gs,ax

if ?VCPIDBG
	int 3
endif
	test flags, QFLAG
	jz @F
	call pmquery
@@:
	test flags, AFLAG
	jz @F
	call pmalloc
@@:
	test flags, FFLAG
	jz @F
	call pmfree
@@:
;--- jump back to v86
;--- SS:ESP+8 -> IRET32V86
;--- DS=FLAT

	xor eax,eax
	push eax 		 ;gs
	push eax 		 ;fs
	push ax
	push [segds] 	 ;ds
	push ax
	push [segds] 	 ;es
	push ax
	push [segds] 	 ;ss
	push ax
	push bx			 ;esp
	push ax
	pushf			 ;eflags
	push ax
	push [segcs] 	 ;CS
	push ax
	push offset rmentr;EIP

	clts						;clear task switched flag

	mov ax,FLATR0
	mov ds,ax					;DS must be FLAT
	mov ax,0DE0Ch
	call fword ptr ss:[vcpiv]
rmentr: 						;back in v86-mode
	sti
	ret
pmgo endp

protocol proc
	.if (flags & AFLAG)
		invoke printf, CStr( <"alloced %lu">), dwAlloced
		movzx ax,bRet
		invoke printf, CStr( <" page(s) in pm, last status ah=%02X">),ax
		.if (dwAlloced)
			invoke printf, CStr( <", (first) page=%08lX">), dwPage
		.endif
		invoke _crout
	.elseif (flags & FFLAG)
		invoke printf, CStr( <"freed %lu">), dwFreed
		movzx ax,bRet
		invoke printf, CStr( <" page(s) in pm, last status ah=%02X">),ax
		.if (dwFreed)
			invoke printf, CStr( <", (last) page released=%08lX">), dwPage
		.endif
		invoke _crout
	.elseif (flags & RFLAG)
		invoke printf, CStr( <"freed %lu">), dwFreed
		movzx ax,bRet
		invoke printf, CStr( <" page(s) in rm, last status ah=%02X">),ax
		.if (dwFreed)
			invoke printf, CStr( <", (last) page released=%08lX">), dwPage
		.endif
		invoke _crout
	.elseif (flags & QFLAG)
		movzx ax,bRet
		invoke printf, CStr( <"%lu free pages in pm, status ah=%02X",lf>), dwFreePages, ax
	.elseif (flags & (UFLAG or PFLAG))
	.elseif (!(flags & NFLAG))
		invoke printf, CStr( <'Protected Mode Switch ok',cr,lf>)
	.endif
	ret
protocol endp

;--- query free VCPI page(s) using protected-mode API

pmquery proc
	pushad
	mov ax,0DE03h
	call fword ptr ss:[vcpiv]
	mov bRet, ah
	mov dwFreePages, edx
	popad
	ret
pmquery endp

;--- allocate VCPI page(s) using protected-mode API

pmalloc proc
	pushad
	mov ecx, dwNumPages
nextitem:
	mov ax,0DE04h
	call fword ptr ss:[vcpiv]
	mov bRet, ah
	and ah,ah
	jnz allocerr
	inc dwAlloced
	cmp ecx,dwNumPages
	jnz @F
	mov dwPage, edx
@@:
	dec ecx
	jnz nextitem
allocerr:
	popad
	ret
pmalloc endp

;--- release VCPI page(s) with protected-mode VCPI API

pmfree proc
	mov edx, dwPage
	and edx, edx
	jz exit
	pushad
	mov ecx, dwNumPages
nextitem:
	mov ax,0DE05h
	call fword ptr ss:[vcpiv]
	and ah,ah
	jnz done
	mov dwPage, edx
	inc dwFreed
	add edx,1000h
	dec ecx
	jnz nextitem
done:
	mov bRet, ah
	popad
exit:
	ret
pmfree endp

;--- free VCPI pages with real-mode VCPI API

rmfree proc
	mov edx, dwPage
	and edx, edx
	jz exit
	mov ecx, dwNumPages
nextitem:
	mov ax,0DE05h
	int 67h
	and ah,ah
	jnz exit
	inc dwFreed
	mov dwPage, edx
	add edx,1000h
	dec ecx
	jnz nextitem
exit:
	mov bRet, ah
	ret
rmfree endp

start:
	mov ax,@data
	mov ds,ax
	mov bx,ss
	mov cx,ds
	sub bx,cx
	shl bx,4
	add bx,sp
	mov ss,ax
	mov sp,bx
	mov ax,ds
	mov cx,cs
	sub ax,cx
	add ax,10h
	shr bx,4
	add bx,ax
	mov ah,4ah
	int 21h
	call main
	mov ax,4c00h
	int 21h

	END start
