
;*** test EMS move (int 67h, ah=57h)
;*** move 1024 kB conv to EMS memory
;*** move 1024 kB EMS to EMS memory non-overlapping
;*** move 1024 kB EMS to EMS memory overlapping

	.286
	.model small
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

?SIZE	equ 64		;size in EMS pages (64*16=1024 kB)
        

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
	invoke printf, CStr("EMM not found",lf)
	jmp exit
@@:
	xor ax,0
	mov wMem, ax
	mov bx,?SIZE*2
	mov ah,43h	   ;alloc pages
	int 67h
	and ah,ah
	jz @F
	movzx ax,ah
	invoke printf, CStr( "int 67h, ah=43h, bx=%X failed, status=%X",lf),bx,ax
	jmp exit
@@:
	mov handle,dx
	invoke printf, CStr("Handle %u allocated",lf), handle

	mov si, offset emm57
	mov emm57.dwSize, 100000h
	mov emm57.bSrcTyp, 0
	mov emm57.wSrcOfs, 0
	mov emm57.wSrcSeg, 0

	mov ax,handle
	mov emm57.bDstTyp, 1
	mov emm57.wDstHdl, ax
	mov emm57.wDstOfs, 0
	mov emm57.wDstSeg, 0
	mov ax,5700h	;move memory region
	int 67h
	movzx ax,ah
	invoke printf, CStr( "5700,0->1: move conv to expanded memory, status=%X",lf),ax

;--- move from EMS to EMS non-overlapp

	mov si, offset emm57
	mov ax,handle
	mov emm57.dwSize, ?SIZE*4000h
	mov emm57.bSrcTyp, 1
	mov emm57.wSrcHdl, ax
	mov emm57.wSrcOfs, 0
	mov emm57.wSrcSeg, 0

	mov emm57.bDstTyp, 1
	mov emm57.wDstHdl, ax
	mov emm57.wDstOfs, 0
	mov emm57.wDstSeg, ?SIZE
	mov ax,5700h	;move memory region
	int 67h
	movzx ax,ah
	invoke printf, CStr( "5700,1->1: move EMS to EMS memory (non-overlapp), status=%X",lf),ax

;--- move from EMS to EMS overlapp

	mov si, offset emm57
	mov ax,handle
	mov emm57.dwSize, ?SIZE*4000h
	mov emm57.bSrcTyp, 1
	mov emm57.wSrcHdl, ax
	mov emm57.wSrcOfs, 0
	mov emm57.wSrcSeg, 0

	mov emm57.bDstTyp, 1
	mov emm57.wDstHdl, ax
	mov emm57.wDstOfs, 0
	mov emm57.wDstSeg, ?SIZE/2
	mov ax,5700h	;move memory region
	int 67h
	movzx ax,ah
	invoke printf, CStr( "5700,1->1: move EMS to EMS memory (overlapp), status=%X (92 exp)",lf),ax

;--- xchg from EMS to EMS non-overlapp

	mov si, offset emm57
	mov ax,handle
	mov emm57.dwSize, ?SIZE*4000h
	mov emm57.bSrcTyp, 1
	mov emm57.wSrcHdl, ax
	mov emm57.wSrcOfs, 0
	mov emm57.wSrcSeg, 0

	mov emm57.bDstTyp, 1
	mov emm57.wDstHdl, ax
	mov emm57.wDstOfs, 0
	mov emm57.wDstSeg, ?SIZE
	mov ax,5701h	;xchg memory region
	int 67h
	movzx ax,ah
	invoke printf, CStr( "5701,1->1: xchg EMS to EMS memory (non-overlapp), status=%X",lf),ax

;--- xchg from EMS to EMS overlapp

	mov si, offset emm57
	mov ax,handle
	mov emm57.dwSize, ?SIZE*4000h
	mov emm57.bSrcTyp, 1
	mov emm57.wSrcHdl, ax
	mov emm57.wSrcOfs, 0
	mov emm57.wSrcSeg, 0

	mov emm57.bDstTyp, 1
	mov emm57.wDstHdl, ax
	mov emm57.wDstOfs, 0
	mov emm57.wDstSeg, ?SIZE/2
	mov ax,5701h	;xchg memory region
	int 67h
	movzx ax,ah
	invoke printf, CStr( "5701,1->1: xchg EMS to EMS memory (overlapp), status=%X",lf),ax

;--- set invalid region type

	mov si, offset emm57
	mov ax,handle
	mov emm57.dwSize, ?SIZE*4000h
	mov emm57.bSrcTyp, 2
	mov emm57.wSrcHdl, ax
	mov emm57.wSrcOfs, 0
	mov emm57.wSrcSeg, 0

	mov emm57.bDstTyp, 1
	mov emm57.wDstHdl, ax
	mov emm57.wDstOfs, 0
	mov emm57.wDstSeg, ?SIZE
	mov ax,5700h	;move memory region
	int 67h
	movzx ax,ah
	invoke printf, CStr( "5700,2->1: src has invalid type (2), status=%X",lf),ax

exit2:
	mov dx,handle
	mov ah,45h	   ;free pages
	int 67h
exit:
	ret
main endp

start:
	mov ax,@data
	mov ds,ax
	mov cx,ss
	sub cx,ax
	shl cx,4
	mov ss,ax
	add sp,cx
	invoke main
	mov ah,4ch
	int 21h

	END start
