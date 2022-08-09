
;--- tsr to test JLM IOTRAP.
;--- it installs a callback which is called whenever port 100h
;--- is accessed.
;--- the callback displays some colored characters on line 25.
;--- assemble: JWasm -bin -Fo testiot.com testiot.asm

	.286
	.model tiny
	.stack 2048
	.dosseg
	.386

	.data

szOK1   db "IOTRAP found.",13,10,'$'
szOK2   db "TESTIOT installed.",13,10,'$'
szErr1  db "IOTRAP is NOT installed!",13,10,'$'
szErr2  db "IOTRAP has wrong version!",13,10,'$'
szErr3  db "register callback failed!",13,10,'$'

	.code

	org 100h

start:
	mov ax, 1684h	;get IOTRAP's entry point
	mov bx, 6661h
	int 2Fh
	cmp al,0        ;IOTRAP installed?
	jnz not_installed
	push es
	push di
	mov bp,sp
	mov dx,offset szOK1
	mov ah,9
	int 21h
	mov ax,0000     ;call "get version"
	call dword ptr [bp]
;--- check version and exit if not ok
;	cmp ax,???
;	jc wrong_version
;--- API: CX:DX=CS:IP of callback, BX=param
	mov cx,cs
	mov dx,offset iocb
	mov bx,0
	mov ax,0001     ;call "register callback"
	call dword ptr [bp]
	jc  register_failed
	mov dx,offset szOK2
	mov ah,9
	int 21h
	mov dx,offset resident
	shr dx,4
	inc dx
	mov ax,3100h
	int 21h

iocb:

;--- callback when i/o was detected.
;--- cpu is in 16-bit protected-mode, ring 0.
;--- EAX=data of IO
;--- DX=IO port
;--- CX=type of IO
;--- BX=value when callback was "registered"
;--- DS=data segment
;--- ES=flat segment

	push esi
	mov esi,0B8000h

;--- display '*#!+' in colors at line 25

	mov word ptr es:[esi+160*24+0],'*'+100h*40h
	mov word ptr es:[esi+160*24+2],'#'+100h*51h
	mov word ptr es:[esi+160*24+4],'!'+100h*62h
	mov word ptr es:[esi+160*24+6],'+'+100h*73h
	pop esi
	retd    ;a 32bit RETF is needed!!!

resident label byte

not_installed:
	mov dx,offset szErr1
	mov ah,9
	int 21h
	int 20h
wrong_version:
	mov dx,offset szErr2
	mov ah,9
	int 21h
	int 20h
register_failed:
	mov dx,offset szErr3
	mov ah,9
	int 21h
	int 20h

	end start

