
;--- test FD read in UMB

	.286
	.model small
	.stack 2048
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

	.code

	include printf.inc

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


	mov bx, 100h		; allocate 4 kB
	mov ah, 48h
	int 21h
	jc exit
	mov wSeg, ax

	mov es, ax
	xor di, di
	mov cx, 1000h
	mov al, 00
	rep stosb

	push ds
	mov ds, wSeg		; ds:bx=transfer buffer
	mov bx, 0
	mov cx, 8			; 8 sectors to read
	mov al, 0			; al=0 -> A:
	mov dx, 0			; start sector #
	int 25h
	jc error
	add sp, 2
	pop ds
	invoke printf, CStr("reading drive A: ok",10)
	jmp exit
error:
	add sp, 2
	pop ds
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
