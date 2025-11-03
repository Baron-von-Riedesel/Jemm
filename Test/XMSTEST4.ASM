
;--- XMSTEST4: test block resize (shrink)
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

	assume DS:DGROUP

	include printf.inc

;--- test xms block resize function

testproc proc

local handle:word

;--- allocate XMS block

	mov edx, 10000h	;64MB
	mov ah,89h
	call [xmsadr]
	mov handle, dx
	push ax
	invoke printf, CStr("xms alloc (ah=89h) of 64MB returned ax=%X, dx=%X",lf), ax, dx
	pop ax
	cmp ax,1
	jnz failed

;--- lock XMS block

	mov dx, handle
	mov ah,0Ch
	call [xmsadr]
	push ax
        invoke printf, CStr("xms lock (ah=0Ch) returned ax=%X, dx:bx=%X%04X",lf), ax, dx, bx
	pop ax
	cmp ax,1
	jnz failed2

;--- resize block; should fail since locked

	mov ebx, 8000h	;shrink block to 32MB
	mov dx, handle
	mov ah,8Fh
	call [xmsadr]
	mov bh,0
	invoke printf, CStr("xms resize (ah=8Fh) to 32MB returned ax=%X, bl=%X",lf), ax, bx

;--- unlock XMS block

	mov dx, handle
	mov ah,0Dh
	call [xmsadr]
	invoke printf, CStr("xms unlock (ah=0Dh) returned ax=%X",lf), ax

failed2:
;--- free xms handle
	mov dx,handle
	mov ah,0ah
	mov bl,0
	call [xmsadr]
	invoke printf, CStr("xms release (ah=0Ah) returned ax=%X",lf), ax
failed:
	ret
testproc endp

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
	invoke printf, CStr("XMS call address: %X:%X",lf),
		word ptr [xmsadr+2], word ptr [xmsadr+0]

	call testproc

exit:
	ret
main    endp

;--- init

start   proc

	mov ax,@data
	mov ds,ax

	mov cx,ds
	mov ax,ss
	sub ax,cx
	shl ax,4
	add ax,sp
	push ds
	pop ss
	mov sp,ax

;--- free DOS mem
	mov ax, ds
	mov cx, es
	sub ax, cx
	mov bx, sp
	add bx, 15
	shr bx, 4
	add bx, ax
	mov ah, 4Ah
	int 21h

	pushf
	pushf
	pop ax
	or	ah,70h			;a 80386 will have bit 15 cleared
	push ax 			;if bits 12-14 are 0, it is a 80286
	popf				;or a bad emulation
	pushf
	pop ax
	popf
	and ah,0f0h
	js no386			;bit 15 set? then its a 8086/80186
	jnz is386
no386:
	invoke printf, CStr("a 80386 is needed",lf)
	jmp done
is386:
	call main
done:
	mov ah,4Ch
	int 21h
start   endp

	END start
