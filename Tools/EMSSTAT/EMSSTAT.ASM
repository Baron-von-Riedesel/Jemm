
;--- EMSSTAT: display EMS status.
;--- Public Domain.
;--- tools: JWasm/Masm v6 and WLink.

	.286
	.model small
DGROUP group _TEXT		;use TINY model
	.386

cr	equ 13
lf	equ 10

;--- define a string constant

CStr macro string:vararg
local xxx
CONST segment
xxx db string
	db 0
CONST ends
	exitm <offset xxx>
	endm

	.dosseg
	.stack 1024 

	.data

fc		dw 0	;EMS function code
handle	dw 0	;EMS handle
totalpg	dd 0
totalkb	dd 0
bStd	db 01
bVCPI	db 00
bPages	db 00
bDevice	db 00

	.const

emsstr1 db 'EMMXXXX0',0
emsstr2 db 'EMMQXXX0',0
emsstr3 db 'EMMXXXQ0',0 ;qemm


	.data?

namtab	db 12 dup (?)
gdttab	db 8*3 dup (?)
buffer	db 4096h dup (?)

	.code

	include printf.inc

;--- test if EMM is installed
;--- out: ax=0 if no EMM found
;---      ax=1 if EMM found

EMScheck proc uses es si di

	mov ax, 3567h
	int 21h
	mov ax, es
	or ax, bx
	jz exit

	mov dx,1
	mov si,offset emsstr1
	mov di,000ah
	mov cx,8
	cld
	repz cmpsb
	jz found

	mov dx,0
	mov ah,46h
	int 67h
	and ah,ah
	jz found

	xor ax, ax
	jmp exit
found:
	and dx,dx
	jnz isems
	invoke printf, CStr("EMM installed, but NOEMS, device name=")
	mov bx,10
	mov cx,8
@@:
	mov al,es:[bx]
	push cx
	invoke printf, CStr("%c"),ax
	pop cx
	inc bx
	loop @B
	invoke printf, CStr(lf)
isems:
	mov ax,1
exit:
	ret

EMScheck endp

_upper:
	cmp al,'a'
	jb @F
	and al,not 20h
@@:
	ret
_skipws:
	mov al,es:[bx]
	inc bx
	cmp al,' '
	je _skipws
	cmp al,9
	je _skipws
	dec bx
	cmp al,13
	ret

;--- ES=PSP

getpar proc near
	mov bx,0080h
	mov cl,es:[bx]
	cmp cl,00
	jz getp1
getp2:
	inc bx
	call _skipws
	jz getp1
	cmp al,'/'
	jz @F
	cmp al,'-'
	jnz parerr
@@:
	inc bx
	mov al,es:[bx]
	call _upper
	cmp al,'V'
	jz getp3
	cmp al,'D'
	jz getp4
	cmp al,'P'
	jnz parerr
	mov byte ptr [bStd],0
	mov byte ptr [bPages],01
	jmp getp2
getp3:
	mov byte ptr [bStd],0
	mov byte ptr [bVCPI],01
	jmp getp2
getp4:
	mov byte ptr [bStd],0
	mov byte ptr [bDevice],01
	jmp getp2
getp1:
	clc
	ret
parerr:
	invoke printf, CStr("usage: EMSSTAT [ options ]",lf)
	invoke printf, CStr("options are:",lf)
	invoke printf, CStr("    -p: display physical pages",lf)
	invoke printf, CStr("    -v: display VCPI info",lf)
	invoke printf, CStr("    -d: try to open devices EMMXXXX0 or EMMQXXX0",lf)
	stc
	ret
getpar endp

;--- ES=PSP

main proc c

	call getpar
	jc exit

	call EMScheck
	and ax,ax
	jnz @F
	invoke printf, CStr("EMM not found",lf)
	mov al,01
	jmp nointapi
@@:
	.if (bStd)
		call readd	;read+display EMS standard info
		call rpages	;display raw pages
		call xvhandle;display EMS handle infos	 
	.endif

	.if (bPages)
		call ppages	;display EMS mapping info
	.endif

	.if (bVCPI)
		call vcpi	;display VCPI info
	.endif

	.if (bDevice)
		call deviceinfo;display EMMXXXX0 device info
	.endif

nointapi:
	mov al,00
exit:
	ret
main endp

;--- read EMS info

