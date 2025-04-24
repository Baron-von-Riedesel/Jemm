
;--- real-mode part of fastboot.asm;
;--- this code is loaded at address 07E00h by the fastboot JLM;
;--- on entry:
;--- + cpu is still in protected-mode;
;--- + CS, SS, DS, ES, FS, GS: 16-bit selector, limit 0ffffh, base 0
;--- + ESP: 7C00h
;--- + ECX: value for CR0
;--- + EAX: 0
;--- requires Masm v6+ or JWasm v2.20+.
;--- to load a partition boot sector will work only if the
;--- BIOS supports LBA access for the disk.

	.model tiny

RESETDSK equ 0	;1=reset disk via int 13h, ah=0
BOOTDISK equ 80h
BOOTPART equ 0	;may be 1-4 to boot a partition or 0 to boot MBR

@dbgout macro chr
ifdef _DEBUG
	mov al,chr
	call printchr
endif
endm

BDESC struct
bBoot    db ?
chsStart db ?,?,?
bType    db ?
chsEnd   db ?,?,?
lbaStart dd ?
lbaSize  dd ?
BDESC ends

	.code

	org 7E00h

	.386p
	mov cr0,ecx			;enter real-mode
	db 0EAh 			;jmp far16 0000:7Exx (set CS=0000)
	dw @F, 0
bPartition db BOOTPART  ;offset 8 (contents may be changed by FASTBOOT.ASM!)
@@:
	mov cr3,eax
	.386
	mov ss,ax
	mov ds,ax
	mov es,ax
	sti
ifdef BOOTDBG
	@dbgout 'D'
	mov ax, ds:[413h]
	shl ax, 6   ;kB -> para
	push cs
	push offset @F
	push ax				;call DebugB init proc
	push 0
	retf
@@:    
endif
	@dbgout 'R'
if RESETDSK
	mov dl,BOOTDISK
	mov ah,00 			;disk reset
	int 13h
endif
	@dbgout 'B'

	mov cx,0001h		;CX+DH=cyl/head/sector
	mov dx,BOOTDISK
	mov bx,7C00h		;ES:BX=transfer address
	push es
	push bx				;push address for RETF below
	mov ax,201h			;read first sector of HD 0
	int 13h
	jc err
	@dbgout 'T'
	mov al,cs:[bPartition]
	and al,al
	jz @F
	dec al
	mov ah,0
	shl ax,4
	mov si,ax
	mov bx,055AAh
	mov dl,BOOTDISK
	mov ah,41h  ;check for int 13h extensions
	int 13h
	jc @F
;--- create a "disk address packet" onto stack
	pushd 0
	push [si+7C00h+1BEh].BDESC.lbaStart	;LBA sector# (start of partition)
	push 0
	push 7C00h	;transfer buffer (0000:7C00)
	push 1		;sectors
	push 10h	;size of packet
	mov si,sp
	mov dl,BOOTDISK
	mov ah,42h
	int 13h
	lea sp,[si+10h]
	jc err
	@dbgout 'p'
@@:
ifdef BOOTDBG
	int 3
endif
	retf				;jump to boot code
err:
	@dbgout 'e'
	@dbgout 'r'
	@dbgout 'r'
	jmp $				;stop
ifdef _DEBUG
printchr:
	push bx
	mov bh,0
	mov ah,0Eh
	int 10h
	pop bx
	ret
endif
	end
