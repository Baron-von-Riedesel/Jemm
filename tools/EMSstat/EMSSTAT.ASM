
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

CStr macro string
local xxx
CONST segment
xxx db string
	db 0
CONST ends
	exitm <offset xxx>
	endm

;--- display word decimal

@wordout_d macro number,format
	mov cl,format
	ifidni <number>,<ax>
	else
	  mov ax,number
	endif
	call _wordout_d
	endm

;--- display dword decimal

@dwordout_d macro number,format
	ifnb <number>
		mov ax,word ptr number+0
		mov dx,word ptr number+2
	endif
	mov cl, format
	call _dwordout_d
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

_putchr proc stdcall char:word
	push dx
	push ax
	mov dx,char
	mov ah,2
	int 21h
	pop ax
	pop dx
	ret
_putchr endp

;--- display a string constant

_strout proc stdcall uses si pText:ptr
	mov si,pText
nextitem:
	lodsb
	and al,al
	jz exit
	cmp al,10
	jnz @F
	invoke _putchr, 13
	mov al,10
@@:
	invoke _putchr, ax
	jmp nextitem
exit:
	ret
_strout endp

;--- display a EOL

_crout proc
	invoke _strout, CStr(<lf>)
	ret
_crout endp

;--- display word in AX decimal
;--- min. number of chars in CL

_wordout_d proc
	xor dx,dx
;	jmp _dwordout_d
_wordout_d endp ;fall thru!

;--- display dword in DX:AX decimal
;--- min. number of chars in CL

_dwordout_d proc c

	pusha
	mov bl,cl
	mov si,offset tab1
	mov bh,00
	mov ch,10			;max cnt of digits
nextdigit:
	mov cl,'0' - 1
@@:
	inc cl
	sub ax,cs:[si + 0]
	sbb dx,cs:[si + 2]
	jnc @B
	add ax,cs:[si + 0]
	adc dx,cs:[si + 2]
	add si,4
	cmp cl,'0'			;current digit
	jnz @F
	cmp ch,1			;format
	jz @F
	cmp bh,00			;number of digits displayed
	jz skipdigit
@@:
	and bh,bh
	jnz prefdone
	sub bl,ch
	jna prefdone
@@:
	invoke _putchr, ' '
	dec bl
	jnz @B
prefdone:
	invoke _putchr, cx
	inc bh
skipdigit:
	dec ch
	jnz nextdigit
	popa
	ret

	align 2
tab1 dd 1000000000,100000000,10000000,1000000,100000,10000,1000,100,10,1

_dwordout_d endp

;--- display DWORD/WORD/BYTE in EAX/AX/AL hexadecimal

_dwordout:
	push eax
	shr eax,16
	call _wordout
	pop eax
_wordout:
	push ax
	mov al,ah
	call _byteout
	pop ax
_byteout:
	push ax
	shr al,4
	call _nibout
	pop ax
_nibout:
	and al,0Fh
	add al,'0'
	cmp al,'9'
	jbe @F
	add al,7
@@:
	invoke _putchr, ax
	ret

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
	invoke _strout, CStr(<"EMM installed, but NOEMS, device name=">)
	mov bx,10
	mov cx,8
@@:
	mov al,es:[bx]
	invoke _putchr,ax
	inc bx
	loop @B
	invoke _crout
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
	invoke _strout, CStr(<"usage: EMSSTAT [ options ]",lf>)
	invoke _strout, CStr(<"options are:",lf>)
	invoke _strout, CStr(<"    -p: display physical pages",lf>)
	invoke _strout, CStr(<"    -v: display VCPI info",lf>)
	invoke _strout, CStr(<"    -d: try to open devices EMMXXXX0 or EMMQXXX0",lf>)
	stc
	ret
getpar endp

;--- ES=PSP

main	proc c

	call getpar
	jc exit

	call EMScheck
	and ax,ax
	jnz @F
	invoke _strout, CStr(<"EMM not found",lf>)
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

	invoke _strout, CStr(<"EMS version: ">)
	mov ax,[si+2]
	call _byteout
	call _crout
	invoke _strout, CStr(<'16 kB pages total/free: '>)
	mov ax,[si+3]
	@wordout_d ax,1
	invoke _putchr, '/'
	mov ax,[si+5]
	@wordout_d ax,1
	invoke _strout, CStr(<" ",28h>)
	mov ax,[si+11]
	mov dx,[si+13]
	@dwordout_d ,1
	invoke	_putchr, '/'
	mov ax,[si+19]
	mov dx,[si+21]
	@dwordout_d ,1
	invoke _strout, CStr(<" kB",29h>)
	call _crout
	invoke _strout, CStr(<'EMS page frame: '>)
	mov ax,  [si+0]
	call _wordout
	call _crout
	invoke _strout, CStr(<'Active handles: '>)
	mov ax,  [si+7]
	@wordout_d ax,1
	call _crout
	invoke _strout, CStr(<'physical pages: '>)
	mov ax,  [si+17]
	@wordout_d ax,1
	call _crout

	mov ax,5900h
	lea di,[si+23]
	push ds
	pop es
	int 67h
	and ah,ah
	jz ems59
	invoke _strout, CStr(<"int 67h, ax=5900h (get EM hardware information) failed, status=">)
	mov al,ah
	call _byteout
	call _crout
	jmp ems59done
