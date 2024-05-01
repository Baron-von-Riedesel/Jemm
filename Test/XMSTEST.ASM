
;--- XMSTEST: test xms memory moves
;--- Public Domain.
;--- to be assembled with JWasm or Masm v6.

	.model small
DGROUP group _TEXT	;use tiny model
	.386

	.dosseg
	.stack 2048

cr  equ 13
lf  equ 10

;--- XMS handle table

XMSHT struct
        db ?
bSize   db ?
wHdls   dw ?
dwArray dd ?
XMSHT ends

;--- XMS handle

XMSH struct
bFlags db ? ;flags, see below 
bLocks db ? ;number of locks
dwAddr dd ? ;addr in KB
dwSize dd ? ;size in KB
XMSH ends

XMSF_FREEB  equ 1   ;free block
XMSF_USEDB  equ 2   ;used block
XMSF_FREEH  equ 4   ;free handle

;--- define a string constant

CStr macro string:vararg
local xxx
	.const
xxx db string
	db 0
	.code
	exitm <offset xxx>
	endm

;--- display word decimal

@wordout_d macro number,format
	mov cl,format
	ifidni <number>,<ax>
	else
	  mov ax,number
	endif
	call _wordout_d
	endm

;--- display dword decimal

@dwordout_d macro number,format
	ifnb <number>
		mov ax,word ptr number+0
		mov dx,word ptr number+2
	endif
	mov cl, format
	call _dwordout_d
	endm

	.data

xmsadr    dd 0      ;XMS host call address
dwTotal   dd 0      ;total size EMBs
freehdls  dw 0      ;count free handles
wVersion  dw 0      ;XMS version
bFlags    db 0      ;flags

FL_NOSIZENULL   equ 1
FL_NOUSEDEMBS   equ 2
FL_NOFREEEMBS   equ 4
FL_FREEHANDLES  equ 8

	.code

	assume DS:DGROUP

	include printf.inc

protocol proc
	push bx
	invoke printf, CStr("%s"), dx
	pop ax
	cmp al,0
	jz @F
	mov ah,0
	invoke printf, CStr(" failed, bl=%02X", 10), ax
	ret
@@:
	invoke printf, CStr(" ok",10)
	ret
protocol endp

xms_move struct 
  len           dd  ?       ; block length in bytes
  src_handle    dw  ?       ; source handle
  src_offset    dd  ?       ; offset into source
  dest_handle   dw  ?       ; destination handle
  dest_offset   dd  ?       ; offset into destination
xms_move ends 

;--- test xms move block function

movetest proc

local handle:word
local emm:xms_move

	mov ah,9
	mov dx,64
	mov bl,0
	call [xmsadr]
	cmp bl,0
	jnz failed
	mov handle, dx

;--- test 1

	mov dx,handle
	mov emm.len, 10000
	mov emm.src_handle, dx
	mov emm.src_offset, 0
	mov emm.dest_handle, dx
	mov emm.dest_offset, 10000
	lea si, emm
	mov ah,0bh
	mov bl,0
	call [xmsadr]
	mov dx, CStr("XMS block move, src < dest && src+len < dest")
	call protocol

;--- test 2

	mov dx,handle
	mov emm.len, 20000
	mov emm.src_handle, dx
	mov emm.src_offset, 0
	mov emm.dest_handle, dx
	mov emm.dest_offset, 10000
	lea si, emm
	mov ah,0bh
	mov bl,0
	call [xmsadr]
	mov dx, CStr("XMS block move, src < dest && src+len > dest")
	call protocol

;--- test 3

	mov dx,handle
	mov emm.len, 10000
	mov emm.src_handle, dx
	mov emm.src_offset, 10000
	mov emm.dest_handle, dx
	mov emm.dest_offset, 0
	lea si, emm
	mov ah,0bh
	mov bl,0
	call [xmsadr]
	mov dx, CStr("XMS block move, src > dest && src > dest+len")
	call protocol

;--- test 4

	mov dx,handle
	mov emm.len, 20000
	mov emm.src_handle, dx
	mov emm.src_offset, 10000
	mov emm.dest_handle, dx
	mov emm.dest_offset, 0
	lea si, emm
	mov ah,0bh
	mov bl,0
	call [xmsadr]
	mov dx, CStr("XMS block move, src > dest && src < dest+len")
	call protocol

	mov dx,handle
	mov ah,0ah
	mov bl,0
	call [xmsadr]
	ret
failed:
	invoke printf, CStr("XMS call AH=08 failed",lf)
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
	invoke printf, CStr("XMS call address: %X:%X",10),
		word ptr [xmsadr+2], word ptr [xmsadr+0]

	call movetest

exit:
	ret
main    endp

;--- init

start   proc

	push cs
	pop ds

	mov cx,es
	mov ax,ss
	sub ax,cx
	shl ax,4
	add ax,sp
	push cs
	pop ss
	mov sp,ax

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