readd proc near
	mov ax,4100h
	call intrt
	mov si,offset buffer
	mov [si + 0],bx 	;segment address of page frame
	mov ax,4600h
	call intrt
	mov [si + 2],al 	;version (3.2 or 4.0)
	mov ax,4200h
	call intrt
	mov [si + 3],dx 	;num total 16 kB pages
	mov [si + 5],bx 	;num free 16 kB pages
	mov ax,16
	mul dx
	mov [si + 11],ax	;total in kb
	mov [si + 13],dx	;total in kb
	mov ax,16
	mul bx
	mov [si + 19],ax	;free in kb
	mov [si + 21],dx	;free in kb
	mov ax,4b00h
	call intrt
	mov [si + 7],bx 	;active handles
	mov ax,5801h
	call intrt
	mov [si + 17],cx	;num mappable physical pages

	mov al,[si+2]
	mov ah,0
	shl ax,4
	mov cl,ah
	shr al,4
	mov ah,0
	mov ch,0
	invoke printf, CStr("EMS version: %u.%u",lf), cx, ax
	mov ax,[si+3]
	mov cx,[si+5]
	mov edx,[si+11]
	mov ebx,[si+19]
	invoke printf, CStr('16 kB pages total/free: %u/%u (%lu/%lu kB)',lf),ax,cx,edx,ebx
	mov ax,  [si+0]
	invoke printf, CStr('EMS page frame: %04X',lf),ax
	mov ax,  [si+7]
	invoke printf, CStr('Active handles: %u',lf),ax
	mov ax,  [si+17]
	invoke printf, CStr('physical pages: %u',lf),ax

	mov ax,5900h
	lea di,[si+23]
	push ds
	pop es
	int 67h
	and ah,ah
	jz ems59
	mov al,ah
	mov ah,0
	invoke printf, CStr("int 67h, ax=5900h (get EM hardware information) failed, status=%X",lf),ax
	jmp ems59done
ems59:
	mov ax, [si+23]
	shl ax, 4
	invoke printf, CStr('Raw pages size: %u',lf),ax
	mov ax, [si+25]
	invoke printf, CStr('Alternate map register sets: %u',lf),ax
	mov ax, [si+27]
	invoke printf, CStr('Mapping context size: %u',lf),ax
	mov ax, [si+29]
	invoke printf, CStr('DMA register sets: %u',lf),ax
ems59done:
	ret
readd endp

;--- display raw pages

rpages proc
	mov ax,5901h
	int 67h
	cmp ah,0
	jnz exit
	invoke printf, CStr("raw pages total/free: %u/%u",lf),dx,bx
exit:
	ret
rpages endp

;*** display EMS handle information

xvhandle proc near

local	wHandles:WORD

	mov ax,5402h		;get number of handles in BX
	int 67h
	and ah,ah
	jz @F
	mov al,ah
	mov ah,0
	invoke printf, CStr("int 67h, ax=5402h (get number of handles) failed, status=%X",lf),ax
	jmp done
@@:
	invoke printf, CStr("(max) size of handle table: %u",lf),bx

	push ds
	pop es
	mov di,offset buffer
	mov ax,5400h		;get handle directory
	int 67h
	and ah,ah
	jz @F
	mov al,ah
	mov ah,0
	invoke printf, CStr("int 67h, ax=5400h (get handle directory) failed, status=%X",lf),ax
	jmp done
@@:
	movzx ax,al
	mov wHandles,ax
	and ax, ax
	jz done
	invoke printf, CStr("Handle Name     Pages     KB",lf)
	invoke printf, CStr("-----------------------------",lf)
	mov cx,wHandles
nexthdl:						;<------
	push cx
	mov ax,[di]
	invoke printf, CStr("%6u "), ax
	lea si,[di+2]
	mov cx,8
nextchar:
	lodsb
	cmp al,0
	jnz @F
	mov al,' '
@@:
	mov dl,al
	mov ah,2
	int 21h
	loop nextchar
	
	mov dx,[di]
	mov ax,4c00h		;get handle pages
	int 67h
	and ah,ah
	jz @F
	invoke printf, CStr("    ?      ?",lf)
	jmp invalhdl
@@:
	movzx ebx,bx
	add [totalpg],ebx
	push bx
	invoke printf, CStr("%5u"), bx
	pop bx
	mov ax,16
	mul bx
	push dx
	push ax
	pop eax
	add [totalkb],eax
	invoke printf, CStr("%8lu",lf), eax
