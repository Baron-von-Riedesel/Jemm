
;--- real-mode part of fastboot.asm;
;--- this code is loaded at address 07E00h by the fastboot JLM;
;--- on entry:
;--- + cpu is still in protected-mode;
;--- + CS, SS, DS, ES, FS, GS: 16-bit selector, limit 0ffffh, base 0
;--- + ESP: 7C00h
;--- + ECX: value for CR0
;--- + EAX: 0
;--- requires Masm v6+ or JWasm.
;--- to load a partition boot sector will work only if the
;--- BIOS supports LBA access for the disk.

	.model tiny

RESETDSK equ 0	;1=reset disk via int 13h, ah=0
BOOTDISK equ 80h
BOOTPART equ 0	;may be 1-8 to boot a partition or 0 to boot MBR
BOOTADDR equ 7C00h ;address where mbr/boot sector will be loaded
CHKJMPS  equ 0	;1=check for "jmp short" at boot sector start

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
	mov bx,BOOTADDR		;ES:BX=transfer address
	push es
	push bx				;push address for RETF below
	mov ax,201h			;read first sector of HD 0
	int 13h
	jc err
	@dbgout 'T'
	mov al,cs:[bPartition]
	and al,al
	jz bsect_read
	mov bx,055AAh
	mov ah,41h			;check for int 13h extensions
	int 13h
	jc bsect_read
if 0;def BOOTDBG
	int 3
endif
	mov al,cs:[bPartition]
	dec al				;1..8 -> 0..7
	mov ah,0
	cmp al,4			;0..3?
	jb stdpart

;--- partitions 5-8 are searched in (the first and only) extended partition

	xor edi,edi
	sub al,4-1			;4-7 -> 1-4
nextext:
	push ax
	mov si,0
@@:
	cmp byte ptr [si+BOOTADDR+1BEh].BDESC.bType, 5	;extended partition?
	jz @F
	cmp byte ptr [si+BOOTADDR+1BEh].BDESC.bType, 15	;extended partition, LBA?
	jz @F
	add si,sizeof BDESC
	cmp si,4*sizeof BDESC
	jb @B
	jmp err				;no extended partition found
@@:
	and edi,edi
	jnz @F
	mov edi,[si+BOOTADDR+1BEh].BDESC.lbaStart
	jmp isfirst
@@:
	add [si+BOOTADDR+1BEh].BDESC.lbaStart,edi
isfirst:
	push [si+BOOTADDR+1BEh].BDESC.lbaStart
	push si
	call readsect
	pop si
	pop ebx
	jc err
	cmp word ptr ds:[BOOTADDR+1FEh],0AA55h
	jnz err
	pop ax
	dec al
	jnz nextext
;--- bootable partitions in extended partitions are supposed to be the first entry!
	add ds:[BOOTADDR+1BEh+BDESC.lbaStart],ebx
stdpart:
	shl ax,4
	mov si,ax
	call readsect
	jc err
	cmp word ptr ds:[BOOTADDR+1FEh],0AA55h
	jnz err
if CHKJMPS
	cmp byte ptr ds:[BOOTADDR],0EBh	;sector starts with a short jmp?
	jnz err
endif
	@dbgout 'p'
bsect_read:
ifdef BOOTDBG
	int 3
endif
	retf				;jump to boot code
err:
	call errout
	db 7,"err",13,10
	jmp $				;stop
readsect:
;--- create a "disk address packet" onto stack
	pushd 0
	push [si+BOOTADDR+1BEh].BDESC.lbaStart	;LBA sector# (start of partition)
	push 0
	push BOOTADDR;transfer buffer (0000:7C00)
	push 1		;sectors
	push 10h	;size of packet
	mov si,sp
	mov dl,BOOTDISK
	mov ah,42h
	int 13h
	lea sp,[si+10h]
	ret
errout:
	pop si
	cld
@@:
	lodsb
	push ax
	call printchr
	pop ax
	cmp al,10
	jnz @B
	jmp si
printchr:
	push bx
	mov bh,0
	mov ah,0Eh
	int 10h
	pop bx
	ret
	end
