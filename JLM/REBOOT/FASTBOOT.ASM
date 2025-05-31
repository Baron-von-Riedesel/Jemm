
;--- Sample how to handle DEVICE_REBOOT_NOTIFY control message;
;--- handles fastboot only.
;--- Requires Jemm v5.86+.
;--- To be assembled with JWasm v2.19+; if Masm is to be used,
;--- FASTBRM.BIN must be converted to FASTBRM.INC.
;--- If a link step is added, the linker is supposed to export ddb.

	.386p
	.MODEL FLAT, stdcall
	option casemap:none

	include jlm.inc

ifndef BOOTSECT
BOOTSECT equ 1
endif
ifndef LDDBG  ;support API "load DebugB"?
LDDBG equ 1
endif
ifndef LDI13EXT ;support API "load Int 13h extension"?
LDI13EXT equ 1
endif

DLL_PROCESS_ATTACH equ 1
DLL_PROCESS_DETACH equ 0   

DEVICE_ID equ 4435h

;--- equates from jemm32.inc
REAL_CODE_SEL   equ 4 * 8
REAL_DATA_SEL   equ 5 * 8

RMCOMM struct
	db ?,?,?	;mov cr0,ecx
	db ?		;jmp far16 opcode (0EAh)
	dw ?,?		;offset, segment of jmp far16
bPartition db ?
bDisk db ?
if LDDBG or LDI13EXT
bFlags db ?     ;1:call DebugB init, 1: stop in DebugB; 2: 1=call int13 extension init.
endif
RMCOMM ends

ifdef @pe_file_flags   ;defined by JWasm if option -pe is set
	option dotname
.drectve segment info
	db "-dll "
	db "-subsystem:native "
	db "-fixed:no "
.drectve ends

.hdr$2 segment flat
	db "PX"
.hdr$2 ends
EXPORT equ <export>
else
EXPORT equ <>
endif

	.const

	public EXPORT ddb

ddb VxD_Desc_Block <0,0,DEVICE_ID,1,0,0,"REBOOT",0, ctrlproc, v86_dispatch >

helptxt label byte
	db "Usage:",13,10
	db "jload fastboot.dll [options]",13,10
	db "options:",13,10
	db " /Dn",9,"set Hard Disk to boot from; n=0..7; default 0",13,10
	db " /Pn",9,"set Partition to boot from; n=1..8; no default",13,10
if BOOTSECT
	db ' /B:file set File to boot from; file=name of file to be used as boot sector',13,10
endif
	db 0
fileerror label byte
	db "file access error or invalid format",13,10
	db 0

	.data

if LDDBG
dwStartDbg dd 0
dwSizeDbg  dd 0
endif
if LDI13EXT
dwStartI13 dd 0
dwSizeI13  dd 0
endif
rmcode label byte
ifdef __JWASM__
	incbin <fastbrm.bin>
else
	include <fastbrm.inc>	;translated by bin2inc
endif
sizermcode equ $ - rmcode

if BOOTSECT
	.data?
bsbuffer db 512 dup (?)
endif

	.CODE

;--- V86 API
;--- AH=0: get version
;--- AH=1: set disk (AL=disk, HDs only)
;--- AH=2: set partition (AL=partition, one-based)
;--- AH=3: set boot debugger (DS:SI=address, ECX=size)
;--- AH=4: set int 13h extension (DS:SI=address, ECX=size)

v86_dispatch proc

	@VMMCall Simulate_Far_Ret	;emulate a RETF in v86
	and [ebp].Client_Reg_Struc.Client_EFlags,not 1  ;clear Carry flag
	movzx eax, word ptr [ebp].Client_Reg_Struc.Client_EAX
	cmp ah,0
	jz getversion
	cmp ah,1
	jz setdisk
	cmp ah,2
	jz setpart
if LDDBG
	cmp ah,3
	jz setdbg
endif
if LDI13EXT
	cmp ah,4
	jz seti13ext
endif
error:
	or [ebp].Client_Reg_Struc.Client_EFlags,1  ;set Carry flag
	ret
getversion:
	mov word ptr [ebp].Client_Reg_Struc.Client_EAX, 0101h   ;bit 0 of AH signals FASTBOOT
	ret
setdisk:
	mov rmcode.RMCOMM.bDisk,al
	ret
setpart:
	mov rmcode.RMCOMM.bPartition,al
	ret
if LDDBG
setdbg:
	call ReleaseDbg
	call StoreFile
	jc @F
	mov dwStartDbg, eax
	mov dwSizeDbg, ecx
@@:
	ret
endif
if LDI13EXT
seti13ext:
	call ReleaseI13
	call StoreFile
	jc @F
	mov dwStartI13, eax
	mov dwSizeI13, ecx
@@:
	ret
endif
v86_dispatch endp

;--- control proc: handle messages from Jemm

