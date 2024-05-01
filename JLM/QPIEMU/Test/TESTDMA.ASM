
;--- test Qemm/QPIEMU ( IO trap part )
;--- this time test ISA DMA ports

	.286
	.model small
	.dosseg
	.stack 1024

PORT equ 0C4h

lf equ 10

CStr macro text:vararg
local sym
	.const
sym db text, 0
	.code
	exitm <offset sym>
endm

	.data

dwQemm dd 0
dwOldIO dd 0
wVersion dw 0

	.code

dataseg dw 0

	.386

	include printf16.inc	; this printf() preserves all registers!

PUSHAS struct
wDI	dw ?
wSI	dw ?
wBP	dw ?
	dw ?
wBX	dw ?
wDX	dw ?
wCX	dw ?
wAX	dw ?
PUSHAS ends

myio proc far
	pusha
	mov bp, sp
	push ds
	mov ds, cs:[dataseg]
	pushf
	invoke printf, CStr("in myio, eax=%lX, bx=%X, cx=%X, dx=%X, ds=%X, cs=%X, ss=%X, fl=%X",10), eax, bx, cx, dx, [bp-2], cs, ss, [bp-4]
	add sp, 2
if 0
	cmp byte ptr [bp].PUSHAS.wCX, 0
	jnz @F
	mov ax, 1A00h			; untrapped read (byte only)
	mov dx, [bp].PUSHAS.wDX
	call [dwQemm]
	mov byte ptr [bp].PUSHAS.wAX, bl
	invoke printf, CStr("in myio, untrapped read=%X",10), bl
@@:
else
	mov cx, [bp].PUSHAS.wCX	; bits set to allow byte/word/dword read/write
	mov dx, [bp].PUSHAS.wDX

	push ebx
	mov ebx, eax			; for OUT, ebx is to be loaded with value of eax
	mov bx, [bp].PUSHAS.wAX

	mov ax, 1A04h			; untrapped IO (generic)
	call [dwQemm]
	test [bp].PUSHAS.wCX, 4	; IN?
	jnz @F
	mov eax, ebx			; then load EAX with read value
	mov [bp].PUSHAS.wAX, ax
	invoke printf, CStr("in myio, untrapped read=%lX",10), eax
@@:
	pop ebx
endif
	pop ds
	popa
	clc		; NC=access handled
	retf
myio endp

main proc c args:word, argv:word

;--- 1. test if Qemm is installed
	push 0
	pop es
	mov eax, es:[67h*4]
	and eax, eax
	jz noemm
	mov cx, "QE"
	mov dx, "MM"
	mov ah, 3Fh
	int 67h
	cmp ah,0
	jz qpi_ok

;--- 2. check for QPIEMU
	mov ax, 1684h
	mov bx, 4354h
	int 2Fh
	cmp al, 0
	jnz noqpi
qpi_ok:
	mov word ptr [dwQemm+0], di
	mov word ptr [dwQemm+2], es
	invoke printf, CStr("QEMM/QPI found, entry=%X:%X",10), es, di
	mov ah, 3
	call [dwQemm]
	mov [wVersion], bx
	invoke printf, CStr("QPI call AH=3, Qemm version: %X.%02X",10), bh, bl
	cmp [wVersion], 0703h
	jb exit
	mov ax, 1A06h
	call [dwQemm]
	.if CARRY?
		invoke printf, CStr("QPI call AX=1A06h failed",10)
		jmp exit
	.endif
	mov word ptr [dwOldIO+0], di
	mov word ptr [dwOldIO+2], es
	invoke printf, CStr("QPI call AX=1A06h ok, current IO trap callback: %X:%X",10), es, di
	mov di, offset myio
	mov ax, seg myio
	mov es, ax
	mov ax, 1A07h
	call [dwQemm]
	.if CARRY?
		invoke printf, CStr("QPI call AX=1A07h failed",10)
		jmp exit
	.endif
	invoke printf, CStr("QPI call AX=1A07h ok, new IO trap callback: %X:%X",10), es, di

;-- ax=1A08h is GetPortTrap()

	mov dx, PORT
	mov ax, 1A09h
	call [dwQemm]
	.if CARRY?
		invoke printf, CStr("QPI call AX=1A09h, port %X failed",10), PORT
		jmp exit2
	.endif
	invoke printf, CStr("QPI call AX=1A09h ok, port %X now trapped",10), PORT

	mov dx, PORT+2
	mov ax, 1A09h
	call [dwQemm]
	.if CARRY?
		invoke printf, CStr("QPI call AX=1A09h, port %X failed",10), dx
		jmp exit3
	.endif
	invoke printf, CStr("QPI call AX=1A09h ok, port %X now trapped",10), dx

;--- access port DX

	invoke printf, CStr("accessing port 220h",10)

	mov bx, -1
	mov cx, -1
	mov dx, PORT

	mov eax, 55aa55AAh
	in al, dx
	invoke printf, CStr("IN al, dx: EAX=%lX",10), eax

	mov eax, 55aa55AAh
	in ax, dx
	invoke printf, CStr("IN ax, dx: EAX=%lX",10), eax

	mov eax, 12345678h
	out dx, al
	out dx, ax

	invoke printf, CStr("behind IO instructions",10)

	mov dx, PORT+2
	mov ax, 1A0Ah
	call [dwQemm]
	.if CARRY?
		invoke printf, CStr("QPI call AX=1A0Ah, port %X failed",10), dx
	.else
		invoke printf, CStr("QPI call AX=1A0Ah ok, port %X now untrapped",10), dx
	.endif

exit3:
	mov dx, PORT
	mov ax, 1A0Ah
	call [dwQemm]
	.if CARRY?
		invoke printf, CStr("QPI call AX=1A0Ah, port %X failed",10), dx
	.else
		invoke printf, CStr("QPI call AX=1A0Ah ok, port %X now untrapped",10), dx
	.endif

exit2:
	les di, [dwOldIO]
	mov ax, 1A07h
	call [dwQemm]
	.if CARRY?
		invoke printf, CStr("QPI call AX=1A07h failed, IO callback not restored",10)
	.else
		invoke printf, CStr("QPI call AX=1A07h ok, IO callback restored to %X:%X",10), es, di
	.endif
exit:
	ret
noemm:
	invoke printf, CStr("no EMM found",10)
	ret
noqpi:
	invoke printf, CStr("QPI not available",10)
	ret
main endp

	include setargv.inc

start:
	mov ax, @data
	mov ds, ax
	mov cs:[dataseg], ax
	mov bx, ss
	sub bx, ax
	shl bx, 4
	mov ss, ax
	add sp, bx
	call _setargv
	invoke main, [_argc], [_argv]
	mov ah, 4Ch
	int 21h

	END start
