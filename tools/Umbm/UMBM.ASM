
;***   UMBM is a DOS device driver (use link with /NON !!!),
;***   but will not install permanently.
;***   If UMBs activated by UMBPCI are found, UMBM will check if
;***   a XMS host is present. If yes, it will hook into the XMS chain
;***   and add support for UMBs there. If no, it will install a micro
;***   XMS host which just provides UMBs.
;***   During the boot process, if line DOS=UMB is present in CONFIG.SYS,
;**    DOS will query for UMBs every time a driver has been loaded. If UMBs
;***   are provided, DOS will grab them. So UMBM's lifetime usually should be
;***   very short. Once the UMBs are grabbed, UMBM will remove itself from
;***   the XMS/Int 2Fh chain.
;***   To not use any DOS memory, UMBM copies itself into the first UMB.
;***   This assumes that DOS first allocates all available UMBs *before*
;***   "using" them. All DOSes I know do so, but AFAIK this is not documented
;***   and therefore a small risk remains. 

?MOVEINUMB equ 1        ;move in 1. umb

	.286
	.MODEL SMALL
	.386

cr	equ 13
lf	equ 10

;*** macros and structures ***

IODAT   struc
cmdlen  db      ?       ;+ 0    size of structure
unit    db      ?       ;+ 1
cmd     db      ?       ;+ 2
status  dw      ?       ;+ 3
        db      8 dup (?); reserved
media   db      ?       ;+ 0d
trans   dd      ?       ;+ 0e
count   dw      ?       ;+ 12   on init:offset parameter line
start   dw      ?       ;+ 14   on init:segment parameter line
drive   db      ?       ;+ 16
IODAT   ends

@putchr macro char
	mov dl,char
	mov ah,2
	int 21h
	endm

@stroutc macro xx
local xxxx
	CCONST segment word public 'CODE'
xxxx db xx,0
	CCONST ends
	CGROUP group _TEXT,CCONST
	.CODE
	invoke _strout,addr xxxx
	endm

@wordout macro arg
	ifnb <arg>
	 invoke  _wordout, arg
	else
	 invoke  _wordout, ax
	endif
	endm

	.CODE

	assume ds:_TEXT

	dw 0ffffh
	dw 0ffffh
	dw 8000h				;attribute
	dw offset devstrat		;device strategy
	dw offset devint		;device interrupt
devname db 'UMBXXXX0'			;device name

befptr  dd 1 dup (?)

memtab  label word
	dw 3 dup (0)			;max. 4 regions (segm,curr size,init size)
	dw 3 dup (0)
	dw 3 dup (0)
	dw 3 dup (0)
	dw 0000

umbrou  proc far                  ;XMS hook routine
	jmp short umbr1 		  ;must have this format
	nop
	nop
	nop
umbr1:
	cmp ah,10h			  ;request umb?
	jz umb1
	cmp ah,11h			  ;release umb?
	jz umb2
	db 0EAh
oldvec	dd 0					  ;chain to previous handler

umb1:									;request umb
	mov bx,offset memtab
	mov ax,0000
umb1b:									;<==== check next block
	cmp dx,cs:[bx+2]			;request block (DX=size in paras)
	ja short umb1a 			;jmp if block too small
	cmp word ptr cs:[bx+2],0000
	jz umb1a3
	mov ax,cs:[bx+4]			;original size
	sub ax,cs:[bx+2]			;subtract rest size
	add ax,cs:[bx+0]			;+ start address => new start address
	sub cs:[bx+2],dx			;size of block in DX
if ?MOVEINUMB
	jnz umb1c
	call deakt
umb1c:
endif
	mov bx,ax					;segment address of block
	mov ax,1					;no error!
	ret
umb1a:
	cmp ax,cs:[bx+2]			;remember largest block in AX
	jnb @F
	mov ax,cs:[bx+2]
@@:
	add bx,6
	cmp word ptr cs:[bx],0
	jnz umb1b
	mov bl,0b0h 				;error: smaller UMB available
	mov dx,ax					;still free space
	and dx,dx
	jnz umb1a2
umb1a3:
	mov bl,0b1h 				;error: no UMB free
umb1a2:
	mov ax,0					;error
	ret

umb2:							;release umb
	mov bx,offset memtab
umb2b:
	cmp dx,cs:[bx+0]
	jc umb2a1
	mov ax,cs:[bx+4]
	add ax,cs:[bx+0]
	cmp dx,ax
	jnc umb2a
	sub ax,dx
	mov cs:[bx+2],ax
	mov ax,1
	ret
umb2a:
	add bx,6
	cmp word ptr cs:[bx],0
	jnz umb2b
umb2a1:
	mov bl,0b2h 				;error: invalid UMB segment address
	mov ax,0
	ret
umbrou endp

