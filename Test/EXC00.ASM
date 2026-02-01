
;*** EXC 00

	.286
	.model small
	.stack 2048
	.dosseg
	.386

	.code

start:
	mov dx, -1
	mov cx, 8000h
	div cx
	mov ah, 4Ch
	int 21h

	END start