ctrlproc proc
	cmp eax, DEVICE_REBOOT_NOTIFY
	jz reboot_notify
@@:
	clc
	ret
reboot_notify:
	test bl,1      ;fastboot flag?
	jz @B

if LDDBG or LDI13EXT
;	mov rmcode.RMCOMM.bFlags,0
endif

if LDI13EXT
	mov ecx,dwSizeI13
	jecxz no_i13ext
	mov edi,8000h
	mov esi,dwStartI13
	cld
	rep movsb
	or rmcode.RMCOMM.bFlags,4
no_i13ext:
endif

if LDDBG
	mov ecx,dwSizeDbg
	jecxz no_dbginit
	add ecx,1024-1
	movzx edi,word ptr ds:[413h]
	shl edi,10        ;convert kB to bytes
;--- if already loaded, don't change ds:[413h]
	cmp byte ptr [edi],0E9h  ;jmp near16 opcode?
	jnz adjmem
	movzx eax,word ptr [edi+1]
	cmp dword ptr [edi+eax-1],0DEADBEEFh	;DebugB signature?
	jz @F
adjmem:
	shr ecx,10        ;convert bytes to kB
	sub ds:[413h],cx
	shl ecx,10
	sub edi,ecx
@@:
	mov esi,dwStartDbg
	cld
	rep movsb
	or rmcode.RMCOMM.bFlags,1+2
no_dbginit:
	mov ax,word ptr ds:[4+2]
	shr ax,6				   ;para -> kB
	cmp ax,ds:[413h]
	jb @F
	or rmcode.RMCOMM.bFlags,2
@@:
endif

;--- If fastboot is on, one cannot call v86-mode.
;--- IVT vectors have been restored already, VDS bit has been cleared.
;--- So copy 16-bit code to address 07e00h, setup stack and registers
;--- EAX & ECX, finally jump to 7E00h ( still in protected-mode ).

	mov edi, 7E00h
	mov esi, offset rmcode
	mov ecx, sizermcode
	cld
	rep movsb
if BOOTSECT
	cmp rmcode.RMCOMM.bPartition,-1
	jnz @F
	mov edi, 7C00h
	mov esi, offset bsbuffer
	mov ecx, 512/4
	rep movsd
@@:
endif
	xor edx, edx
	push edx
	pushw -1
	LIDT FWORD ptr [esp]	; reset the IDT to 0:ffffh
	MOV AX,REAL_DATA_SEL	; before returning to real-mode set the
	MOV DS,EAX				; segment register caches
	MOV ES,EAX
	MOV FS,EAX
	MOV GS,EAX
	MOV SS,EAX				; set SS:ESP
	MOV ESP,7C00h
	MOV ECX,CR0 			; prepare to reset CR0 PE and PG bits
	AND ECX,7FFFFFFEH
	XOR EAX,EAX
	db 66h, 0eah			; jmp far16 20h:7E00h
	dw 7E00h, REAL_CODE_SEL

ctrlproc endp

cputs proc uses esi
	mov esi, eax
	cld
nextitem:
	lodsb
	and al,al
	jz done
	mov byte ptr [ebp].Client_Reg_Struc.Client_EDX,al
	mov byte ptr [ebp].Client_Reg_Struc.Client_EAX+1,2
	mov eax,21h
	@VMMCall Exec_Int
	jmp nextitem
done:
	ret
cputs endp

;--- display usage

helpout proc uses ebp
	@VMMCall Get_Cur_VM_Handle
	mov ebp,[ebx].cb_s.CB_Client_Pointer
	@VMMCall Begin_Nest_Exec	 ;start nested execution
	mov eax,offset helptxt
	call cputs
	@VMMCall End_Nest_Exec		 ;end nested execution
	ret
helpout endp

if LDDBG

ReleaseDbg proc uses esi
	mov ecx,dwSizeDbg
	jecxz exit
	add ecx,4096-1
	shr ecx,12
	mov esi,dwStartDbg
@@:
	push ecx
	push 0
	push esi
	@VMMCall _PageFree
	add esp,2*4
	pop ecx
	add esi,1000h
	loop @B
exit:
	mov dwSizeDbg,0
	mov dwStartDbg,0
	ret
ReleaseDbg endp

endif

if LDI13EXT

ReleaseI13 proc uses esi
	mov ecx,dwSizeI13
	jecxz exit
	add ecx,4096-1
	shr ecx,12
	mov esi,dwStartI13
@@:
	push ecx
	push 0
	push esi
	@VMMCall _PageFree
	add esp,2*4
	pop ecx
	add esi,1000h
	loop @B
exit:
	mov dwSizeI13,0
	mov dwStartI13,0
	ret
ReleaseI13 endp

endif

if LDDBG or LDI13EXT

