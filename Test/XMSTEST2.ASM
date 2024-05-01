
;--- XMSTEST: test max block allocation
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

xms_move struct
  len           dd  ?       ; block length in bytes
  src_handle    dw  ?       ; source handle
  src_offset    dd  ?       ; offset into source
  dest_handle   dw  ?       ; destination handle
  dest_offset   dd  ?       ; offset into destination
xms_move ends

	.data

xmsadr dd 0      ;XMS host call address

	.code

	assume DS:DGROUP

	include printf.inc

;--- test xms move block function

movetest proc

local handle:word
local maxmem:dword
local buffer:word
local emm:xms_move

;--- allocate DOS memory block
	mov ah,48h
	mov bx,BUFFSIZ / 16
	int 21h
	jnc @F
	invoke printf, CStr("not enough DOS memory",lf)
	jmp failed
@@:
	mov buffer, ax

;--- allocate XMS block
	mov ah,88h	;query free xms mem
	mov bl,0
	call [xmsadr]
	mov maxmem, eax
	mov bh,0
	push bx
	invoke printf, CStr("xms function 88h returned bl=%X, eax=%lX",lf), bx, eax
	pop bx
	cmp bl,0
	jnz failed

	mov edx, maxmem
	mov ah,89h
	mov bl,0
	call [xmsadr]
	mov handle, dx
	mov bh,0
	push bx
	invoke printf, CStr("xms function 89h returned bl=%X, dx=%X",lf), bx, dx
	pop bx
	cmp bl,0
	jnz failed

;--- test 1

	cld
	mov es, buffer
	mov di, 0
	mov cx, BUFFSIZ / 4
	mov eax, 0deadbabeh
	rep stosd

	mov emm.len, BUFFSIZ
	mov emm.src_handle, 0
	mov word ptr emm.src_offset+0, 0
	mov word ptr emm.src_offset+2, es
	mov ax, handle
	mov emm.dest_handle, ax
	mov emm.dest_offset, 0
	mov edi, maxmem
	shl edi, 10		;kB -> byte
	.while edi
		mov dx,handle
		lea si, emm	;ds:si->xms move struct
		mov ah,0bh
		mov bl,0
		call [xmsadr]
		push ax
		invoke printf, CStr("XMS block move, ax=%u, dest ofs=%lX",13), ax, emm.dest_offset
		pop ax
		.break .if ax == 0
		add emm.dest_offset, BUFFSIZ
		.if edi > BUFFSIZ
			sub edi, BUFFSIZ
		.else
			mov emm.len, edi
			xor edi, edi
		.endif
	.endw
	invoke printf, CStr(10)

;--- free xms handle
	mov dx,handle
	mov ah,0ah
	mov bl,0
	call [xmsadr]
failed:
	ret
movetest endp

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

	call movetest

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
