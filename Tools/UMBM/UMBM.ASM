
;***   UMBM is a DOS device driver, but will not install permanently:
;***   if UMBs activated by UMBPCI are found, UMBM will check if
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
?MOVEXBDA  equ 1        ;/XBDA option

	.286
	.MODEL SMALL
DGROUP group _TEXT
	.STACK
	.dosseg
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

;--- macro to define a string

CStr macro text:vararg
local xxxx
	.const
xxxx db text,0
	.code
	exitm <offset xxxx>
endm

;--- display a character on stdout

@putchr macro char
	mov dl,char
	mov ah,2
	int 21h
	endm

;--- display a 16-bit word on stdout

@wordout macro arg
	ifdif <arg>,<ax>
		mov ax,arg
	endif
	call _wordout
endm

	.CODE

	assume ds:DGROUP

	dw 0ffffh
	dw 0ffffh
	dw 8000h				;attribute
	dw offset devstrat		;device strategy
	dw offset devint		;device interrupt
devname db 'UMBXXXX0'		;device name

befptr  dd 1 dup (?)

memtab  label word
	dw 3 dup (0)			;max. 4 regions (segm,curr size,init size)
	dw 3 dup (0)
	dw 3 dup (0)
	dw 3 dup (0)
	dw 0000

umbrou  proc far        ;XMS hook routine
	jmp umbr1 			;must have this format
	nop
	nop
	nop
umbr1:
	cmp ah,10h			;request umb?
	jz umb1
	cmp ah,11h			;release umb?
	jz umb2
	db 0EAh
oldvec	dd 0			;chain to previous handler

umb1:					;request umb
	mov bx,offset memtab
	mov ax,0000
umb1b:						;<==== check next block
	cmp dx,cs:[bx+2]		;request block (DX=size in paras)
	ja short umb1a 			;jmp if block too small
	cmp word ptr cs:[bx+2],0000
	jz umb1a3
	mov ax,cs:[bx+4]		;original size
	sub ax,cs:[bx+2]		;subtract rest size
	add ax,cs:[bx+0]		;+ start address => new start address
	sub cs:[bx+2],dx		;size of block in DX
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
	jnz devi1
	push bx
	push ds
	call ignname 		;skip device driver name
	call main			;init
	pop ds
	pop bx
	mov word ptr [bx.IODAT.trans+0],0000
	mov word ptr [bx.IODAT.trans+2],ax
	jmp devi2
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

;--- display a nul-terminated string
;--- modifies ax

_strout proc stdcall uses dx si pStr:word
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
	ret
_strout endp

;--- display value in AX in hex
;--- preserves all registers except AX

_wordout proc

	push ax
	mov al,ah
	call byteout
	pop ax
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
	ret
_wordout endp

;--- es:si = cmdline

getpar proc
nextitem:
	mov al,es:[si]
	cmp al,cr
	jz exit
	cmp al,lf
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

;--- inp: es:[si] -> cmdline
;--- ds:[di] -> memtab

getregion proc uses bx
	cmp byte ptr es:[si],'/'	;allow the "/I=" prefix
	jnz @F
	mov eax,es:[si+1]
	or eax,20202020h
if ?MOVEXBDA
	cmp eax,'adbx'
	jz is_xbda
endif
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
	mov bx,ax
	mov al,es:[si]
	cmp al,'-'
	jnz getregion_er
	inc si
	call gethexnumber
	jc getregion_er
	inc ax
	cmp al,00h
	jnz getregion_er
	sub ax,bx
	jbe getregion_er
	mov [di+0],bx
	mov [di+2],ax
	mov [di+4],ax
	add di,6
	clc
	ret
if ?MOVEXBDA
is_xbda:
	inc bp
	add si,5
	clc
	ret
endif
getregion_er:
	stc
	ret
getregion endp

;--- search for UMBPCI blocks in upper memory
;--- DI->memtab

MCB struct
sig   db ?
psp   dw ?
_size dw ?
MCB ends

searchumbpciblocks proc
	mov si,0C800h
	.while si < 0F000h
		mov es,si
		cmp dword ptr es:[0],"BMU$"
		jnz noblock
		cmp dword ptr es:[4],"!lbT"
		jnz noblock
		mov bx,8
		.while word ptr es:[bx]
			mov ax,es:[bx] ;start of (first) block
			mov [di+0],ax
			mov ax,es:[bx+2];size of block in paras
			mov [di+2],ax
			mov [di+4],ax
			add di,3*2
			add bx,2*2
			.break .if di == offset memtab+4*3*2
		.endw
		.break
noblock:
		add si,100h
	.endw
done:
	ret
searchumbpciblocks endp

