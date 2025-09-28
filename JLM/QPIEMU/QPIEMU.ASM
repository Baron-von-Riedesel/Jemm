
;--- JLM sample QPIEMU
;--- use Makefile to create QPIEMU.DLL

;--- QPIEMU installs a small subset of Qemm's QPI,
;--- just enough to trap ports.

	.386
	.model flat, stdcall

	.nolist
	include jlm.inc
	.list

DEVICE_ID equ 4354h

cr equ 13
lf equ 10

DLL_PROCESS_ATTACH  equ 1
DLL_PROCESS_DETACH  equ 0

PGTAB0 equ 1	;support ax=5000h - "get page table 0 physical address"

if PGTAB0
;--- this hack should be cleaned ASAP...
	include jemm.inc
	include jemm32.inc	;needed to get linear address of page directory
endif

	.data

;--- the DDB must be make public. The linker will "export" this
;--- symbol. This is the simplest method to make JLoad know the
;--- device id.

ifdef ?PE
	public export ddb	;syntax accepted since jwasm v2.19
	option dotname
.drectve segment info
	db "-subsystem:native -dll -fixed:no"
.drectve ends
else
	public ddb
endif

ddb VxD_Desc_Block <0,0,DEVICE_ID,1,0,0,"QPIEMU",0,0, v86_dispatch >

callback dd 0	; current far16 real-mode callback address

	.code

;--- dispatcher for v86 services

v86_dispatch proc

	@VMMCall Simulate_Far_Ret	;emulate a RETF in v86

	and [ebp].Client_Reg_Struc.Client_EFlags,not 1  ;clear Carry flag
	movzx eax, word ptr [ebp].Client_Reg_Struc.Client_EAX
	cmp ah, 3
	jz getversion
	cmp ah, 1Ah
	jz isio
if PGTAB0
	cmp ax, 5000h
	jz ispt0
endif
error:
	or [ebp].Client_Reg_Struc.Client_EFlags,1  ;set Carry flag
	ret
if PGTAB0
ispt0:
	mov eax,ds:[?PAGEDIR]
	and ax, 0F000h
	mov [ebp].Client_Reg_Struc.Client_EDX, eax
	ret
endif
isio:
	cmp al, 0
	jz simin
	cmp al, 1
	jz simout
	cmp al, 4
	jz simio		; generic untrapped IO
	cmp al, 6
	jz gethandler
	cmp al, 7
	jz sethandler
	cmp al, 8		; get port status
	jz getportstat
	cmp al, 9		; trap port
	jz trapport
	cmp al, 10		; untrap port
	jz untrapport
	jmp error
simin:
	mov edx, [ebp].Client_Reg_Struc.Client_EDX
	in al, dx
	mov byte ptr [ebp].Client_Reg_Struc.Client_EBX, al
	ret
simout:
	mov edx, [ebp].Client_Reg_Struc.Client_EDX
	mov al, byte ptr [ebp].Client_Reg_Struc.Client_EBX
	out dx, al
	ret
simio:
	movzx edx, word ptr [ebp].Client_Reg_Struc.Client_EDX
	mov ecx, [ebp].Client_Reg_Struc.Client_ECX
	mov eax, [ebp].Client_Reg_Struc.Client_EBX
	@VMMCall Simulate_IO
	test byte ptr [ebp].Client_Reg_Struc.Client_ECX, 24h	;OUT or STRING_IO?
	jnz @F
	mov [ebp].Client_Reg_Struc.Client_EBX, eax
@@:
	ret
gethandler:
	mov eax, [callback]
	mov word ptr [ebp].Client_Reg_Struc.Client_EDI, ax
	shr eax, 16
	mov word ptr [ebp].Client_Reg_Struc.Client_ES, ax
	ret
sethandler:
	mov ax, word ptr [ebp].Client_Reg_Struc.Client_ES
	shl eax, 16
	mov ax, word ptr [ebp].Client_Reg_Struc.Client_EDI
	mov [callback], eax
	ret
