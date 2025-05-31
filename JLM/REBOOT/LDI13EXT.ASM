
;--- sample how to load an int 13h extension into FASTBOOT JLM.
;--- this sample just swaps HDs 0 and 1 in int 13h; int 41h/46h are NOT modified.
;--- assemble: JWasm -mz LDI13EXT.asm

	.286
	.model tiny
	.dosseg
	.stack 2048
	option casemap:none
	.386

CStr macro text:vararg
local sym
	.const
sym db text,0
	.code
	exitm <offset sym>
endm

DStr macro text:vararg
local sym
	.const
sym db text,'$'
	.code
	exitm <offset sym>
endm

IRETS struct
wIP	dw ?
wCS	dw ?
wFL	dw ?
IRETS ends

	.const
helptxt label byte
	db "LDI13EXT: sample how to load an int 13h extension to FASTBOOT JLM.",13,10
	db "Required:",13,10
	db " - Jemm v5.86+",13,10
	db " - Jemm loaded with option FASTBOOT",13,10
	db " - FASTBOOT.DLL be loaded",13,10
	db '$'

	.code

;--- int 13h extension initialization
;--- assumes: CS=_TEXT, DS=0000

int13ext proc

	push es
	pusha
	mov eax,ds:[13h*4]
	mov cs:[oldi13a],eax
	mov cs:[oldi13b],eax
	sub word ptr ds:[413h],1	;decrease conv. memory by 1 kB
	mov ax,ds:[413h]
	shl ax,6
	mov es,ax
	shl eax,16
	xor di,di
	mov si,offset myint13
	mov cx,size_int13ext2
	cld
	rep movsb es:[di],cs:[si]
	mov ds:[13h*4],eax
	popa
	pop es
	retf

;--- the new int 13h code

myint13:
	cmp dl,80h	;HD 0?
	jz is_hd0
	cmp dl,81h	;HD 1?
	jz is_hd1
jmp_oldvec:
	db 0eah		;opcode jmp ssss:oooo
oldi13a dd 0
is_hd0:
is_hd1:
	xor dl,1	; swap disks
	cmp ah,8	; ah=8 is special because DL returns # of HDs
	jz jmp_oldvec
	pushf
	db 09ah		;opcode call ssss:oooo
oldi13b dd 0
	push bp
	mov bp,sp
	push ax
	pushf
	xor dl,1	; restore DL
	pop ax
	mov byte ptr [bp+2].IRETS.wFL,al
	pop ax
	pop bp
	iret
size_int13ext equ $ - int13ext
size_int13ext2 equ $ - myint13
int13ext endp

main proc

local dwFB:dword

	cld
	mov si,81h
nextchr:
	lodsb es:[si]
	cmp al,13
	jz cmdl_done
	cmp al,20h
	jbe nextchr
	mov dx,offset helptxt
	mov ah,9
	int 21h
	ret
cmdl_done:
	mov bx,4435h	;FASTBOOT/REBOOT device ID
	mov ax,1684h	;get API entry point
	int 2Fh
	cmp al,0
	jnz not_installed
	mov word ptr dwFB+0,di
	mov word ptr dwFB+2,es
	mov ah,0		;get version
	call dwFB
	jc not_installed
	test ah,1		;FASTBOOT variant?
	jz not_installed

;--- test that at least 2 HDs are present

	push ds
	mov ax,40h
	mov ds,ax
	mov al,ds:[75h]
	pop ds
	cmp al,2
	jb no_hds

;--- FASTBOOT API AH=4: DS:SI=start extension, ECX=size extension in bytes

	mov si,offset int13ext
	mov ecx, size_int13ext
	mov ah,4
	call dwFB
	jc no_int13ext
	mov dx,DStr("int 13h extension loaded")
	mov ah,9
	int 21h
	call lfout
	ret

not_installed:
	mov dx,DStr("FASTBOOT not installed")
	mov ah,9
	int 21h
	call lfout
	ret
no_hds:
	mov dx,DStr("at least 2 HDs are needed")
	mov ah,9
	int 21h
	call lfout
	ret
no_int13ext:
	mov dx,DStr("int 13h extension not accepted")
	mov ah,9
	int 21h
	call lfout
	ret
main endp

lfout proc
	mov dx,DStr(13,10)
	mov ah,9
	int 21h
	ret
lfout endp

start:
	mov ax,cs
	mov ds,ax
	mov dx,ss
	sub dx,ax
	shl dx,4
	mov ss,ax
	add sp,dx
	mov bx,sp
	shr bx,4
	mov cx,es
	sub ax,cx
	add bx,ax
	mov ah,4Ah
	int 21h
	call main
	mov ah,4ch
	int 21h

	end start