ems59:
	invoke _strout, CStr(<'Raw pages size: '>)
	mov ax, [si+23]
	shl ax, 4
	@wordout_d ax,1
	call _crout
	invoke _strout, CStr(<'Alternate map register sets: '>)
	mov ax, [si+25]
	@wordout_d ax,1
	call _crout
	invoke _strout, CStr(<'Mapping context size: '>)
	mov ax, [si+27]
	@wordout_d ax,1
	call _crout
	invoke _strout, CStr(<'DMA register sets: '>)
	mov ax, [si+29]
	@wordout_d ax,1
	call _crout
ems59done:
	ret
readd endp

;--- display raw pages

rpages proc
	mov ax,5901h
	int 67h
	cmp ah,0
	jnz exit
	push bx
	push dx
	invoke _strout, CStr(<"raw pages total/free: ">)
	pop ax
	@wordout_d ax,1
	invoke _strout, CStr(<"/">)
	pop ax
	@wordout_d ax,1
	call _crout
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
	invoke _strout, CStr(<"int 67h, ax=5402h (get number of handles) failed, status=">)
	mov al,ah
	call _byteout
	call _crout
	jmp done
@@:
	invoke _strout, CStr(<"(max) size of handle table: ">)
	@wordout_d bx,1
	call _crout

	push ds
	pop es
	mov di,offset buffer
	mov ax,5400h		;get handle directory
	int 67h
	and ah,ah
	jz @F
	invoke _strout, CStr(<"int 67h, ax=5400h (get handle directory) failed, status=">)
	mov al,ah
	call _byteout
	call _crout
	jmp done
@@:
	movzx ax,al
	mov wHandles,ax
	and ax, ax
	jz done
	invoke _strout, CStr(<"Handle Name     Pages     KB",lf>)
	invoke _strout, CStr(<"-----------------------------",lf>)
	mov cx,wHandles
nexthdl:						;<------
	push cx
	mov ax,[di]
	@wordout_d ax,6
	invoke _putchr, ' '

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
	invoke _strout, CStr(<"    ?      ?",lf>)
	jmp invalhdl
@@:
	movzx ebx,bx
	add [totalpg],ebx
	push bx
	@wordout_d bx,5
	pop bx
	mov ax,16
	mul bx
	push dx
	push ax
	pop eax
	add [totalkb],eax
	@dwordout_d ,8
	call _crout
invalhdl:
	pop cx
	add di,10
	loop nexthdl
	invoke _strout, CStr(<"-----------------------------",lf>)
	invoke _strout, CStr(<"               ">)
	mov ax,word ptr [totalpg+0]
	mov dx,word ptr [totalpg+2]
	@dwordout_d ,5
	mov ax,word ptr [totalkb+0]
	mov dx,word ptr [totalkb+2]
	@dwordout_d ,8
	call _crout
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
	invoke _strout, CStr(<"int 67h, ax=5801h (get mappable pages) failed, status=">)
	mov al,ah
	call _byteout
	call _crout
	jmp exit
@@:
	jcxz nopages
	mov numpgs,cx
	mov count,0
	mov di,offset buffer
	push ds
	pop es
	mov ax,5800h				;get mappable physical address array
	int 67h
	cmp ah,00
	jz @F
	invoke _strout, CStr(<"int 67h, ax=5800h (get mappable pages) failed, status=">)
	mov al,ah
	call _byteout
	call _crout
	jmp exit
@@:
	call _crout
	invoke _strout, CStr(<"Segm:Pg Segm:Pg Segm:Pg Segm:Pg",lf>)
	invoke _strout, CStr(<"-------------------------------",lf>)
	xor si,si
ppage3:
	mov ax,si
	call _wordout
	invoke _putchr, ':'
	mov cx,numpgs
	call searchpage
	jc @F
	@wordout_d ax,2
	jmp ppage4
@@:
	invoke _strout, CStr(<"--">)
ppage4:

	invoke _putchr, ' '
	inc count
	test byte ptr count,3
	jnz @F
	call _crout
@@:
	add si,400h
	jnz ppage3
	call _crout
exit:
	ret
nopages:
	invoke _strout, CStr(<"no mappable pages",lf>)
	ret
ppages endp

intrt proc near
	mov fc,ax
	int 67h
	and ah,ah
	jz intrt1
	push ax
	invoke _strout, CStr(<"function:">)
	mov ax,fc
	call _wordout
	invoke _strout, CStr(<" - RC:">)
	pop ax
	push ax
	mov al,ah
	call _byteout
	call _crout
	pop ax
	mov bx,0000
intrt1:
	ret
intrt endp