if ?MOVEXBDA
movexbda proc
	push 40h
	pop es
	mov dx,es:[0013h]
	shl dx,6		;convert kB to para
	mov ax,es:[000Eh]
	cmp ax,dx
	jnz dontmove
	
	mov es,ax
	movzx ax,byte ptr es:[0]	;size of xbda in kb
	shl ax,6		;size in paras
	cmp ax,memtab+2
	ja done
	mov dx,memtab+0
	add memtab+0,ax
	sub memtab+2,ax
	sub memtab+4,ax
	push ds
	push es
	pop ds
	mov es,dx
	mov cx,ax
	shl cx,3
	xor si,si
	xor di,di
	rep movsw
	mov di,ax
	push 40h
	pop es
	mov es:[000eh],dx
	mov ax,ds
	pop ds

;--- increase the last DOS MCB

	mov ah,52h
	int 21h
	mov si,es:[bx-2]
nextitem:
	mov es, si
	mov dx, es:[MCB._size]	;get size of MCB
	inc dx
	add dx, si		;dx = next block
	cmp byte ptr es:[MCB.sig], 'M'
	jnz @F
	mov si, dx
	jmp nextitem
@@:
	add es:[MCB._size],di

;--- increase bios conv memory size

	push 40h
	pop es
	shr di,6
	add es:[0013h],di

	invoke _strout, CStr("UMBM: XBDA moved to ")
	@wordout word ptr es:[000Eh]
	invoke _strout, CStr(cr,lf)
done:
	ret
dontmove:
	invoke _strout, CStr("UMBM: XBDA has already been moved - nothing done",cr,lf)
	ret

movexbda endp
endif

;--- called as device driver
;--- check cmdline and get the regions to add as UMBs
;--- test each region if it really contains RAM
;--- es:di = cmdline

main proc near

	push cs
	pop ds

	xor bp,bp
	mov di,offset memtab
	call getpar
	jc mainex
	cmp memtab,0  ;any valid /I= option given?
	jnz @F
	call searchumbpciblocks
@@:
	mov bx,offset memtab
	mov ax,[bx]
	and ax,ax
	jz mainex
	invoke _strout, CStr("UMBM: Upper Memory Blocks: ")
mn1:						;<----
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
	invoke _strout, CStr(" - no RAM found at ")
	@wordout dx
	invoke _strout, CStr(". Aborted!",cr,lf)
	jmp mainex
@@:
	add dx,100h
	loop next4k
testdone:

	@putchr ' '
	add bx,6
	cmp word ptr [bx],0
	jnz mn1
	invoke _strout, CStr(cr,lf)

if ?MOVEXBDA
	and bp,bp
	jz @F
	call movexbda
@@:
endif

	mov ax,4300h
	int 2fh
	xor bp,bp
	test al,80h			;does xms host exist?
	jnz @F
	mov ax,352Fh
	int 21h
	mov word ptr oldint2f+0,bx
	mov word ptr oldint2f+2,es
	mov word ptr [oldvec+0],offset _iret
if ?MOVEINUMB
	mov ax,[memtab]
else
	mov ax,cs
endif
	mov word ptr [oldvec+2],ax
	dec bp
	jmp main_1
@@:
	mov ax,4310h		;get XMS call address
	int 2fh
	mov ax,es:[bx]
	cmp ax,03ebh		;should begin with a jmp short $+5
	jz  @F
	invoke _strout, CStr("UMBM: cannot hook into XMS chain",cr,lf)
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
;	invoke _strout, CStr("UMBM: copy myself in 1. UMB",cr,lf)
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
	add ax,bx			;num paragraphs
endif
						;if no XMM found, install æXMM
	and bp,bp
	jz @F
	push ds
	push ax
	invoke _strout, CStr("UMBM: XMS host not found, installing æXMS",cr,lf)
	mov dx,offset myint2f
if ?MOVEINUMB
	mov ds,[memtab]
else
	push cs
	pop ds
endif
	mov ax,252fh
	int 21h
	pop ax
	pop ds
@@:
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

main_exe endp

dHowTo  label byte
	db "UMBM is assumed to be located behind UMBPCI in CONFIG.SYS,",cr,lf
	db "and before the XMS driver. This will allow to load the XMS driver",cr,lf
	db "(and the EMM) into an UMB, thus saving some conventional DOS memory.",cr,lf
	db cr,lf
	db "UMBM knows the following options:",cr,lf
	db "  /I=XXXX-YYYY   force region XXXX-YYYY to be included. Example: /I=D000-DBFF.",cr,lf
	db "  /XBDA          move the XBDA to the first UMB",cr,lf
	db "Option /I is not recommended, since UMBM will automatically find regions",cr,lf
	db "activated by UMBPCI. Option /XBDA may cause troubles if the upper memory",cr,lf
	db "can't be used by DMA. To find out, there's no other way than to try.",cr,lf
	db "Example:",cr,lf
	db "DEVICE=UMBPCI.SYS",cr,lf
	db "DEVICE=UMBM.EXE",cr,lf
	db "DEVICEHIGH=HIMEMX.EXE",cr,lf
	db "After DOS has grabbed the UMBs, UMBM will remove itself from DOS memory.",cr,lf
	db cr,lf
	db "UMBM is Public Domain. Japheth.",cr,lf
	db '$'

	END main_exe