invalhdl:
	pop cx
	add di,10
	loop nexthdl
	invoke printf, CStr("-----------------------------",lf)
	mov eax,dword ptr [totalpg+0]
	mov edx,dword ptr [totalkb+0]
	invoke printf, CStr("               %5lu%8lu",lf), eax, edx
done:
	ret
xvhandle endp

searchpage proc
	push di
@@:
	cmp si,[di]
	jz @F
	add di,4
	loop @B
	stc
@@:
	mov ax,[di+2]
	pop di
	ret
searchpage endp

;*** display mapping segment -> physical page

ppages proc c

local	count:word
local	numpgs:word

	mov ax,5801h
	int 67h
	cmp ah,00
	jz @F
	mov al,ah
	mov ah,0
	invoke printf, CStr("int 67h, ax=5801h (get mappable pages) failed, status=%X",lf),ax
	jmp exit
@@:
	and cx,cx
	jz nopages
	mov numpgs,cx
	mov count,0
	mov di,offset buffer
	push ds
	pop es
	mov ax,5800h				;get mappable physical address array
	int 67h
	cmp ah,00
	jz @F
	mov al,ah
	mov ah,0
	invoke printf, CStr("int 67h, ax=5800h (get mappable pages) failed, status=%X",lf),ax
	jmp exit
@@:
	invoke printf, CStr("Segm:Pg Segm:Pg Segm:Pg Segm:Pg",lf)
	invoke printf, CStr("-------------------------------",lf)
	xor si,si
ppage3:
	mov ax,si
	invoke printf,CStr("%04X:"),ax
	mov cx,numpgs
	call searchpage
	jc @F
	invoke printf,CStr("%2u"),ax
	jmp ppage4
@@:
	invoke printf, CStr("--")
ppage4:

	invoke printf,CStr(" ")
	inc count
	test byte ptr count,3
	jnz @F
	invoke printf, CStr(lf)
@@:
	add si,400h
	jnz ppage3
	invoke printf, CStr(lf)
exit:
	ret
nopages:
	invoke printf, CStr("no mappable pages",lf)
	ret
ppages endp

intrt proc near
	mov fc,ax
	int 67h
	and ah,ah
	jz intrt1
	push ax
	mov al,ah
	mov ah,0
	mov cx,fc
	invoke printf, CStr("function:%X - RC:%X",lf),cx,ax
	pop ax
	mov bx,0000
intrt1:
	ret
intrt endp

descout proc near
	mov ah,[di+7]		;base bits 31..24
	mov al,[di+4]		;base bits 23..16
	mov cx,[di+2]		;base bits 15..0
	invoke printf, CStr("%08lX:"), ax::cx
	mov ax,[di+0]		;limit bits 15..0
	mov cx,[di+5]
	invoke printf, CStr("%04X,%04X",lf),ax,cx
	add di,8
	stc
	ret
descout endp

;*** display vcpi information

vcpi proc near

	mov ax,4300h
	mov bx,0001h		;get a ems page to ensure vcpi is active
	call intrt
	mov [handle],dx

	mov ax,0DE00h		;vcpi supported?
	int 67h
	cmp ah,00
	jz @F
	invoke printf, CStr("VCPI not supported",lf)
	jmp exit
@@:
	mov al,bh
	mov ah,0
	mov bh,0
	invoke printf, CStr("VCPI version: %u.%u",lf),ax,bx

	push ds
	pop es
	mov di,offset buffer
	mov si,offset gdttab	;DS:SI -> 3 GDT descriptors
	mov ax,0DE01h			;get protected mode interface
	int 67h
	.if (ah == 0)
		invoke printf, CStr("offset for protected-mode switch:%08lX",lf), ebx
		sub di,offset buffer
		movzx edi,di
		shl edi, 10 	;440h -> 110000
		mov eax, edi
		invoke printf, CStr("Start free address space: %lX",lf), eax
		mov di,offset gdttab
		invoke printf, CStr('1. VCPI descriptor: ')
		call descout
		invoke printf, CStr('2. VCPI descriptor: ')
		call descout
		invoke printf, CStr('3. VCPI descriptor: ')
		call descout
	.else
		mov al,ah
		mov ah,0
		invoke printf, CStr("int 67h, ax=DE01 failed, ah=%X",lf),ax
	.endif
	mov ax,0DE03h		;num free 4K pages
	int 67h
	cmp ah,00
	jz @F
	mov al,ah
	mov ah,0
	invoke printf, CStr("int 67h, ax=DE03 failed, ah=%X",lf),ax
	jmp _de02
