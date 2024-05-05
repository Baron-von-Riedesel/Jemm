
;--- test FD read in UMB
;--- using Int 13h

	.286
	.model small
	.stack 2048
	.dosseg
	.386

?SIZE equ 1000h

CStr macro text:vararg
local sym
	.const
sym db text,0
	.code
	exitm <offset sym>
endm

lf equ 10

	.code

	include printf.inc

writefile proc c pName:ptr, pBuffer:ptr far16, wSize:word
	mov dx, pName
	xor cx, cx
	mov ax,3c00h
	int 21h
	jc fail1
	mov bx, ax
	push ds
	lds dx, pBuffer
	mov cx, wSize
	mov ax, 4000h
	int 21h
	pop ds
	jc fail2
	mov ah, 3Eh
	int 21h
	ret
fail1:
	invoke printf, CStr("create file failed",10)
	ret
fail2:
	invoke printf, CStr("write file failed",10)
	ret
writefile endp

main proc c

local stat1:word
local stat2:word
local wSeg:word

	mov ax, 5802h		;get status umb
	int 21h
	xor ah,ah
	mov stat1, ax

	mov ax, 5800h		;get memory alloc strategy
	int 21h
	xor ah,ah
	mov stat2, ax

	mov bx, 81h			;first high,then low
	mov ax, 5801h		;set memory alloc strat
	int 21h
	mov bx, 1			;include umbs
	mov ax, 5803h		;umb link restore
	int 21h

	mov bx, ?SIZE shr 4	; allocate mem block
	mov ah, 48h
	int 21h
	jc exit
	mov wSeg, ax

	mov es, ax
	xor di, di
	mov cx, ?SIZE
	mov al, 00
	rep stosb

	push es
	mov es, wSeg		; es:bx=transfer buffer
	mov bx, 0
	mov cx, 1			; cl[0-5]: sector#; ch+cl[6-7]:cylinder
	mov dh, 0			; dh=head
	mov dl, 0			; dl=0 -> A:
	mov ax, 0200h or (?SIZE shr 9)	; al=# of sectors to read
	int 13h
	pop es
	jc error
	invoke printf, CStr("reading drive A: ok",10)
	mov ax, wSeg
	invoke writefile, CStr("~XXX.TMP"), ax::bx, (?SIZE shr 9)*200h
	jmp exit
error:
	movzx ax, ah
	invoke printf, CStr("reading drive A: failed, error code=%X",10), ax
exit:
	mov bx, stat1
	mov ax, 5803h
	int 21h
	mov bx, stat2
	mov ax, 5801h		; set memory alloc strag
	int 21h
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
