
;--- XMSSTAT: display xms status.
;--- Public Domain.
;--- to be assembled with JWasm or Masm v6.

	.model small
DGROUP group _TEXT	;use tiny model
	.386

	.dosseg
	.stack 2048

cr  equ 13
lf  equ 10

;--- XMS handle table

XMSHT struct
        db ?
bSize   db ?
wHdls   dw ?
dwArray dd ?
XMSHT ends

;--- XMS handle

XMSH struct
bFlags db ? ;flags, see below 
bLocks db ? ;number of locks
dwAddr dd ? ;addr in KB
dwSize dd ? ;size in KB
XMSH ends

XMSF_FREEB  equ 1   ;free block
XMSF_USEDB  equ 2   ;used block
XMSF_FREEH  equ 4   ;free handle

printf proto c :ptr byte, :vararg

;--- define a string constant

CStr macro string
local xxx
	.const
xxx db string
	db 0
	.code
	exitm <offset xxx>
	endm

	.data

xmsadr    dd 0      ;XMS host call address
dwTotal   dd 0      ;total size EMBs
freehdls  dw 0      ;count free handles
wVersion  dw 0      ;XMS version
bFlags    db 0      ;flags

FL_NOSIZENULL   equ 1
FL_NOUSEDEMBS   equ 2
FL_NOFREEEMBS   equ 4
FL_FREEHANDLES  equ 8

	.code

	assume DS:DGROUP

	include printf.inc

;--- display a EOL

_crout proc
	invoke printf, CStr(<lf>)
	ret
_crout endp

;--- get cmdline parameter
;--- ES=PSP

getparm proc
	mov bx,0080h
	mov cl,es:[bx]
	inc bx
	mov ch,00
	jcxz getparm_ex
	mov ah,00
getparm_1:
	mov al,es:[bx]
	or al,20h
	cmp ax,'-a'
	jnz @F
	or bFlags,FL_NOFREEEMBS
@@:
	cmp ax,'-b'
	jnz @F
	or [bFlags], FL_FREEHANDLES
@@:
	cmp ax,'-c'
	jnz @F
	or [bFlags], FL_NOSIZENULL
@@:
	cmp ax,'-f'
	jnz @F
	or [bFlags], FL_NOUSEDEMBS
@@:
	cmp ax,'-?'
	jnz getparm_3
	invoke printf, CStr(<"XMSSTAT v1.0, Public Domain",lf>)
	invoke printf, CStr(<"usage: XMSSTAT [ -options ]",lf>)
	invoke printf, CStr(<"  -a: skip free memory blocks",lf>)
	invoke printf, CStr(<"  -b: also display unused handles",lf>)
	invoke printf, CStr(<"  -c: skip memory blocks with size 0",lf>)
	invoke printf, CStr(<"  -f: skip used memory blocks",lf>)
	jmp getparm_er
getparm_3:
	cmp al,'/'
	jnz @F
	mov al,'-'
@@:
	mov ah,al
	inc bx
	loop getparm_1
getparm_ex:
	clc
	ret
getparm_er:
	stc
	ret
getparm endp

;--- check if XMS handle should be displayed

checkflags proc
	test al,XMSF_USEDB	 ;block used?
	jnz isused
	test al,XMSF_FREEB
	jnz isfree
	inc [freehdls]
	test bFlags, FL_FREEHANDLES
	jz nodisp
	ret
isfree:
	test bFlags, FL_NOFREEEMBS
	jnz nodisp
	ret
isused:
	test bFlags, FL_NOUSEDEMBS
	jnz nodisp
	ret
nodisp:
	stc
	ret
checkflags endp

;--- display XMS handle flags

getflags proc
	test al,1
	jz @F
	mov cx,CStr("free")
	ret
@@:
	test al,2
	jz @F
	mov cx,CStr(<"used">)
	ret
@@:
	test al,4
	jz @F
	mov cx,CStr(<"unused">)
	ret
@@:
	mov cx,CStr(" ")
	ret
getflags endp

