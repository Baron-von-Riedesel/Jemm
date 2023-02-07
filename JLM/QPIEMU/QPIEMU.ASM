
;--- JLM sample QPIEMU
;--- use Makefile to create QPIEMU.DLL

;--- IOTRAP installs a small subset of Qemm's QPI.
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

	.data

;--- the DDB must be make public. The linker will "export" this
;--- symbol. This is the simplest method to make JLoad know the
;--- device id.

	public ddb

ddb VxD_Desc_Block <0,0,DEVICE_ID,1,0,0,"QPIEMU",0,0, dispatch >

szHello db "Hello from JLM QPIEMU",cr,lf,0

cntCB dd 0
callbacks label dword
	dd 1*2 dup (0)	;allow 1 callback only

	.code

;--- dispatcher for v86 services

dispatch proc

	@VMMCall Simulate_Far_Ret	;emulate a RETF in v86

	and [ebp].Client_Reg_Struc.Client_EFlags,not 1  ;clear Carry flag
	movzx eax, word ptr [ebp].Client_Reg_Struc.Client_EAX
	cmp ah, 3
	jz getversion
	cmp ah, 1Ah
	jz isio
error:
	or [ebp].Client_Reg_Struc.Client_EFlags,1  ;set Carry flag
	ret
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
	mov eax, [callbacks]
	mov word ptr [ebp].Client_Reg_Struc.Client_EDI, ax
	shr eax, 16
	mov word ptr [ebp].Client_Reg_Struc.Client_ES, ax
	ret
sethandler:
	mov ax, word ptr [ebp].Client_Reg_Struc.Client_ES
	shl eax, 16
	mov ax, word ptr [ebp].Client_Reg_Struc.Client_EDI
	mov [callbacks], eax
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

dispatch endp

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

if 1 ;if the client is to be called in v86-mode

	push ecx
	push edx
;	push eax

	push [ebp].Client_Reg_Struc.Client_EFlags
	push [ebp].Client_Reg_Struc.Client_ECX
	push [ebp].Client_Reg_Struc.Client_EDX

;--- setup registers
;--- EAX: current client reg
;--- EBX: current client reg
;--- CL: bit 2: 0=IN, 1=OUT
;---     bit 3+4: 00=BYTE, 01=WORD, 10=DWORD
;--- DX=port

	and byte ptr [ebp].Client_Reg_Struc.Client_EFlags+1, not 1+2	; reset TF & IF!
	mov word ptr [ebp].Client_Reg_Struc.Client_EDX, dx
	mov ch, 2	; copied from Qemm
	mov word ptr [ebp].Client_Reg_Struc.Client_ECX, cx

	@VMMCall Begin_Nest_Exec 	;start nested execution
	movzx edx, word ptr [callbacks+0]
	movzx ecx, word ptr [callbacks+2]
	@VMMCall Simulate_Far_Call
	@VMMCall Resume_Exec		;run the VM
	@VMMCall End_Nest_Exec		;end nested execution

	pop [ebp].Client_Reg_Struc.Client_EDX
	pop [ebp].Client_Reg_Struc.Client_ECX
	pop [ebp].Client_Reg_Struc.Client_EFlags

	mov eax, [ebp].Client_Reg_Struc.Client_EAX
;	pop eax
	pop edx
	pop ecx
	ret

else ;if the client is to be called in protected-mode

PF32 typedef ptr far32

	pushad
	push ecx
	push edx
	push eax
	sub esp,8
	sgdt [esp]
	mov eax,[esp+2]
	add esp,8
	mov esi, offset callbacks
	mov ecx, cntCB

	.while ecx
		push ecx
		push eax
		lodsd
		push CODE16_SEL
		pushw 0
		push ax
		shr eax,16
		shl eax, 4
		mov edx,[esp+2*4]
		mov [edx+CODE16_SEL+2],ax
		mov [edx+DATA16_SEL+2],ax
		shr eax,16
		mov [edx+CODE16_SEL+4],al
		mov [edx+DATA16_SEL+4],al
		lodsd
		mov ebx, eax
		mov eax,[esp+4*4+0]
		mov edx,[esp+4*4+4]
		mov ecx,[esp+4*4+8]
		push ds
		push DATA16_SEL
		pop ds
		call PF32 ptr [esp+4]
		pop ds
		add esp,2*4
		pop eax
		pop ecx
		dec ecx
	.endw

	add esp,3*4
	popad
	ret
endif
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

	cmp [callbacks], 0
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