deakt:
	push ds						;restore xms vector
	lds bx,cs:[oldvec]			;thus no space is needed at all
	push eax
	mov eax,dword ptr cs:[umbrou]
	mov [bx-5],eax
	mov al,byte ptr cs:[umbrou+4]
	mov [bx-1],al
	mov ax,word ptr cs:[oldint2f+2]
	and ax,ax
	jz @F
	push dx
	mov dx,word ptr cs:[oldint2f+0]
	mov ds,ax
	mov ax,252fh
	int 21h
	pop dx
@@:
	pop eax
	pop ds
	ret

oldint2f dd 0

myint2f::
	cmp ax,4300h
	jz int4300
	cmp ax,4310h
	jz int4310
	jmp dword ptr cs:[oldint2f]
int4300:
	or al,80h
_iret:
	iret
int4310:
	mov bx,offset umbrou
	push cs
	pop es
	iret

endres equ $

;*** end resident part ***

devstrat proc far
	mov word ptr cs:[befptr+0],bx
	mov word ptr cs:[befptr+2],es
	ret
devstrat endp

devint proc far
	pusha
	push ds
	push es
	lds bx,cs:[befptr]
	mov word ptr [bx.IODAT.status],100h
	mov al,[bx.IODAT.cmd]
	cmp al,00			;init?
	jnz short devi1
	push bx
	push ds
	call ignname 		;skip device driver name
	call main			;init
	pop ds
	pop bx
	mov word ptr [bx.IODAT.trans+0],0000
	mov word ptr [bx.IODAT.trans+2],ax
	jmp short devi2
devi1:
devi2:
	pop es
	pop ds
	popa
	ret
devint endp

ignname proc near			;skip device driver name
	mov es,[bx.IODAT.start]
	mov si,[bx.IODAT.count]
	dec si
ignn1:
	inc si
	cmp byte ptr es:[si],' '
	jz ignn1
	dec si
ignn2:
	inc si
	cmp byte ptr es:[si],' '
	jnz ignn2
	ret
ignname endp

_strout proc pascal pStr:word
	push si
	mov si,pStr
nextitem:
	lodsb
	and al,al
	jz done
	mov dl,al
	mov ah,2
	int 21h
	jmp nextitem
done:
	pop si
	ret
_strout endp

_wordout proc pascal wValue:word

	mov ax,wValue
	push ax
	mov al,ah
	call byteout
	pop ax
	call byteout
	ret
byteout:
	push ax
	shr al,4
	call nibout
	pop ax
nibout:
	and al,0Fh
	cmp al,10
	sbb al,69H
	das
	push dx
	mov dl,al
	mov ah,2
	int 21h
	pop dx
	retn
_wordout endp

getpar proc
nextitem:
	mov al,es:[si]
	cmp al,cr
	jz exit
	cmp al,20h
	jz getpar_1
	or al,20h
	call getregion
	jc exit
	jmp nextitem
getpar_1:
	inc si
	cmp byte ptr es:[si],' '
	jz getpar_1 
	jmp nextitem
exit:
	ret
getpar endp

makecaps proc
	cmp al,'a'
	jb iscaps
	cmp al,'z'
	ja iscaps
	and al,not 20h
iscaps:
	ret
makecaps endp

ishex proc
	cmp al,'0'
	jb @@no
	cmp al,'9'
	jbe @@yes
	cmp al,'A'
	jb @@no
	cmp al,'F'
	jbe @@yes2
@@no:
	stc
	ret
@@yes2:
	sub al,7
@@yes:
	sub al,'0'
	clc
	ret
ishex endp

gethexnumber proc
	push dx
	mov ch,00
	mov dx,0000
gethex2:
	mov al,es:[si]
	call makecaps
	call ishex
	jc gethex1
	inc ch
	mov ah,00
	shl dx,4
	add dx,ax
	inc si
	jmp gethex2
gethex1:
	cmp ch,1   ;null digits -> invalid
	mov ax,dx
	pop dx
	ret
gethexnumber endp

;--- inp: es:[si] ->
;--- ds:[di] ->

getregion proc uses bp
	cmp byte ptr es:[si],'/'	;allow the "/I=" prefix
	jnz @F
	mov al,es:[si+1]
	or al,20h
	cmp al,'i'
	jnz @F
	cmp byte ptr es:[si+2],'='
	jnz @F
	add si,3
@@:
	call gethexnumber
	jc getregion_er
	cmp al,00h
	jnz getregion_er
	mov bp,ax
	mov al,es:[si]
	cmp al,'-'
	jnz getregion_er
	inc si
	call gethexnumber
	jc getregion_er
	inc ax
	cmp al,00h
	jnz getregion_er
	sub ax,bp
	jbe getregion_er
	mov [di+0],bp
	mov [di+2],ax
	mov [di+4],ax
	add di,6
	clc
	ret