;--- display 1 XMS handle
;--- ES:BX -> handle
;--- SI=no of handle in array (1-based)

hdlout proc
	mov al,es:[bx].XMSH.bFlags
	call checkflags
	jnc @F
	ret
@@:
	test [bFlags], FL_NOSIZENULL
	jz @F
	cmp es:[bx].XMSH.dwSize,0
	jnz @F
	ret
@@:
	invoke printf, CStr("%3u %4X"), si, bx
	mov eax,es:[bx].XMSH.dwSize
	add [dwTotal],eax
	mov eax,es:[bx].XMSH.dwAddr
	shl eax, 10
	mov edx,es:[bx].XMSH.dwAddr
	mov ecx,es:[bx].XMSH.dwSize
	add edx,ecx
	shl edx,10
	jecxz @F
	dec edx
@@:
	mov cl, es:[bx].XMSH.bLocks
	mov ch, 00
	invoke printf, CStr("   %08lx-%08lx %8lu %5u "), eax, edx, es:[bx].XMSH.dwSize, cx
	mov al, es:[bx].XMSH.bFlags
	call getflags
	movzx ax,al
	invoke printf, CStr(<"%2X %s",lf>), ax, cx
	ret

hdlout endp

;--- display XMS handle array

hdlarray proc stdcall pArray:DWORD
	mov ah,5					;enable A20 in case array is in HMA
	call [xmsadr]
	mov [freehdls],0
	les bx,pArray
	mov cx,es:[bx].XMSHT.wHdls	;total number of handles
	mov dl,es:[bx].XMSHT.bSize	;size of element (must be 10)
	mov dh,00
	les bx,es:[bx].XMSHT.dwArray
	jcxz exit
	call _crout
	invoke printf, CStr(<" no handle region            size(kB) locks  flags",lf>)
	invoke printf, CStr(<"--------------------------------------------------------",lf>)
	mov si,1                    ;start with 1
nextitem:
	pusha
	call hdlout
	popa
	add bx,dx
	inc si
	loop nextitem
	invoke printf, CStr(<"--------------------------------------------------------",lf>)
	invoke printf, CStr(<"                            %9lu",lf>), dwTotal
exit:
	invoke printf, CStr(<"free handles: %u",lf>),freehdls
	mov ah,6					;disable A20
	call [xmsadr]
	ret

hdlarray endp

;--- display XMS handle info (handle table + handle array)

hdlinfo proc near

	mov ax,4309h
	int 2Fh
	cmp al,43h
	jnz nohandletab
	mov al,es:[bx].XMSHT.bSize	;size of element
	mov ah,00
	invoke printf, CStr(<"XMS handle table at %X:%X, handle cnt/size=%u/%u",lf>), es, bx, es:[bx].XMSHT.wHdls, ax
	invoke printf, CStr(<"XMS handle array at %X:%X",lf>), word ptr es:[bx].XMSHT.dwArray+2, word ptr es:[bx].XMSHT.dwArray+0
	cmp es:[bx].XMSHT.bSize, sizeof XMSH
	jnz invalhdlsize
	invoke hdlarray, es::bx
	ret
nohandletab:
	invoke printf, CStr(<"Int 2Fh, ax=4309h failed!",lf>)
	ret
invalhdlsize:
	invoke printf, CStr(<"XMS handle size isn't 10!",lf>)
	ret
hdlinfo endp

;*** display XMS UMB info

umbinfo  proc near
	mov ah,10h				;request UMB (upper memory block)
	mov dx,0ffffh			;get FFFF paras (will fail)
	call dword ptr [xmsadr]  ;but DX contains largest block
	mov ah,10h				;get this largest block
	call dword ptr [xmsadr]
	cmp ax,0001h
	jz umbchk1
	cmp bl,80h
	jnz umbchk2
	invoke printf, CStr(<"no UMB handler installed",lf>)
	jmp exit
umbchk2:
	cmp bl,0B1h
	jnz @F
	invoke printf, CStr(<"no free UMBs available",lf>)
	jmp exit