descout proc near
	mov ah,[di+7]		;base bits 31..24
	mov al,[di+4]		;base bits 23..16
	call _wordout
	mov ax,[di+2]		;base bits 15..0
	call _wordout
	invoke _putchr, ':'
	mov ax,[di+0]		;limit bits 15..0
	call _wordout
	invoke _putchr, ','
	mov ax,[di+5]
	call _wordout
	call _crout
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
	invoke _strout, CStr(<"VCPI not supported",lf>)
	jmp exit
@@:
	invoke _strout, CStr(<"VCPI version: ">)
	mov ax,bx
	call _wordout
	call _crout

	push ds
	pop es
	mov di,offset buffer
	mov si,offset gdttab	;DS:SI -> 3 GDT descriptors
	mov ax,0DE01h			;get protected mode interface
	int 67h
	.if (ah == 0)
		push di
		push ebx
		invoke _strout, CStr(<"offset for protected-mode switch:">)
		pop eax
		call _dwordout
		call	_crout
		invoke _strout, CStr(<"Start free address space: ">)
		pop di
		sub di,offset buffer
		movzx edi,di
		shl edi, 10 	;440h -> 110000
		mov eax, edi
		call _dwordout
		call	_crout
		mov di,offset gdttab
		invoke _strout, CStr(<'1. VCPI descriptor: '>)
		call descout
		invoke _strout, CStr(<'2. VCPI descriptor: '>)
		call descout
		invoke _strout, CStr(<'3. VCPI descriptor: '>)
		call descout
	.else
		invoke _strout, CStr(<"int 67h, ax=DE01 failed, ah=">)
		mov al,ah
		call _byteout
		call _crout
	.endif
	mov ax,0DE03h		;num free 4K pages
	int 67h
	cmp ah,00
	jz @F
	invoke _strout, CStr(<"int 67h, ax=DE03 failed, ah=">)
	mov al,ah
	call _byteout
	call _crout
	jmp _de02
@@:
	push edx
	invoke _strout, CStr(<"free 4K pages: ">)
	pop ax
	pop dx
	@dwordout_d ,1
	call _crout
_de02:
	mov ax,0DE02h		;maxAddr of a 4K page
	int 67h
	cmp ah,0
	jz @F
	invoke _strout, CStr(<"int 67h, ax=DE02 failed, ah=">)
	mov al,ah
	call _byteout
	call _crout
	jmp _de0a
@@:
	push edx
	invoke _strout, CStr(<"highest address of pages:">)
	pop edx
	mov eax,edx
	call _dwordout
	call _crout
_de0a:
	mov ax,0DE0Ah		;get interrupt vector mappings
	int 67h
	cmp ah,0
	jz @F
	invoke _strout, CStr(<"int 67h, ax=DE0A failed, ah=">)
	mov al,ah
	call _byteout
	call _crout
	jmp exit
@@:
	push cx
	push bx
	invoke _strout, CStr(<"master/slave PIC base: ">)
	pop ax
	call _wordout
	invoke _putchr, '/'
	pop ax
	call _wordout
	call _crout
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
	invoke _strout, CStr(<"read IOCTL device [">)
	mov al, [buffer]
	call _byteout
	invoke _strout, CStr(<"]=">)
	pop cx
	mov dx, offset buffer
	mov ax,4402h
	int 21h
	.if (CARRY?)
		invoke _strout, CStr(<" failed",lf>)
		stc
	.else
		invoke _strout, CStr(<" ok ",28h,"AX=">)
		call _wordout
		invoke _strout, CStr(<29h,": ">)
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
		invoke _strout, CStr(<"open device EMMXXXX0 failed",lf>)
		mov dx,offset emsstr2
		mov ax,3D00h
		int 21h
		.if (CARRY?)
			invoke _strout, CStr(<"open device EMMQXXX0 failed",lf>)
			mov dx,offset emsstr3
			mov ax,3D00h
			int 21h
			.if (CARRY?)
				invoke _strout, CStr(<"open device EMMXXXQ0 failed",lf>)
				jmp exit
			.endif
		.endif
	.endif
	push ax
	push dx
	invoke _strout, CStr(<"open device ">)
	pop ax
	invoke _strout, ax
	invoke _strout, CStr(<" ok",lf>)
	pop bx
	mov byte ptr [buffer+0], 0
	mov byte ptr [buffer+1], -1
	mov dword ptr [buffer+2], -1
	mov cx,6
	call read0
	.if (!CARRY?)
		mov ax, word ptr [buffer+0]
		call _wordout
		invoke	_putchr, ' '
		mov ax, word ptr [buffer+2]
		call _wordout
		invoke	_putchr, ' '
		mov ax, word ptr [buffer+4]
		call _wordout
		call _crout
	.endif
	mov byte ptr [buffer+0], 2
	mov byte ptr [buffer+1], -1
	mov cx,2
	call read0
	.if (!CARRY?)
		movzx ax, [buffer+0]
		@wordout_d ax,1
		invoke	_putchr, '.'
		movzx ax, [buffer+1]
		@wordout_d ax,1
		call _crout
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
