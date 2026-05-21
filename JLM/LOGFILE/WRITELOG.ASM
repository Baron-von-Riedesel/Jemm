
;--- get contents of log buffer and write it to a file
;--- assemble: JWasm -mz writelog.asm

	.286
	.model tiny
	.stack 4096
	.dosseg
	.386

DStr macro text:vararg
local sym
	.const
sym db text,'$'
	.code
	exitm <offset sym>
endm

XMSMOVE struct
dwSize   dd ?
hSrc     dw ?
dwOfsSrc dd ?
hDst     dw ?
dwOfsDst dd ?
XMSMOVE ends

	.data

pJLM   dd 0
pXMS   dd 0
dwSize dd 0
xm     XMSMOVE <0,0,0,0,0>
szFN   db "~LOGFILE.TXT",0

	.data?

buffer db 32768 dup (?)

	.code

main proc
	mov ax, 1684h	;get GENERIC's entry point
	mov bx, 6510h
	int 2Fh
	cmp al,0
	jnz not_installed
	mov word ptr pJLM+0,di
	mov word ptr pJLM+2,es
	mov ax, 0001	;call "get info"
	call [pJLM]
	cmp ecx, 0
	jz isempty
	mov xm.hSrc, dx
	mov word ptr xm.dwOfsDst+0, offset buffer
	mov word ptr xm.dwOfsDst+2, ds
	mov dwSize, ecx

	mov ax,4300h
	int 2Fh
	cmp al,80h
	jnz noxms
	mov ax,4310h
	int 2Fh
	mov word ptr pXMS+0,bx
	mov word ptr pXMS+2,es

	mov dx, offset szFN
	xor cx, cx
	mov ax, 3C00h
	int 21h
	jc createerr
	mov bx, ax
nextchunk:
	mov eax, dwSize
	cmp eax, sizeof buffer
	jb @F
	mov eax, sizeof buffer
@@:
	push bx
	sub dwSize, eax

	mov di, ax
	add ax, 2-1	; size must be even
	and ax, not 1
	mov word ptr xm.dwSize, ax

	mov si, offset xm
	mov ah, 0Bh
	call [pXMS]
	movzx eax, di
	add xm.dwOfsSrc, eax
	pop bx
	mov dx, offset buffer
	mov cx, di
	mov ah, 40h
	int 21h
	cmp dwSize, 0
	jnz nextchunk
	mov ah, 3Eh
	int 21h
	jc closeerr
	mov ax, 0002	;call "clear data"
	call [pJLM]
	mov dx, DStr("~LOGFILE.TXT written",13,10)
	mov ah, 9
	int 21h
	ret
not_installed:
	mov dx, DStr("JLM LOGFILE not loaded",13,10)
	mov ah, 9
	int 21h
	ret
noxms:
	mov dx, DStr("XMS driver not found",13,10)
	mov ah, 9
	int 21h
	ret
isempty:
	mov dx, DStr("logfile is empty",13,10)
	mov ah, 9
	int 21h
	ret
createerr:
	mov dx, DStr("create file failed",13,10)
	mov ah, 9
	int 21h
	ret
closeerr:
	mov dx, DStr("close file failed",13,10)
	mov ah, 9
	int 21h
	ret
main endp

start:
	mov ax,cs
	mov ds,ax
	mov bx,ss
	sub bx,ax
	shl bx,4
	mov ss,ax
	add sp,bx
	call main
	mov ah,4Ch
	int 21h

	end start

