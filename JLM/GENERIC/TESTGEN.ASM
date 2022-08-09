
;--- test app which calls some "services" of JLM GENERIC.
;--- assemble: JWasm -bin -Fo testgen.com testgen.asm

	.model tiny

	.data

szOK    db "GENERIC found!",13,10,'$'
szError db "GENERIC is NOT installed!",13,10,'$'

	.code

	org 100h

start:
	mov ax, 1684h	;get GENERIC's entry point
	mov bx, 6660h
	int 2Fh
	cmp al,0
	jnz not_installed
	push es
	push di
	mov bp,sp
	mov dx,offset szOk
	mov ah,9
	int 21h
	mov ax,0000     ;call "get version"
	call dword ptr [bp]
	mov ax,0001     ;call "display hello"
	call dword ptr [bp]
	add sp,4
	int 20h
not_installed:
	mov dx,offset szError
	mov ah,9
	int 21h
	int 20h

	end start

