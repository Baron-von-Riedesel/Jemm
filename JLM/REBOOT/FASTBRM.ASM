
;--- real-mode part of the fastboot JLM;
;--- this code is moved to address 07E00h by the fastboot JLM;
;--- on entry:
;--- + cpu is still in protected-mode;
;--- + CS, SS, DS, ES, FS, GS: 16-bit selector, limit 0ffffh, base 0
;--- + ESP: 7C00h
;--- + ECX: value for CR0
;--- + EAX: 0
;
;--- To assemble use Masm v6+ or JWasm.
;
;--- To load a partition boot sector will work only if the
;--- BIOS supports LBA access for the disk.

	.model tiny

RESETDSK equ 0	;1=reset disk via int 13h, ah=0
BOOTDISK equ 80h;default boot HD
BOOTPART equ 0	;may be 1-8 to boot a partition or 0 to boot MBR
BOOTADDR equ 7C00h ;address where mbr/boot sector will be loaded
CHKJMPS  equ 0	;1=check for "jmp short" at boot sector start

ifndef BOOTSECT
BOOTSECT equ 1	;1=support option /B:boot_sector_file
endif
ifndef BOOTDBG  ;must match setting in fastboot.asm
BOOTDBG equ 1	;1=check for presence of DebugB and initialize it
endif

@dbgout macro chr
ifdef _DEBUG
	mov al,chr
	call printchr
endif
endm

;--- needed if an extended partition has to be scanned.
BDESC struct
bBoot    db ?
chsStart db ?,?,?   ;
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
bDisk      db BOOTDISK  ;offset 9 (contents may be changed by FASTBOOT.ASM!)
if BOOTDBG
bDbgFlags  db 0			;bit 0:1=initialize DebugB; bit 1:1=stop in debugger
endif
@@:
	mov cr3,eax
	.386
	mov ss,ax
	mov ds,ax
	mov es,ax
	sti
if BOOTDBG
	test cs:[bDbgFlags],1
	jz @F
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
	mov dl,cs:[bDisk]
	mov ah,00 			;disk reset
	int 13h
endif
	@dbgout 'B'

	mov cx,0001h		;CX+DH=cyl/head/sector
	movzx dx,cs:[bDisk]
	mov bx,BOOTADDR		;ES:BX=transfer address
	push es
	push bx				;push address for RETF below
if BOOTSECT
	cmp cs:[bPartition],-1  ;boot sector loaded as file?
	jz bsect_read           ;then it has been moved to 7C00h already
endif
	mov ax,201h			;read first sector of HD
	int 13h
	jc err
	@dbgout 'T'
	mov al,cs:[bPartition]
	and al,al
	jz bsect_read
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
if BOOTDBG
	test cs:[bDbgFlags],2
	jz @F
	int 3
@@:
endif
	retf				;jump to boot code
err:
	call errout
	db 7,"err",13,10
	jmp $				;stop

readsect:
;--- si = 0,10h,20h,30h
	mov bx,055AAh
	mov ah,41h			;check for int 13h extensions
	int 13h
	jc readsectchs1
	cmp bx,0AA55h
	jnz readsectchs1
	cmp [si+BOOTADDR+1BEh].BDESC.bType,7
	jb readsectchs    
	cmp [si+BOOTADDR+1BEh].BDESC.bType,0Bh	;FAT32 CHS?
	jz readsectchs    
readsectlba:
;--- create a "disk address packet" onto stack
	pushd 0
	push [si+BOOTADDR+1BEh].BDESC.lbaStart	;LBA sector# (start of partition)
	push 0
	push BOOTADDR;transfer buffer (0000:7C00)
	push 1		;sectors
	push 10h	;size of packet
	mov si,sp
	mov dl,cs:[bDisk]
	mov ah,42h
	int 13h
	lea sp,[si+10h]
	ret
readsectchs:
;--- logical partitions inside extended partitions usually have type 5, although LBA must be used!
	cmp byte ptr [si+BOOTADDR+1BEh].BDESC.chsStart+2,0ffh
	jnz @F
	cmp word ptr [si+BOOTADDR+1BEh].BDESC.chsStart+0,0fffeh
	jnc readsectlba
@@:
readsectchs1:
	mov bx,BOOTADDR
	mov dh,[si+BOOTADDR+1BEh].BDESC.chsStart+0
	mov cx,word ptr [si+BOOTADDR+1BEh].BDESC.chsStart+1
	mov ax,201h
	int 13h
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
