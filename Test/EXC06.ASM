
;*** EXC 06 - requires a P6+ cpu

	.286
	.model small
	.stack 2048
	.dosseg
	.686

	.code

start:
	ud2
	mov ah, 4Ch
	int 21h

	END start
