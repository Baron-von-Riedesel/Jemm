
;--- copy contents of XMS log buffer to a file (~LOGFILE.TXT).
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

;--- write XMS buffer to file

writefile proc
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
	jc writeerr
	cmp dwSize, 0
	jnz nextchunk
	mov ah, 3Eh
	int 21h
	jc closeerr
	mov ax, DStr("~LOGFILE.TXT written",13,10)
	ret
createerr:
	mov ax, DStr("create file failed",13,10)
	ret
closeerr:
	mov ax, DStr("close file failed",13,10)
	ret
writeerr:
	mov ax, DStr("write file failed",13,10)
	ret
writefile endp

;--- main()

main proc
	mov ax, 1684h	;get LOGFILE's API entry point
	mov bx, 6510h
	int 2Fh
	cmp al,0
	jnz not_installed
	mov word ptr pJLM+0,di
	mov word ptr pJLM+2,es
	mov ax, 0001	;get buffer info
	call [pJLM]
	cmp ecx, 0
	jz isempty
	mov xm.hSrc, dx
	mov dwSize, ecx
	mov word ptr xm.dwOfsDst+0, offset buffer
	mov word ptr xm.dwOfsDst+2, ds

	mov ax,4300h	;XMM installed?
	int 2Fh
	cmp al,80h
	jnz noxms
	mov ax,4310h	;get XMM entry
	int 2Fh
	mov word ptr pXMS+0,bx
	mov word ptr pXMS+2,es

	call writefile	;write XMS buffer to file
	push ax
	mov ax, 0002	;reset buffer
	call [pJLM]
	pop dx
exit:
	mov ah, 9
	int 21h
	ret
not_installed:
	mov dx, DStr("JLM LOGFILE not loaded",13,10)
	jmp exit
noxms:
	mov dx, DStr("XMS driver not found",13,10)
	jmp exit
isempty:
	mov dx, DStr("logfile is empty",13,10)
	jmp exit
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

