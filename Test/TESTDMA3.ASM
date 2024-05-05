
;--- test FD read in UMB
;--- using Int 13h
;--- this variant ensures that a 64kb border is crossed,
;--- forcing the EMM to either "auto remap" PTEs (EMM386) or
;--- use the DMA buffer (Jemm).

	.286
	.model small
	.stack 2048
	.dosseg
	option casemap:none
	.386

?BSIZE equ 8000h

CStr macro text:vararg
local sym
	.const
sym db text,0
	.code
	exitm <offset sym>
endm

lf equ 10

DDS struct
dwSize dd ?
dwOfs  dd ?
wSeg   dw ?
wID    dw ?
dwPhys dd ?
DDS ends

	.data?

dds DDS <>

	.code

	include printf.inc

writefile proc c pName:ptr, pBuffer:ptr far16, wSize:word
	mov dx, pName
	xor cx, cx
	mov ax,3c00h
	int 21h
	jc fail1
	mov bx, ax
	push ds
	lds dx, pBuffer
	mov cx, wSize
	mov ax, 4000h
	int 21h
	pop ds
	jc fail2
	mov ah, 3Eh
	int 21h
	ret
fail1:
	invoke printf, CStr("create file failed",10)
	ret
fail2:
	invoke printf, CStr("write file failed",10)
	ret
writefile endp

main proc c

local stat1:word
local stat2:word
local wSeg:word

;--- requires VDS

	xor ax, ax
	mov es, ax
	test byte ptr es:[47bh],20h
	jz novds
	mov ax,8102h
	mov dx,0000
	int 4bh
	jnc @F
novds:
	invoke printf, CStr("VDS not installed",lf)
	jmp exit
@@:

	mov ax, 5802h		;get status umb
	int 21h
	xor ah,ah
	mov stat1, ax

	mov ax, 5800h		;get memory alloc strategy
	int 21h
	xor ah,ah
	mov stat2, ax

	mov bx, 81h			;first high,then low
	mov ax, 5801h		;set memory alloc strat
	int 21h
	mov bx, 1			;include umbs
	mov ax, 5803h		;umb link restore
	int 21h

	mov bx, ?BSIZE shr 4; allocate mem block
	mov ah, 48h
	int 21h
	jnc @F
	invoke printf, CStr("no free %ukB block found in Upper Memory",10), ?BSIZE shr 10
	jmp exit
@@:
	mov wSeg, ax
	mov es, ax
	xor di, di
	mov cx, ?BSIZE
	mov al, 00
	rep stosb

;--- call VDS to see when a 4 KB block isn't contiguous or crosses a 64kb border
	push ds
	pop es

	mov cx, ?BSIZE shr 12
	mov dds.wSeg, 0
	movzx eax, wSeg
	shl eax, 4
nexttry:
	mov di, offset dds
	mov dds.dwSize, 1000h
	mov dds.dwOfs, eax
	push eax
	mov dx, (1 shl 2) or (1 shl 4)	; b2=1:don't alloc buffer, b4=1:64kb crossing disallowed
	mov ax, 8103h
	int 4Bh
	jc found			; found an address that requires remap/buffer
	xor dx, dx
	mov ax, 8104h		; unlock block
	int 4Bh
	pop eax
	add eax, 1000h
	loop nexttry
	invoke printf, CStr("no uncontiguous 4kB block found",10)
	jmp exit
found:
	pop eax
	shr eax, 4
	mov wSeg, ax

	mov es, wSeg		; es:bx=transfer buffer
	mov bx, 0
	mov cx, 1			; cl[0-5]: sector#; ch+cl[6-7]:cylinder
	mov dh, 0			; dh=head
	mov dl, 0			; dl=0 -> A:
	mov ax, 0208h		; al=# of sectors to read
	int 13h
	jc error
	invoke printf, CStr("reading drive A: ok",10)
	mov ax, wSeg
	invoke writefile, CStr("~XXX.TMP"), ax::bx, 200h*8
	jmp exit
error:
	movzx ax, ah
	invoke printf, CStr("reading drive A: failed, error code=%X",10), ax
exit:
	mov bx, stat1
	mov ax, 5803h
	int 21h
	mov bx, stat2
	mov ax, 5801h		; set memory alloc strag
	int 21h
	ret
main endp

start:
	mov ax, @data
	mov ds, ax
	mov bx, ss
	sub bx, ax
	shl bx, 4
	mov ss, ax
	add sp, bx
	call main
	mov ah, 4Ch
	int 21h

	END start