@@:
	movzx ax,bl
	invoke printf, CStr(<"request for UMB returned RC=%X",lf>),ax
	jmp exit
umbchk1:
	push bx 	 ;save UMB address
	push dx 	 ;save size largest
	invoke printf, CStr(<"segment of largest UMB: %X",lf>), bx
	pop ax
	invoke printf, CStr(<"size of largest UMB (paragraphs): %X",lf>), ax
	pop dx
	mov ah,11h				;free UMB again
	call dword ptr [xmsadr]
	cmp ax,1
	jz exit
	mov ax,bx
	mov ah,0
	invoke printf, CStr(<"calling free UMB failed, BL=%X",lf>),ax
exit:
	ret
umbinfo  endp

;--- display XMS v2 memory info

freememinfo2 proc
	mov ah,8
	mov bl,0
	call [xmsadr]
	cmp bl,0
	jnz failed
	invoke printf, CStr(<"v2 free memory largest/total (kB): %u/%u",lf>), ax, dx
	ret
failed:
	invoke printf, CStr(<"XMS call AH=08 failed",lf>)
	ret
freememinfo2 endp

;--- display XMS v3 memory info

freememinfo3 proc
	mov ah,88h
	mov bl,0
	call [xmsadr]
	cmp bl,0
	jnz failed
	invoke printf, CStr(<"v3 free memory largest/total (kB): %lu/%lu, highest addr: %lX",lf>), eax, edx, ecx
	ret
failed:
	invoke printf, CStr(<"XMS call AH=88h failed",lf>)
	ret
freememinfo3 endp

versioninfo proc
	mov ah,00
	call [xmsadr]
	mov [wVersion],ax
	push dx
	movzx ax,byte ptr [wVersion+1]
	movzx dx,byte ptr [wVersion+0]
	invoke printf, CStr(<"XMS version: %u.%u",lf>), ax, dx
	pop dx
	test dx,1
	jz nohma
	invoke printf, CStr(<"HMA handled by XMS host, HMA is ">)
	mov ah,01h				;try to reserve HMA
	mov dx,-1
	call [xmsadr]
	cmp ax,0001
	jnz hma_used
	mov ah,02h				;release HMA
	call [xmsadr]
	invoke printf, CStr(<"free",lf>)
	ret
hma_used:
	invoke printf, CStr(<"allocated",lf>)
	ret
nohma:
	invoke printf, CStr(<"HMA NOT handled by XMS host",lf>)
	ret
versioninfo endp

;--- main

main    proc c

	call getparm
	jc exit
	mov ax,4300h
	int 2fh
	test al,80h 		 ;xms host found?
	jnz main1
	invoke printf, CStr(<"no XMS host found",lf>)
	jmp exit
main1:
	mov ax,4310h		;get XMS call address
	int 2fh
	mov word ptr xmsadr+0,bx
	mov word ptr xmsadr+2,es
	invoke printf, CStr(<"XMS call address: %X:%X",lf>), word ptr [xmsadr+2], word ptr [xmsadr+0]

	call versioninfo
	call freememinfo2
	cmp byte ptr [wVersion+1],3
	jb @F
	call freememinfo3
@@:
	call hdlinfo
	call umbinfo
exit:
	ret
main    endp

;--- init

start   proc

	push cs
	pop ds

	pushf
	pushf
	pop ax
	or	ah,70h			;a 80386 will have bit 15 cleared
	push ax 			;if bits 12-14 are 0, it is a 80286
	popf				;or a bad emulation
	pushf
	pop ax
	popf
	and ah,0f0h
	js no386			;bit 15 set? then its a 8086/80186
	jnz is386
no386:
	invoke printf, CStr(<"a 80386 is needed",lf>)
	jmp done
is386:
	mov ax,@data
	mov ds,ax
	mov bx,ss
	mov cx,ds
	sub bx,cx
	shl bx,4
	add bx,sp
	mov ss,ax
	mov sp,bx
	call main
done:
	mov ah,4Ch
	int 21h
start   endp

	END start