getportstat:

;--- todo

	mov byte ptr [ebp].Client_Reg_Struc.Client_EBX, 0	;0=port not trapped
	ret
trapport:
	push esi
	mov esi, offset iocb
	movzx edx, word ptr [ebp].Client_Reg_Struc.Client_EDX
	@VMMCall Install_IO_Handler
	.if ( CARRY? )
		or [ebp].Client_Reg_Struc.Client_EFlags, 1  ;set Carry flag
	.endif
	pop esi
	ret
untrapport:
	movzx edx, word ptr [ebp].Client_Reg_Struc.Client_EDX
	@VMMCall Remove_IO_Handler
	.if ( CARRY? )
		or [ebp].Client_Reg_Struc.Client_EFlags, 1  ;set Carry flag
	.endif
	ret

	align 4

v86_dispatch endp

getversion proc

	mov word ptr [ebp].Client_Reg_Struc.Client_EAX, 0703h
	mov word ptr [ebp].Client_Reg_Struc.Client_EBX, 0703h
	ret
	align 4

getversion endp

;--- io handler proc
;--- ecx=type of io, see jemm32.inc:
;---  bit 2: 0=IN, 1=OUT
;---  bit 3+4: 00=byte, 01=word, 10=dword
;---  bit 5: string IO
;---  bit 6: REP
;--- edx=port
;--- ebp=client struct
;--- eax=client's eax
;--- out: EAX=value read ( will be stored in EAX if IN )

iocb proc

	push ecx
	push edx

	push [ebp].Client_Reg_Struc.Client_EFlags
	push [ebp].Client_Reg_Struc.Client_ECX
	push [ebp].Client_Reg_Struc.Client_EDX

;--- setup registers
;--- EAX: current client reg
;--- EBX: current client reg
;--- CL: bit 2: 0=IN, 1=OUT
;---     bit 3+4: 00=BYTE, 01=WORD, 10=DWORD
;--- CH: bit 1: 1=IF (QPI, undocumented)
;--- DX=port

	mov ch, byte ptr [ebp].Client_Reg_Struc.Client_EFlags+1
	and ch, 2

	and byte ptr [ebp].Client_Reg_Struc.Client_EFlags+1, not 1+2	; reset TF & IF!
	mov word ptr [ebp].Client_Reg_Struc.Client_EDX, dx

	mov word ptr [ebp].Client_Reg_Struc.Client_ECX, cx

	@VMMCall Begin_Nest_Exec 	;start nested execution
	movzx edx, word ptr [callback+0]
	movzx ecx, word ptr [callback+2]
	@VMMCall Simulate_Far_Call
	@VMMCall Resume_Exec		;run the VM
	@VMMCall End_Nest_Exec		;end nested execution

	pop [ebp].Client_Reg_Struc.Client_EDX
	pop [ebp].Client_Reg_Struc.Client_ECX
	pop [ebp].Client_Reg_Struc.Client_EFlags

	mov eax, [ebp].Client_Reg_Struc.Client_EAX

	pop edx
	pop ecx
	ret

	align 4

iocb endp

;--- install the JLM: just set eax=1
;--- this tells JLOAD that it's ok to add IOTRAP to the list of
;--- loaded modules.

install proc uses esi pcomm:ptr JLCOMM

	mov eax,1
	ret
	align 4

install endp

;--- deinstall the JLM:

deinstall proc pcomm:ptr JLCOMM

	cmp [callback], 0
	setz al
	movzx eax, al
	ret
	align 4

deinstall endp

DllMain proc stdcall public hModule:dword, dwReason:dword, dwRes:dword

	mov eax,dwReason
	cmp eax,DLL_PROCESS_ATTACH
	jnz @F
	invoke install, dwRes
	jmp exit
@@:
	cmp eax,DLL_PROCESS_DETACH
	jnz @F
	invoke deinstall, dwRes
@@:
exit:
	ret
	align 4

DllMain endp

	end DllMain
