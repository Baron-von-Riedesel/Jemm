
;--- MOVEXBDA moves XBDA to low memory. If the XBDA is already moved
;--- or if it is too large, nothing is done.
;--- MOVEXBDA hooks interrupt 19h and will restore the XBDA to its
;--- previous location if this interrupt is called.
;--- MOVEXBDA is Public Domain.

	.286
	.model small
DGROUP group _TEXT

ifndef MAXXBDA
MAXXBDA equ 4		;max size of XBDA in KB
endif
XBDAADR equ 000Eh	;address of XBDA segment in BIOS data region
MEMSIZE equ 0013h	;size of memory in kB in BIOS data region
?WELCOME equ 0		;display message at start

MCB struct
sig   db ?
psp   dw ?
_size dw ?
MCB ends

XBDA struct
_size db ? ;size of XBDA in KB
XBDA ends

IODAT   struct
cmdlen	db ?
unit	db ?
cmd 	db ?
status	dw ?
		db 8 dup (?)
media	db ?
trans	dd ?
count	dw ?	;+ 12 init:offset parameter line
start	dw ?	;+ 14 init:segment parameter line
drive	db ?
IODAT   ends

	.code

	dw -1
	dw -1
	dw 8000h				  ;attribute
	dw offset devstrat		  ;device strategy
intproc dw offset devintfirst	  ;device interrupt
devname db 'MOVXBDA#'

cmdptr  dd 1 dup (?)
oldint19 dd ?

devstrat proc far
	mov cs:word ptr[cmdptr],bx
	mov cs:word ptr[cmdptr+2],es
	ret
devstrat endp

devint proc far
	push bx
	push ds
	lds bx,cs:[cmdptr]
	mov word ptr [bx.IODAT.status],8103h
	pop ds
	pop bx
	ret
devint endp

;--- restore XBDA to above low mem

myint19 proc
	push ds
	push 40h
	pop ds
	mov es,ds:[XBDAADR]
	mov di,ds:[MEMSIZE]
	shl di,6    ;convert KB to PARA
	mov cl,es:[XBDA._size]
	mov ch,0
	sub ds:[MEMSIZE],cx
	push cx
	shl cx,6    ;convert KB to PARAs
	sub di,cx
	mov ds:[XBDAADR],di
	push es
	pop ds
	mov es,di
	pop cx
	xor di,di
	xor si,si
	shl cx,9	;convert KB to WORDs
	rep movsw
	mov ds,cx   ;ds=0000
	.386
	mov eax, cs:[oldint19]
	mov ds:[19h*4],eax
	pop ds
	push eax
	.286
	retf
myint19 endp

copyandexit:
	rep movsw
	pop es
	pop ds
	popa
	retf

endres equ $

devintfirst proc far
	pusha
	push ds
	push es
	lds bx,cs:[cmdptr]
	mov al,[bx.IODAT.cmd]
	mov word ptr [bx.IODAT.status],100h
	cmp al,00			;init call?
	jnz exit
if ?WELCOME
	push ds
	push cs
	pop ds
	mov dx,offset dWelcome
	mov ah,9
	int 21h
	pop ds
endif
	mov word ptr [bx].IODAT.trans+0,0000
	mov word ptr [bx].IODAT.trans+2,cs
	mov cs:[intproc], offset devint

;--- scan for option /A
	xor bp,bp
	lds si,dword ptr [bx].IODAT.count
@@:
	lodsb
	cmp al,' '
	jnz @B
@@:
	lodsb
	cmp al,' '
	jz @B
	mov ah,al
	lodsb
	or al,20h
	cmp ax,"/a"	;/A option given?
	jnz @F
	inc bp      ;set flag for option /A
@@:

	push 40h
	pop es
	mov ax,es:[XBDAADR]	;check if XBDA is just above low memory
	mov dx,es:[MEMSIZE]
	shl dx,6    ;convert KB to PARA
	cmp ax,dx	;is xbda just above conv memory?
	jnz err1	;if no, display msg and do nothing
	mov ds,ax
	mov al,ds:[XBDA._size]
	mov ah,0

;--- get new XBDA address
	mov cx,offset endres
	add cx,15
	and cl,0F0h
	shr cx,4
	mov dx,cs
	add dx,cx
	cmp bp,0
	jz @F
	add dx,3Fh
	and dx,0FFC0h
@@:

;--- adjust BIOS variables 040Eh and 0413h

	mov es:[XBDAADR],dx
	add word ptr es:[MEMSIZE],ax

	pusha

;--- increase the last DOS MCB

	mov ah,52h
	int 21h
	mov si,es:[bx-2]
nextitem:
	mov es, si
	mov dx, es:[MCB._size]	;get size of MCB
	inc dx
	add dx, si		;dx = next block
	cmp byte ptr es:[MCB.sig], 'M'
	jnz @F
	mov si, dx
	jmp nextitem
@@:
	popa
	mov cx,ax
	shl cx,6	;convert kB to para
	add es:[MCB._size],cx

	push ds

;--- tell DOS the amount of driver's memory to keep resident

	mov di,ax
	mov si,dx

	shl ax,10	;convert kb to byte
	mov cx,cs
	sub dx,cx
	shl dx,4
	add dx,ax
	lds bx,cs:[cmdptr]
	mov word ptr [bx].IODAT.trans+0,dx

;--- hook int 19h

	push 0
	pop ds
	.386
	push cs
	push offset myint19
	pop eax
	xchg eax,ds:[19h*4]
	mov cs:[oldint19],eax
	.286

	pop ds

	mov es,si
	mov cx,di

;--- move contents of XBDA
;--- cx=size in kB
;--- ds=old XBDA
;--- es=new XBDA

	xor si,si
	xor di,di
	shl cx,9	;convert KB to WORD
	jmp copyandexit
exit:
	pop es
	pop ds
	popa
	ret
err1:
	mov dx,offset derr1
	jmp @F
err2:
	mov dx,offset derr2
@@:
	push cs
	pop ds
	mov ah,9
	int 21h
	jmp exit
devintfirst endp

derr1 db "XBDA not at the end of low memory",13,10,'$'
derr2 db "XBDA too large",13,10,'$'
dWelcome db "MOVEXBDA starting",13,10,'$'

str1 db "MOVEXBDA moves XBDA to low memory. Must be run before UMBs were provided to DOS.",13,10
	db "Usage: DEVICE=MOVEXBDA.EXE [/A]",13,10
	db "Optional parameter /A will align the XBDA to a kB boundary, which is",13,10
	db "required by some BIOSes.",13,10
	db '$'

main:
	mov dx,offset str1
	push cs
	pop ds
	mov ah,9
	int 21h
	mov ax,4C00h
	int 21h

_TEXT ends

STACK segment stack 'STACK'
	db 400h dup (?)
STACK ends

	END main
