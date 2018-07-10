
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

;--- define a string constant

CStr macro string
local xxx
	.const
xxx db string
	db 0
	.code
	exitm <offset xxx>
	endm

;--- display word decimal

@wordout_d macro number,format
	mov cl,format
	ifidni <number>,<ax>
	else
	  mov ax,number
	endif
	call _wordout_d
	endm

;--- display dword decimal

@dwordout_d macro number,format
	ifnb <number>
		mov ax,word ptr number+0
		mov dx,word ptr number+2
	endif
	mov cl, format
	call _dwordout_d
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

_putchr proc stdcall char:word
	push dx
	push ax
	mov dx,char
	mov ah,2
	int 21h
	pop ax
	pop dx
	ret
_putchr endp

;--- display word in AX decimal
;--- min. number of chars in CL

_wordout_d proc
	xor dx,dx
;	jmp _dwordout_d
_wordout_d endp ;fall thru!

;--- display dword in DX:AX decimal
;--- min. number of chars in CL

_dwordout_d proc c

	pusha
	mov bl,cl
	mov si,offset tab1
	mov bh,00
	mov ch,10			;max cnt of digits
nextdigit:
	mov cl,'0' - 1
@@:
	inc cl
	sub ax,cs:[si + 0]
	sbb dx,cs:[si + 2]
	jnc @B
	add ax,cs:[si + 0]
	adc dx,cs:[si + 2]
	add si,4
	cmp cl,'0'			;current digit
	jnz @F
	cmp ch,1			;format
	jz @F
	cmp bh,00			;number of digits displayed
	jz skipdigit
@@:
	and bh,bh
	jnz prefdone
	sub bl,ch
	jna prefdone
@@:
	invoke _putchr, ' '
	dec bl
	jnz @B
prefdone:
	invoke _putchr, cx
	inc bh
skipdigit:
	dec ch
	jnz nextdigit
	popa
	ret

	align 2
tab1 dd 1000000000,100000000,10000000,1000000,100000,10000,1000,100,10,1

_dwordout_d endp

;--- display DWORD/WORD/BYTE in EAX/AX/AL hexadecimal

_dwordout:
	push eax
	shr eax,16
	call _wordout
	pop eax
_wordout:
	push ax
	mov al,ah
	call _byteout
	pop ax
_byteout:
	push ax
	shr al,4
	call _nibout
	pop ax
_nibout:
	and al,0Fh
	add al,'0'
	cmp al,'9'
	jbe @F
	add al,7
@@:
	invoke _putchr, ax
	ret

;--- display a string constant

_cputs proc stdcall uses si pText:ptr
	mov si,pText
nextitem:
	lodsb
	and al,al
	jz exit
	cmp al,10
	jnz @F
	invoke _putchr, 13
	mov al,10
@@:
	invoke _putchr, ax
	jmp nextitem
exit:
	ret
_cputs endp

;--- display a EOL

_crout proc
	invoke _cputs, CStr(<lf>)
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
	invoke _cputs, CStr(<"XMSSTAT v1.0, Public Domain",lf>)
	invoke _cputs, CStr(<"usage: XMSSTAT [ -options ]",lf>)
	invoke _cputs, CStr(<"  -a: skip free memory blocks",lf>)
	invoke _cputs, CStr(<"  -b: also display unused handles",lf>)
	invoke _cputs, CStr(<"  -c: skip memory blocks with size 0",lf>)
	invoke _cputs, CStr(<"  -f: skip used memory blocks",lf>)
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

flagsout proc
	test al,1
	jz @F
	invoke _cputs, CStr(<" free">)
@@:
	test al,2
	jz @F
	invoke _cputs, CStr(<" used">)
@@:
	test al,4
	jz @F
	invoke _cputs, CStr(<" unused">)
@@:
	ret
flagsout endp

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
	@wordout_d si, 3
	invoke _putchr, ' '
	mov eax,es:[bx].XMSH.dwSize
	add [dwTotal],eax
	mov ax,bx
	call _wordout
	invoke _cputs, CStr("   ")
	mov eax,es:[bx].XMSH.dwAddr
	shl eax,10
	call _dwordout
	invoke _putchr, '-'
	mov eax,es:[bx].XMSH.dwAddr
	mov ecx,es:[bx].XMSH.dwSize
	add eax,ecx
	shl eax,10
	jecxz @F
	dec eax
@@:
	call _dwordout
	invoke _putchr, ' '
	@dwordout_d es:[bx].XMSH.dwSize, 8
	invoke _putchr, ' '
	mov al, es:[bx].XMSH.bLocks
	mov ah, 00
	@wordout_d ax,5
	invoke _putchr, ' '
	mov al, es:[bx].XMSH.bFlags
	call _byteout
	mov al, es:[bx].XMSH.bFlags
	call flagsout
	call _crout
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
	invoke _cputs, CStr(<" no handle region            size(kB) locks flags",lf>)
	invoke _cputs, CStr(<"--------------------------------------------------------",lf>)
	mov si,1                    ;start with 1
