
;--- Set /D and /P option for currently loaded fastboot JLM.
;--- This program uses the API installed by FASTBOOT.DLL;
;--- alternatively, one can unload & reload FASTBOOT.DLL.

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

	.data

dopt db -1
popt db -1

	.const
helptxt label byte
	db "FBOOT: set FASTBOOT arguments.",13,10
	db "Usage: FBOOT [/Dn] [/Pm]",13,10
	db " /Dn: set disk to boot from to n [0-9]",13,10
	db " /Pm: set partition to boot from to m [0-9]",13,10
	db '$'

	.code

getoption proc
	cld
	mov si,81h
nextchr:
	lodsb es:[si]
	cmp al,13
	jz cmdl_done
	cmp al,20h
	jbe nextchr
	cmp al,'/'
	jz is_option
	cmp al,'-'
	jnz disp_help
is_option:
	lodsb es:[si]
	cmp al,13
	jz disp_help
	or al,20h
	cmp al,'d'
	jz d_option
	cmp al,'p'
	jz p_option
	cmp al,'b'
	jz b_option
	jmp disp_help
cmdl_done:
	clc
	ret
d_option:
	lodsb es:[si]
	cmp al,'0'
	jb disp_help
	cmp al,'9'
	ja disp_help
	sub al,'0'
	mov dopt,al
	jmp nextchr
p_option:
	lodsb es:[si]
	cmp al,'0'
	jb disp_help
	cmp al,'9'
	ja disp_help
	sub al,'0'
	mov popt,al
	jmp nextchr
b_option:
	mov dx,DStr("not implemented yet",13,10)
	mov ah,9
	int 21h
	jmp nextchr
disp_help:
	mov dx,offset helptxt
	mov ah,9
	int 21h
	stc
	ret
getoption endp

main proc

local dwFB:dword

	call getoption
	jc exit
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

	mov al,dopt
	cmp al,-1
	jz no_dopt
	mov ah,1
	call dwFB
	jc fb_call_failed
	mov dx,DStr("setting HD succeeded",13,10)
	mov ah,9
	int 21h
no_dopt:
	mov al,popt
	cmp al,-1
	jz no_popt
	mov ah,2
	call dwFB
	jc fb_call_failed
	mov dx,DStr("setting partition succeeded",13,10)
	mov ah,9
	int 21h
no_popt:
exit:
	ret

not_installed:
	mov dx,DStr("FASTBOOT not installed or wrong version")
	mov ah,9
	int 21h
	call lfout
	ret
fb_call_failed:
	mov dx,DStr("calling FASTBOOT failed")
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

