
;*** test EMS get/set page map 

	.286
	.model small
	option casemap:none
	.stack 1024
	.dosseg
	.386

CStr macro text:vararg
local sym
	.const
sym db text,0
	.code
	exitm <offset sym>
endm

lf equ 10

	.data
mapstruct label byte
	dw 4
	dw 0A000h
	dw 0A400h
	dw 0A800h
	dw 0AC00h

	.data?

buffer	db 256 dup (?)

	.code

	include printf.inc

emsstr1 db 'EMMXXXX0',0

EMScheck proc uses si di

	mov ax, 3567h
	int 21h
	mov ax, es
	or  ax, bx
	jz  exit

	mov dx,1
	mov si,offset emsstr1
	mov di,000ah
	mov cx,8
	push ds
	push cs
	pop ds
	cld
	repz cmpsb
	pop ds
	jz  found

	mov dx,0
	mov ah,46h
	int 67h
	and ah,ah
	jz  found

	xor ax, ax
	jmp exit
found:
	mov ax,1
exit:
	ret

EMScheck endp

main proc c

local handle:word

	call EMScheck
	and ax,ax
	jz sm1

	mov ax,4E03h
	int 67h
	cmp ah,00
	jnz sm2
	invoke printf, CStr("size to save all pages: %u",lf), ax

	mov di,offset buffer
	push ds
	pop es
	mov ax,4E00h
	int 67h
	cmp ah,00
	jnz sm3

	mov si,offset buffer
	mov ax,4E01h
	int 67h
	cmp ah,00
	jnz sm4
	invoke printf, CStr("Ok",lf)
	jmp exit

sm1:
	invoke printf, CStr("EMM not found",lf)
	jmp exit
sm2:
	movzx ax,ah
	invoke printf, CStr("int 67h, ax=4E03h failed, ah=%X",lf),ax
	jmp exit
sm3:
	movzx ax,ah
	invoke printf, CStr("int 67h, ax=4E00h failed, ah=%X",lf),ax
	jmp exit
sm4:
	movzx ax,ah
	invoke printf, CStr("int 67h, ax=4E01h failed, ah=%X",lf),ax
exit:
	ret
main endp

start:
	mov ax,@data
	mov ds,ax
	mov cx,ss
	sub cx,ax
	shl cx,4
	mov ss,ax
	add sp,cx
	invoke main
	mov ah,4ch
	int 21h

	END start
