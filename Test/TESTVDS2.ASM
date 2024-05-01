
;--- VDS API test; test disable/enable auto DMA translation (810B/810C)

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

local	channel:word

	xor ax, ax
	mov es, ax
	test byte ptr es:[47bh],20h
	jz novds
	mov ax,8102h
	mov dx,0000
	int 4bh
	jnc @F
novds:
	invoke printf, CStr("VDS not installed",lf)
	jmp exit
@@:

;--- disable DMA translation for channel 2

	mov channel, 2
nextchannel:
	mov dx, 0
	mov bx, channel
	mov ax,810Bh
	int 4bh
	.if (CARRY?)
		cbw
		invoke printf, CStr("int 4B, ax=810Bh, BX=%u failed, AL=%X",lf), bx, ax
	.else
		invoke printf, CStr("int 4B, ax=810Bh, BX=%u ok",lf), bx
	.endif

;--- reenable DMA translation

	mov dx, 0
	mov bx, channel
	mov ax,810Ch
	int 4bh
	setz cl
	.if (CARRY?)
		cbw
		invoke printf, CStr("int 4B, ax=810Ch, BX=%u failed, AL=%X",lf), bx, ax
	.else
		invoke printf, CStr("int 4B, ax=810Ch, BX=%u ok (ZF=%u)",lf), bx, cl
	.endif

;--- the second call should fail!

	mov dx, 0
	mov bx, channel
	mov ax,810Ch
	int 4bh
	setz cl
	.if (CARRY?)
		cbw
		invoke printf, CStr("int 4B, ax=810Ch, BX=%u failed, AL=%X",lf), bx, ax
	.else
		invoke printf, CStr("int 4B, ax=810Ch, BX=%u ok (ZF=%u)",lf), bx, cl
	.endif

	inc channel
	cmp channel, 4
	jb nextchannel

exit:
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
