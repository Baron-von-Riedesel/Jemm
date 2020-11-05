
;*** save some interrupt vectors the way MS-DOS does
;*** needed for FreeDOS if Jemm386's FASTBOOT option is used

	.286
	.MODEL SMALL

IODAT   struct
cmdlen  db      ?       ;+ 0:size
unit    db      ?       ;+ 1:
cmd     db      ?       ;+ 2
status  dw      ?       ;+ 3
        db      8 dup (?); reserved
media   db      ?       ;+ 0d
trans   dd      ?       ;+ 0e
count   dw      ?       ;+ 12   init:offset parameter line
start   dw      ?       ;+ 14   init:segment parameter line
drive   db      ?       ;+ 16
IODAT   ends

	.CODE

	dw -1
	dw -1
	dw 8000h				  ;attribute
	dw offset devstrat		  ;device strategy
devc dw offset devintfirst	  ;device interrupt
devname db 'JEMFBHP$'

cmdptr	dd 1 dup (?)

devstrat proc far
	mov cs:word ptr[cmdptr+0],bx
	mov cs:word ptr[cmdptr+2],es
	ret
devstrat endp

devint proc far
	push ds
	push bx
	lds bx,cs:[cmdptr]
	mov word ptr [bx.IODAT.status],100h
	pop bx
	pop ds
	ret
devint endp

int19 proc
	cld
	push 70h
	pop ds
	xor ax,ax
	mov es,ax
	mov si,100h
	mov cx,NUMVECS
nextitem:
	lodsb
	mov di,ax
	shl di,2
	movsw
	movsw
	loop nextitem
	int 19h
int19 endp

resident label byte

vecstable db 15h,19h
NUMVECS equ $ - vecstable

devintfirst proc far
	pusha
	push ds
	push es
	lds bx,cs:[cmdptr]
	mov word ptr [bx.IODAT.status],100h
	cmp [bx.IODAT.cmd],0	;init call?
	jnz exit
	mov word ptr [bx.IODAT.trans+0],0
	mov word ptr [bx.IODAT.trans+2],cs
	mov cs:[devc],offset devint
	mov ax,4300h
	int 2fh
	cmp al,80h		;Himem must not be installed yet
	jnz @F
	push cs
	pop ds
	mov dx,offset str2
	mov ah,9
	int 21h
	jmp exit  
@@:
	xor ax,ax
	mov es,ax
	mov ax, es:[19h*4+2]	;int 19h must be unmodified (segment >= E000)
	cmp ax, 0E000h
	jc exit
	mov word ptr [bx.IODAT.trans+0],offset resident

	push 0070h
	pop es
	xor ax,ax
	mov ds,ax
	mov di,100h
	mov bx,offset vecstable
	mov cx,NUMVECS
nextitem:
	mov al,cs:[bx]
	inc bx
	mov ah,0
	mov si,ax
	shl si,2
	stosb
	movsw
	movsw
	loop nextitem
	mov word ptr ds:[19h*4+0],offset int19
	mov word ptr ds:[19h*4+2],cs
exit:
	pop es
	pop ds
	popa
	ret
devintfirst endp

str2 db "JEMFBHLP.EXE must be installed *before* Himem",13,10,'$'

str1 db "JEMFBHLP is needed for FreeDOS only. It saves some interrupt vectors",13,10
	db "the way MS-DOS does, thus allowing to set Jemm386's FASTBOOT option.",13,10
	db "It must be loaded in (FD)CONFIG.SYS before the XMS host. Example:",13,10
	db "DEVICE=JEMFBHLP.EXE",13,10
	db "DEVICE=HIMEM.EXE [or (Q)HIMEM.SYS]",13,10
	db "DEVICE=JEMM386.EXE FASTBOOT",13,10
	db '$'
main:
	mov dx,offset str1
	push cs
	pop ds
	mov ah,9
	int 21h
	mov ax,4C00h
	int 21h

	.stack 1024

	END main