;--- v86 API ah=3/4: copy conv. memory block to extended memory
;--- in: v86-ds:si=address
;---     v86-ecx=size of region
;--- out: NC if ok
;---      eax=ext. memory address
;---      ecx=size of region

StoreFile proc uses esi edi
	mov eax, [ebp].Client_Reg_Struc.Client_ECX
	and eax, eax
	jz exit
	add eax,4096-1
	shr eax,12
	mov esi,eax

	push 0
	push eax
	push PR_SYSTEM
	@VMMCall _PageReserve	 ;allocate address space for debugger
	add esp,3*4
	cmp eax,-1
	jz error
	mov edi, eax

	shr eax, 12 			 ;convert linear address to page number
	push PC_INCR or PC_WRITEABLE
	push 0
	push PD_FIXED			 ;???
	push esi
	push eax
	@VMMCall _PageCommit
	add esp,5*4
	and eax,eax
	jz error

	movzx esi, word ptr [ebp].Client_Reg_Struc.Client_DS
	shl esi, 4
	movzx eax, word ptr [ebp].Client_Reg_Struc.Client_ESI
	add esi, eax
	mov ecx,[ebp].Client_Reg_Struc.Client_ECX
	mov eax, edi
	push ecx
	rep movsb
	pop ecx
exit:
	clc
	ret
error:
	or [ebp].Client_Reg_Struc.Client_EFlags,1  ;set Carry flag
	stc
	ret
StoreFile endp

endif

if BOOTSECT

	include fileacc.inc

;--- read "boot sector" file
;--- in: esi = start of name in cmdline
;--- out: esi = behind name
;---      C if error occured

ReadBSFile proc uses ebx edi ebp
	push ecx
	@VMMCall Get_Cur_VM_Handle
	mov ebp,[ebx].cb_s.CB_Client_Pointer
	pop ecx
	@VMMCall GetDOSBuffer
	mov edi,eax

	@VMMCall Begin_Nest_Exec

	mov edx,edi
	mov ecx,128
@@:
	lodsb
	stosb
	cmp al,' '
	jbe @F
	loop @B
	inc esi
@@:
	dec esi
	mov byte ptr [edi-1],0
	mov edi,edx
	or ebx,-1
	call OpenFile
	jc exit
	mov ebx,eax
	call GetFileSize
	jc exit
	cmp eax,512
	stc
	jnz exit
	mov edx,edi
	mov ecx,eax
	call ReadFile
	jc exit
	cmp eax,512
	stc
	jnz exit
	push esi
	mov esi, edi
	mov edi, offset bsbuffer
	mov ecx, 512/4
	rep movsd
	pop esi
	clc
exit:
	pushfd
	jnc @F
	mov eax,offset fileerror
	call cputs
@@:
	cmp ebx,-1
	jz @F
	call CloseFile
@@:
	@VMMCall End_Nest_Exec
	popfd
	ret
ReadBSFile endp

endif

;--- scan cmdline
;--- options /P1 .. /P8
;--- options /D0 .. /D7
;--- option  /B:filename

Init proc uses esi pComm:ptr
	mov esi,pComm
	mov esi,[esi].JLCOMM.lpCmdLine
	cld
	.while byte ptr [esi]
		lodsb
		.if al == '/' || al == '-'
			call getoption
			jc error
		.elseif al == ' ' || al == 9
			.continue
		.else
			.break .if al == 13	;if loaded as device driver
			call helpout
			jmp error
		.endif
	.endw
	mov eax,1
	ret
error:
	xor eax,eax
	ret
getoption:
	mov ax,[esi]
	or al,20h
	.if al == 'p' && ah >= '1' && ah <= '8'
		mov al,ah
		sub al,'0'
		mov rmcode.RMCOMM.bPartition,al
		add esi,2
	.elseif al == 'd' && ah >= '0' && ah <= '7'
		mov al,ah
		sub al,'0'
		or al,80h
		mov rmcode.RMCOMM.bDisk,al
		add esi,2
if BOOTSECT
	.elseif al == 'b' && ah == ':'
		mov ecx, pComm
		add esi,2
		invoke ReadBSFile;may return with C=error
		mov rmcode.RMCOMM.bPartition,-1  ;disables boot sector load
endif
	.else
		call helpout
		stc
	.endif
	retn
Init endp

Deinit proc
if LDDBG
	call ReleaseDbg
endif
if LDI13EXT
	call ReleaseI13
endif
	mov eax,1
	ret
Deinit endp

DllMain PROC stdcall hModule:dword, dwReason:dword, dwRes:dword

	mov eax,dwReason
	cmp eax, DLL_PROCESS_ATTACH
	jnz @F
	invoke Init, dwRes
	jmp exit
@@:
	cmp eax,DLL_PROCESS_DETACH
	jnz @F
	call Deinit
@@:
exit:
	ret
DllMain endp

	END DllMain

