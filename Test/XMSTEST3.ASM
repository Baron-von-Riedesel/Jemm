
;--- test ah=0Eh (get handle info)
;--- Public Domain.
;--- to be assembled with JWasm or Masm v6.

	.model small
	.386
	.dosseg
	.stack 2048

cr  equ 13
lf  equ 10

BUFFSIZ equ 10000h

;--- define a string constant

CStr macro string:vararg
local xxx
	.const
xxx db string
	db 0
	.code
	exitm <offset xxx>
endm

	.data

xmsadr dd 0      ;XMS host call address

	.code

	include printf.inc

runtest proc

local handle:word
local dwSize:dword

	mov edx,10000h   ;allocate 65536 kB
	call runtest1
	mov edx,0ffffh   ;allocate 65535 kB
	call runtest1
	ret
runtest1:
	mov dwSize,edx
	mov ah,89h       ;alloc ext. memory block (size EDX)
	mov bl,0
	call [xmsadr]
	cmp ax,1
	jz @F
	invoke printf, CStr("xms function 89h failed (bl=%X, edx=%lX)",lf), bl, edx
	jmp failed
@@:
	mov handle,dx
	invoke printf, CStr("xms function 89h(size %lu kB): dx=%X",lf), dwSize, dx

;--- function 0Eh should fail, since size doesn't fit in 16-bit register
	mov edx,12340000h	;set hiword(edx) to a known value
	mov dx,handle
	mov bx,0            ;set bx to a known value
	mov ah,0eh          ;get handle info (v2)
	call [xmsadr]
	invoke printf, CStr("xms function 0Eh: ax=%X, bx=%X, edx=%lX",lf), ax, bx, edx

;--- function 8Eh should succeed
	mov edx,12340000h	;set hiword(edx) to a known value
	mov dx,handle
	mov bx,0            ;set bx to a known value
	mov ah,8eh          ;get handle info (v3)
	call [xmsadr]
	invoke printf, CStr("xms function 8Eh: ax=%X, bx=%X, edx=%lX",lf), ax, bx, edx

	mov dx,handle
	mov ah,0ah          ;free handle
	call [xmsadr]
failed:
	retn
runtest endp

;--- main

main    proc c

	mov ax,4300h
	int 2fh
	test al,80h 		 ;xms host found?
	jnz main1
	invoke printf, CStr("no XMS host found",lf)
	jmp exit
main1:
	mov ax,4310h		;get XMS call address
	int 2fh
	mov word ptr xmsadr+0,bx
	mov word ptr xmsadr+2,es
;	invoke printf, CStr("XMS call address: %X:%X",lf),word ptr [xmsadr+2],word ptr [xmsadr+0]
	call runtest
exit:
	ret
main    endp

;--- init

start   proc

	mov ax,@data
	mov ds,ax
	mov cx,ss
	sub cx,ax
	shl cx,4
	mov ss,ax
	add sp,cx
	call main
	mov ah,4Ch
	int 21h
start   endp

	END start
