
;*** test EMS 5B
;--- 5b00: get alternate map register set ( if BL=0 on ret, es:di will be current pointer to context save area )
;--- 5b01: set alternate map register set in BL
;---       if BL=0, es:di will be current context save area
;--- 5b02: get size of alternate map register set in dx

	.286
	.model small
	option casemap:none
	option casemap:none
	.stack 1024
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

        
	.data

wCSize dw 0

	.data?

buffer db 1024 dup (?)

	.code

	include printf.inc

memset proc c uses di pMem:ptr, wValue:word, wSize:word
	mov di, pMem
	mov ax, wValue
	mov cx, wSize
	cld
	rep stosb
	ret
memset endp

main proc c

	mov ax,3567h
	int 21h
	mov ax,bx
	mov cx,es
	or ax,cx
	jnz @F
	invoke printf, CStr( "EMM not found",lf)
	jmp exit
@@:
	mov dx, -1
	mov ax, 5B02h
	int 67h
	mov [wCSize], dx
	movzx ax, ah
	invoke printf, CStr("int 67h (ax=5B02h): ah=%X, dx=%X", lf), ax, dx
	cmp [wCSize], sizeof buffer
	ja error1

	push ds
	pop es
	invoke memset, addr buffer, 0, sizeof buffer

	mov ax, 5B00h
	int 67h
	movzx ax, ah
	movzx bx, bl
	invoke printf, CStr("int 67h (ax=5B00h): ah=%X, bl=%X, es:di=%X:%X", lf), ax, bx, es, di

	mov di, offset buffer
	push ds
	pop es
	push es
	push di
	mov ax, 5B01h
	mov bl, 0
	int 67h
	pop cx
	pop dx
	movzx ax, ah
	movzx bx, bl
	invoke printf, CStr("int 67h (ax=5B01h, bl=0, es:di=%X:%X): ah=%X, bl=%X, es:di=%X:%X", lf), dx, cx, ax, bx, es, di
exit:
	ret
error1:
	invoke printf, CStr("size of context save area too small", lf)
	jmp exit

main endp

start:
	mov ax,@data
	mov ds,ax
	mov cx,ss
	sub cx,ax
	shl cx,4
	mov ss,ax
	add sp,cx
	mov dx,es
	mov ax,ss
	sub ax,dx
	mov dx,sp
	shr dx,4
	add ax,dx
	mov bx,ax
	mov ah,4ah
	int 21h
	invoke main
	mov ah,4ch
	int 21h

	END start
