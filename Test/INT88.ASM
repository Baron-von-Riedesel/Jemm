
;--- test int# >= 0x80;
;--- the monitor program uses the "PUSH byte const" instruction
;--- to push a sign-extended value as int#; so it has to carefully
;--- use the lowest byte only.

	.286
	.model tiny
	.stack 256
	.dosseg
	option casemap:none

CStr macro text:vararg
local sym
	.const
sym db text,0
	.code
	exitm <offset sym>
endm

	.data

oldint88 dd 0

	.code

	.386
	include printf.inc
	.286

myint88 proc
	invoke printf, CStr("inside int 88h, ax=%X bx=%X cx=%X dx=%X si=%X di=%X bp=%X",10), ax, bx, cx, dx, si, di, bp
	iret
myint88 endp

start:
	mov ax,cs
	mov ds,ax
	mov ax,3588h
	int 21h
	mov word ptr [oldint88+0],bx
	mov word ptr [oldint88+2],es
	mov dx, offset myint88
	mov ax,2588h
	int 21h

	mov ax,0
	mov bx,1
	mov cx,2
	mov dx,3
	mov si,4
	mov di,5
	mov bp,6
	int 88h

	lds dx, [oldint88]
	mov ax, 2588h
	int 21h

	mov ax, 4c00h
	int 21h

	END start
