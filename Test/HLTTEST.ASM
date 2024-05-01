
;*** HLT test (v86)

	.286
	.model small
	.stack 2048
	.dosseg
	.386

	include macros.inc

	.data

bM21	db 0
bIrq	db 0

	.code

dwOldInt9 dd 0
cIrq	db 0

myint9 proc
	inc cs:[cIrq]
	jmp cs:[dwOldInt9]
myint9 endp

	include printf.inc

main proc c

local	mblock:word

	mov ecx,200000000
@@:
	dec ecx
	jnz @B
@@:
	mov ah,1
	int 16h
	jz @F
	mov ah,0
	int 16h
	jmp @B
@@:
	mov ax,3509h
	int 21h
	mov word ptr cs:dwOldInt9+0,bx
	mov word ptr cs:dwOldInt9+2,es
	push ds
	push cs
	pop ds
	mov dx, offset myint9
	mov ax,2509h
	int 21h
	pop ds

	in al, 21h
	mov bM21, al
	mov al, 0FDh
	out 21h, al

	mov cs:[cIrq],0

	hlt
	cli
	nop

	mov al, cs:[cIrq]
	mov bIrq,al

	sti

	mov al,bM21
	out 21h,al

	push ds
	lds dx, cs:dwOldInt9
	mov ax,2509h
	int 21h
	pop ds

	mov al,bIrq
	mov ah,0
	invoke printf, CStr(<"%u interrupts counted",10>),ax

	ret
main endp

start:
	mov ax, @data
	mov ds, ax
	mov bx, ss
	sub bx, ax
	shl bx, 4
	mov ss, ax
	add sp, bx
	call main
	mov ah, 4Ch
	int 21h

	END start