nextitem:
	pusha
	call hdlout
	popa
	add bx,dx
	inc si
	loop nextitem
	invoke _cputs, CStr(<"--------------------------------------------------------",lf>)
	invoke _cputs, CStr(<"                            ">)
	@dwordout_d dwTotal,9
	call _crout
exit:
	invoke _cputs, CStr(<"free handles: ">)
	@wordout_d freehdls,1
	call _crout
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
	invoke _cputs, CStr(<"XMS handle table at ">)
	mov ax,es
	call _wordout
	invoke _putchr, ':'
	mov ax,bx
	call _wordout
	invoke _cputs, CStr(<", handle cnt/size=">)
	mov ax,es:[bx].XMSHT.wHdls	;number of total handles
	@wordout_d ax,1
	invoke _putchr,  '/'
	mov al,es:[bx].XMSHT.bSize	;size of element
	mov ah,00
	@wordout_d ax,1
	call _crout
	invoke _cputs, CStr(<"XMS handle array at ">)
	mov ax,word ptr es:[bx].XMSHT.dwArray+2
	call _wordout
	invoke _putchr, ':'
	mov ax,word ptr es:[bx].XMSHT.dwArray+0
	call _wordout
	call _crout
	cmp es:[bx].XMSHT.bSize, sizeof XMSH
	jnz invalhdlsize
	invoke hdlarray, es::bx
	ret
nohandletab:
	invoke _cputs, CStr(<"Int 2Fh, ax=4309h failed!",lf>)
	ret
invalhdlsize:
	invoke _cputs, CStr(<"XMS handle size isn't 10!",lf>)
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
	invoke _cputs, CStr(<"no UMB handler installed",lf>)
	jmp exit
umbchk2:
	cmp bl,0B1h
	jnz @F
	invoke _cputs, CStr(<"no free UMBs available",lf>)
	jmp exit
@@:
	push bx
	invoke _cputs, CStr("request for UMB returned RC:")
	pop ax
	call _byteout
	call _crout
	jmp exit
umbchk1:
	push bx 	 ;save UMB address
	push dx 	 ;save size largest
	push bx
	invoke _cputs, CStr(<"segment of largest UMB:">)
	pop ax
	call _wordout
	call _crout
	invoke _cputs, CStr(<"size of largest UMB (paragraphs):">)
	pop ax
	call _wordout
	call _crout
	pop dx
	mov ah,11h				;free UMB again
	call dword ptr [xmsadr]
	cmp ax,1
	jz exit
	push bx
	invoke _cputs, CStr(<"calling free UMB failed, BL=">)
	pop ax
	call _byteout
	call _crout
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
	push dx
	push ax
	invoke _cputs, CStr(<"largest free memory block (v2) in kB: ">)
	pop ax
	@wordout_d ax,1
	invoke _cputs, CStr(<", total free: ">)
	pop ax
	@wordout_d ax,1
	call _crout
	ret
failed:
	invoke _cputs, CStr(<"XMS call AH=08 failed",lf>)
	ret
freememinfo2 endp

;--- display XMS v3 memory info

freememinfo3 proc
	mov ah,88h
	mov bl,0
	call [xmsadr]
	cmp bl,0
	jnz failed
	push edx
	push eax
	invoke _cputs, CStr(<"largest free memory block (v3) in kB: ">)
	pop ax
	pop dx
	@dwordout_d ,1
	invoke	_cputs, CStr(<", total free: ">)
	pop ax
	pop dx
	@dwordout_d ,1
	call _crout
	ret
failed:
	invoke _cputs, CStr(<"XMS call AH=88h failed",lf>)
	ret
freememinfo3 endp

versioninfo proc
	mov ah,00
	call [xmsadr]
	mov [wVersion],ax
	push dx
	invoke _cputs, CStr(<"XMS version: ">)
	movzx ax,byte ptr [wVersion+1]
	@wordout_d ax,1
	invoke _putchr, '.'
	movzx ax,byte ptr [wVersion+0]
	@wordout_d ax,1
	call _crout
	pop dx
	test dx,1
	jz nohma
	invoke _cputs, CStr(<"HMA handled by XMS host, HMA is ">)
	mov ah,01h				;try to reserve HMA
	mov dx,-1
	call [xmsadr]
	cmp ax,0001
	jnz hma_used
	mov ah,02h				;release HMA
	call [xmsadr]
	invoke _cputs, CStr(<"free",lf>)
	ret
hma_used:
	invoke _cputs, CStr(<"allocated",lf>)
	ret
nohma:
	invoke _cputs, CStr(<"HMA NOT handled by XMS host",lf>)
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
	invoke _cputs, CStr(<"no XMS host found",lf>)
	jmp exit
main1:
	mov ax,4310h		;get XMS call address
	int 2fh
	mov word ptr xmsadr+0,bx
	mov word ptr xmsadr+2,es
	invoke _cputs, CStr(<"XMS call address: ">)
	mov ax,word ptr [xmsadr+2]
	call _wordout
	invoke _putchr, ':'
	mov ax, word ptr [xmsadr+0]
	call _wordout
	call _crout

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
	invoke _cputs, CStr(<"a 80386 is needed",lf>)
	jmp done
is386:
	call main
done:
	mov ah,4Ch
	int 21h
start   endp

	END start
