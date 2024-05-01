
;*** EMS move

	.286
	.model small
	option casemap:none
	option casemap:none
	.stack 1024
	.dosseg

CStr macro text:vararg
local sym
	.const
sym db text,0
	.code
	exitm <offset sym>
endm

lf equ 10

        
?BUFSIZE	equ 10000h
?SIZE		equ ?BUFSIZE/4000h	;size in EMS pages
        

        .386

EMM57 struct
dwSize	DD ?	; +0  size of region
bSrcTyp DB ?	; +4  src memory type
wSrcHdl DW ?	; +5  src handle
wSrcOfs DW ?	; +7  src ofs
wSrcSeg DW ?	; +9  src segm./log. page
bDstTyp DB ?	; +11 dst memory type
wDstHdl	DW ?	; +12 dst handle
wDstOfs	DW ?	; +14 dst ofs
wDstSeg	DW ?	; +16 dst segm./log. page
EMM57 ends

    .data

emm57   EMM57 <>

	.code

	include printf.inc

main proc c

local handle:word
local wPages:word
local wMem:word
local frame:word

	mov ax,3567h
	int 21h
	mov ax,bx
	mov cx,es
	or ax,cx
	jnz @F
	invoke printf, CStr( "EMM not found",lf)
	jmp exit
@@:
	mov ah,48h
	mov bx,?BUFSIZE/10h
	int 21h
	jnc @F
	invoke printf, CStr( "DOS memory allocation failed",lf)
	jmp exit
@@:
	mov wMem, ax
	mov bx,?SIZE
	mov ah,43h	   ;alloc pages
	int 67h
	and ah,ah
	jnz error2
	mov handle,dx

	invoke printf, CStr("Handle %u allocated, clearing content ... ", lf), handle

	xor di, di
	mov es, wMem
	mov eax,12345678h
	mov cx,?BUFSIZE/4
	rep stosd

	mov si, offset emm57
	mov emm57.dwSize, ?BUFSIZE
	mov emm57.bSrcTyp, 0
	mov emm57.wSrcOfs, 0
	mov emm57.wSrcSeg, es
	mov emm57.bDstTyp, 1
	mov ax,handle
	mov emm57.wDstHdl, ax
	mov emm57.wDstOfs, 0
	mov emm57.wDstSeg, 0
	mov ax,5700h	;move memory region
	int 67h
	and ah,ah
	jnz error3
	invoke printf, CStr( "move to expanded memory ok",lf)

	xor di, di
	mov es, wMem
	xor eax, eax
	mov cx,?BUFSIZE/4
	rep stosd

	mov si, offset emm57
	mov emm57.dwSize, ?BUFSIZE
	mov ax,handle
	mov es,wMem
	mov emm57.wSrcHdl, ax
	mov emm57.bSrcTyp, 1
	mov emm57.wSrcOfs, 0
	mov emm57.wSrcSeg, 0
	mov emm57.bDstTyp, 0
	mov emm57.wDstOfs, 0
	mov emm57.wDstSeg, es
	mov ax,5700h	;move memory region
	int 67h
	and ah,ah
	jnz error3
	invoke printf, CStr( "move from expanded memory ok",lf)

	xor di, di
	mov es, wMem
	mov eax, 12345678h
	mov cx,?BUFSIZE/4
	repz scasd
	jz exit2
	invoke printf, CStr( "memory content has changed!",lf)

exit2:
	mov dx,handle
	mov ah,45h	   ;free pages
	int 67h
exit:
	ret
error2:
	movzx ax,ah
	invoke printf, CStr( "int 67h, ah=43h, bx=%u failed, status=%X",lf), bx, ax
	jmp exit
error3:
	movzx ax,ah
	invoke printf, CStr( "int 67h, ah=57h failed, status=%X",lf), ax
	jmp exit
main endp

start:
	mov ax,@data
	mov ds,ax
	mov cx,ss
	sub cx,ax
	shl cx,4
	mov ss,ax
	add sp,cx
	mov dx,es
	mov ax,ss
	sub ax,dx
	mov dx,sp
	shr dx,4
	add ax,dx
	mov bx,ax
	mov ah,4ah
	int 21h
	invoke main
	mov ah,4ch
	int 21h

	END start
