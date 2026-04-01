
;--- the EMS handler runs slightly differently if IVT vector 67h is hooked!

	.286
	.model tiny
	.stack 256

	.code

	db 10 dup (0)
	db "EMMXXXX0"

myint67:
	db 0EAh
oldint dd 0

endres equ $

start:
	mov ax, cs
	mov ds, ax
	mov ax, 3567h
	int 21h
	mov word ptr oldint+0, bx
	mov word ptr oldint+2, es
	mov dx, offset myint67
	mov ax, 2567h
	int 21h
	mov dx, offset endres
	add dx, 16-1
	shr dx, 4
	add dx, 10h
	mov ax, 3100h
	int 21h

	END start