getregion_er:
	stc
	ret
getregion endp

;--- hook into the int 2Fh chain

installsmallxms proc

	mov ax,352Fh
	int 21h
	mov word ptr oldint2f+0,bx
	mov word ptr oldint2f+2,es
	mov dx,offset myint2f
	push ds
if ?MOVEINUMB
	mov ds,[memtab]
else
	push cs
	pop ds
endif
	mov ax,252fh
	int 21h
	pop ds
	mov word ptr [oldvec+0],offset _iret
if ?MOVEINUMB
	mov ax,[memtab]
else
	mov ax,cs
endif
	mov word ptr [oldvec+2],ax
	ret
installsmallxms endp

;--- called as device driver
;--- check cmdline and get the regions to add as UMBs
;--- test each region if it really contains RAM

main proc near

	push cs
	pop ds

	mov di,offset memtab
	call getpar
	jnc @F
	call explain
	jnc mainex
@@:
	mov bx,offset memtab
	mov ax,[bx]
	and ax,ax
	jz mainex
	@stroutc <"UMBM: Upper Memory Blocks: ">
mn1:						   ;<----
	@wordout [bx]
	@putchr '-'
	mov ax,[bx]
	add ax,[bx+2]
	dec ax
	@wordout ax
	mov dx,[bx+0]
	mov cx,[bx+2]	;size in paragraphs
	shr cx,8
	jcxz testdone
next4k: 
	push ds
	pushf
	cli
	mov ds,dx
	mov ax,05555h
	xor si,si
	xchg ax,[si]
	xor word ptr [si],0FFFFh
	xchg ax,[si]
	popf
	pop ds
	cmp ax,0AAAAh
	jz @F
	@stroutc <" - no RAM found at ">
	@wordout dx
	@stroutc <". Aborted!",cr,lf>
	jmp mainex
@@:
	add dx,100h
	loop next4k
testdone:

	@putchr ' '
	add bx,6
	cmp word ptr [bx],0
	jnz mn1
	@stroutc <cr,lf>

	mov ax,4300h
	int 2fh
	test al,80h			;does xms host exist?
	jnz @F
							;if not, install ÊXMS
	@stroutc <"UMBM: XMS host not found, installing ÊXMS",cr,lf>
	call installsmallxms
	jmp main_1
@@:
	mov ax,4310h		;get XMS call address
	int 2fh
	mov ax,es:[bx]
	cmp ax,03ebh		;should begin with a jmp short $+5
	jz short @F
	@stroutc <"UMBM: cannot hook into XMS chain",cr,lf>
	jmp mainex
@@:
	cli
	mov ax,offset umbrou
if ?MOVEINUMB
	mov cx,[memtab] 	;hook into XMS chain
else
	mov cx,cs
endif
	mov byte ptr es:[bx+0],0eah ;chain
	mov es:[bx+1],ax
	mov es:[bx+3],cx
	add bx,5
	mov word ptr [oldvec+0],bx
	mov word ptr [oldvec+2],es
	sti
main_1:
if ?MOVEINUMB
;	@stroutc <"UMBM: copy myself in 1. UMB",cr,lf>
	mov es,[memtab]
	xor di,di
	xor si,si
	mov cx,offset endres
	rep movsb
	mov ax,cs		   ;end address
else
	mov bx,offset endres
	shr bx,4
	inc bx
	mov ax,cs
	add ax,bx		   ;num paragraphs
endif
	ret
mainex:
	mov ax,cs
	ret
main endp

explain proc
	push cs
	pop ds
	mov dx, offset dHowTo
	mov ah, 9
	int 21h
	ret
explain endp

;*** entry if loaded from command line

main_exe proc c

	call explain
	mov ax,4c00h
	int 21h
	ret
main_exe endp

dHowTo  label byte
	db "UMBM is assumed to be located behind UMBPCI in CONFIG.SYS,",cr,lf
	db "and before the XMS driver. This will allow to load the XMS driver",cr,lf
	db "(and the EMM) into an UMB, thus saving some conventional DOS memory.",cr,lf
	db "As parameter it expects the upper memory regions to be added as UMBs.",cr,lf
	db "Example:",cr,lf
	db "DEVICE=UMBPCI.SYS /I=D000-EFFF",cr,lf
	db "DEVICE=UMBM.EXE /I=D000-EFFF",cr,lf
	db "DEVICEHIGH=HIMEMX.EXE",cr,lf
	db "DEVICEHIGH=JEMM386.EXE",cr,lf
	db "Max. 4 regions are accepted. After DOS has grabbed the UMBs,",cr,lf
	db "UMBM will remove itself from DOS memory.",cr,lf
	db "UMBM is Public Domain. Japheth.",cr,lf
	db '$'

	.STACK

	END main_exe
