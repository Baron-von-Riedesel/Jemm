
;*** move block by int 15h, ah=87h

	.286
	.model tiny
	.stack 2048
	.dosseg
	.386

lf equ 10

CStr macro text:vararg
local sym
	.const
sym db text,0
	.code
	exitm <offset sym>
endm

	.data
        
gdt label byte
	dq 0
	dq 0

wSrcLim dw -1
wSrcA00 dw 0
bSrcA16 db 0
	db 093h
	db 0
	db 0

wDstLim dw -1
wDstA00 dw 0
bDstA16 db 0
	db 093h
	db 0
	db 0

	dq 0
	dq 0

	.code

	include printf.inc

main proc c

local	mblock:word

	mov ah,48h
	mov bx,4000h	;alloc 256 kB
	int 21h
	jc nomem
	mov mblock,ax

;--- setup descriptors

	movzx eax,ax
	shl eax, 4		;get block's linear address
;	add eax, 0FFCh  ;???
	lea edx, [eax+20000h]
	push eax
	push edx
	mov wSrcA00, ax
	mov wDstA00, dx
	shr eax, 16
	shr edx, 16
	mov bSrcA16, al
	mov bDstA16, dl
	pop edx
	pop eax

	invoke printf, CStr("src/dst descriptor base = %lXh/%lXh",lf), eax, edx
	invoke printf, CStr("src/dst descriptor limit = ffffh, ofs GDT=%Xh",lf), offset gdt

	call clearblock

;--- copy 32kB - should be ok

	mov cx, 4000h
	call i15
	invoke printf, CStr("int 15h, ah=87h, cx=%Xh returned with C=%u, ah=%X",lf), cx, dx, ax
	call testblock
	call clearblock

;--- copy 64kB - should be ok

	mov cx, 8000h
	call i15
	invoke printf, CStr("int 15h, ah=87h, cx=%Xh returned with C=%u, ah=%X",lf), cx, dx, ax
	call testblock
	call clearblock

;--- this move should fail - max words to copy is 8000h.

	mov cx, 8001h
	call i15
	invoke printf, CStr("int 15h, ah=87h, cx=%Xh returned with C=%u, ah=%X",lf), cx, dx, ax

	invoke printf, CStr("src/dst descriptor limit = 3fffh",lf)
	mov wSrcLim, 3fffh
	mov wDstLim, 3fffh

;--- this move should be ok

	mov cx, 2000h
	call i15
	invoke printf, CStr("int 15h, ah=87h, cx=%Xh returned with C=%u, ah=%X",lf), cx, dx, ax

;--- this move should fail - beyond descriptor limit

	mov cx, 2001h
	call i15
	invoke printf, CStr("int 15h, ah=87h, cx=%Xh returned with C=%u, ah=%X",lf), cx, dx, ax

;--- move with cx=0; MS Emm386 returns with C, AH=2; Jemm accepts a size of 0!

	mov cx, 0
	call i15
	invoke printf, CStr("int 15h, ah=87h, cx=%Xh returned with C=%u, ah=%X",lf), cx, dx, ax

	ret
nomem:
	invoke printf, CStr("out of DOS memory",lf)
	ret
i15:
	push ds
	pop es
	mov si, offset gdt
	mov ah,87h
	stc
	int 15h
	sbb dx,dx
	and dx,1
	movzx ax,ah
	retn

clearblock:
	cld
	mov cl,4
	mov eax,11111111h
	mov es, mblock
next64kb:
	push cx
	xor di, di
	mov cx, 4000h
	rep stosd
	mov dx, es
	add dx, 1000h
	mov es, dx
	add eax,11111111h
	pop cx
	dec cl
	jnz next64kb
	retn
testblock:
	retn

main endp

start:
	mov ax,cs
	mov ds,ax
	mov cx,ss
	sub cx,ax
	shl cx,4
	mov ss,ax
	add sp,cx   ; tiny model (CS=SS=DS) setup

	mov bx, sp
	add bx, 100h
	shr bx, 4
	mov ah, 4Ah
	int 21h
	call main
	mov ax,4c00h
	int 21h

	END start