@@:
	invoke printf, CStr("free 4K pages: %lu",lf),edx
_de02:
	mov ax,0DE02h		;maxAddr of a 4K page
	int 67h
	cmp ah,0
	jz @F
	mov al,ah
	mov ah,0
	invoke printf, CStr("int 67h, ax=DE02 failed, ah=%X",lf),ax
	jmp _de0a
@@:
	invoke printf, CStr("highest address of pages: %lX",lf),edx
_de0a:
	mov ax,0DE0Ah		;get interrupt vector mappings
	int 67h
	cmp ah,0
	jz @F
	mov al,ah
	mov ah,0
	invoke printf, CStr("int 67h, ax=DE0A failed, ah=%X",lf)
	jmp exit
@@:
	invoke printf, CStr("master/slave PIC base: %02X/%02X",lf),bx,cx
exit:
	mov dx,[handle]
	cmp dx,0000
	jz @F
	mov ax,4500h		;release EMS page
	call intrt
@@:
	ret
vcpi endp

;--- BX = handle
;--- CX = size

read0 proc
	push cx
	invoke printf, CStr("read IOCTL device [")
	mov al, [buffer]
	mov ah,0
	invoke printf, CStr("%X"),ax
	invoke printf, CStr("]=")
	pop cx
	mov dx, offset buffer
	mov ax,4402h
	int 21h
	.if (CARRY?)
		invoke printf, CStr(" failed",lf)
		stc
	.else
		invoke printf, CStr(" ok (AX=%X):"),ax
		clc
	.endif
	ret
read0 endp

;--- display EMMXXXX0 device info

deviceinfo proc
	mov dx,offset emsstr1
	mov ax,3D00h
	int 21h
	.if (CARRY?)
		invoke printf, CStr("open device EMMXXXX0 failed",lf)
		mov dx,offset emsstr2
		mov ax,3D00h
		int 21h
		.if (CARRY?)
			invoke printf, CStr("open device EMMQXXX0 failed",lf)
			mov dx,offset emsstr3
			mov ax,3D00h
			int 21h
			.if (CARRY?)
				invoke printf, CStr("open device EMMXXXQ0 failed",lf)
				jmp exit
			.endif
		.endif
	.endif
	push ax
	push dx
	invoke printf, CStr("open device ")
	pop ax
	invoke printf, ax
	invoke printf, CStr(" ok",lf)
	pop bx
	mov byte ptr [buffer+0], 0
	mov byte ptr [buffer+1], -1
	mov dword ptr [buffer+2], -1
	mov cx,6
	call read0
	.if (!CARRY?)
		mov ax, word ptr [buffer+0]
		mov cx, word ptr [buffer+2]
		mov dx, word ptr [buffer+4]
		invoke printf, CStr("%X %X %X",lf),ax,cx,dx
	.endif
	mov byte ptr [buffer+0], 2
	mov byte ptr [buffer+1], -1
	mov cx,2
	call read0
	.if (!CARRY?)
		movzx ax, [buffer+0]
		movzx cx, [buffer+1]
		invoke printf, CStr("%u.%u",lf),ax,cx
	.endif
	mov ah, 3Eh
	int 21h
exit:
	ret
deviceinfo endp

start:
	push sp
	pop ax
	cmp ax,sp	;8086?
	jnz exit	;exit silently
	pushf
	pushf
	pop ax
	or ah,70h
	push ax
	popf
	pushf
	pop ax
	popf
	and ah,0f0h ;if bits 12-14 are 0, it is a 80286
	jz exit 	;Z if 80286
	push cs
	pop ds
	mov ax,ss
	mov bx,sp
	shr bx,4
	add bx,ax
	mov ax,es
	sub bx,ax
	mov ah,4Ah
	int 21h
	sub bx,10h
	shl bx,4
	push ds
	pop ss
	mov sp,bx

	mov di,offset namtab	;clear BSS+stack
	push es
	push ds
	pop es
	mov cx,sp
	sub cx,di
	xor ax,ax
	shr cx,1
	cld
	rep stosw
	pop es

	call main
exit:
	mov ah,4Ch
	int 21h

	END start
