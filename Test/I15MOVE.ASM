
;*** move block by int 15h, ah=87h

	.286
	.model small
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
        
gdt	label byte
	dq 0
	dq 0

	dw -1
wSrc dw 0
bSrc db 0
	db 0F3h
	db 0
	db 0

	dw -1
wDst dw 0
bDst db 0
	db 0F3h
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
	movzx eax,ax
	shl eax, 4		;get blocks linear address
	add eax, 0FFCh
	lea edx, [eax+20000h]
	mov wSrc, ax
	mov wDst, dx
	shr eax, 16
	shr edx, 16
	mov bSrc, al
	mov bDst, dl

	call clearblock
	mov cx,8000h
	push ds
	pop es
	mov si, offset gdt
	mov ah,87h
	stc
	int 15h
	jc error
	movzx ax,ah
	invoke printf, CStr("int 15h, ah=87, cx=%X ok, returned with ah=%X",lf),cx, ax
	call testblock

	call clearblock
	mov cx,4000h
	push ds
	pop es
	mov si, offset gdt
	mov ah,87h
	stc
	int 15h
	jc error
	movzx ax,ah
	invoke printf, CStr("int 15h, ah=87, cx=%X ok, returned with ah=%X",lf),cx, ax
	call testblock

;--- this call should fail, max words to copy is 8000h

	call clearblock
	mov cx,0C000h
	push ds
	pop es
	mov si, offset gdt
	mov ah,87h
	stc
	int 15h
	jc error
	invoke printf, CStr("int 15h, ah=87, cx=%X ok, returned with ah=%X",lf),cx, ax
	call testblock

	ret
error:
	movzx ax,ah        
	invoke printf, CStr("int 15h, ah=87, CX=%Xh returned with C, AH=%X",lf), cx, ax
	ret
nomem:
	invoke printf, CStr("out of DOS memory",lf)
	ret

clearblock:
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
	mov bx, sp
	mov cx, ss
	mov dx, es
	sub cx, dx
	shr bx, 4
	add bx, cx
	mov ah, 4Ah
	int 21h
	mov ax,@data
	mov ds,ax
	mov cx,ss
	sub cx,ax
	shl cx,4
	mov ss,ax
	add sp,cx
	call main
	mov ax,4c00h
	int 21h

	END start
