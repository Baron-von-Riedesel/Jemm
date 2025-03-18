
;--- JLM sample GENERIC
;--- use Makefile to create GENERIC.DLL

;--- GENERIC is a very simple JLM. It doesn't hook v86-interrupt vectors.
;--- To be called from v86-mode, its entry point must be obtained by the
;--- caller.

	.386
	.model flat, stdcall

	.nolist
	include jlm.inc
	.list

DEVICE_ID equ 6660h

cr equ 13
lf equ 10

DLL_PROCESS_ATTACH  equ 1
DLL_PROCESS_DETACH  equ 0

	.data

;--- the DDB must be make public. The linker will "export" this
;--- symbol. This is the simplest method to make JLoad know the
;--- device id.

	public ddb

ddb VxD_Desc_Block <0,0,DEVICE_ID,1,0,0,"GENERIC",0, 0, v86_dispatch>

szHello db "Hello from JLM GENERIC",cr,lf,0

	.code

;--- dispatcher for v86 services

v86_dispatch proc

	@VMMCall Simulate_Far_Ret	;emulate a RETF in v86

	and [ebp].Client_Reg_Struc.Client_EFlags,not 1  ;clear Carry flag
	movzx eax, word ptr [ebp].Client_Reg_Struc.Client_EAX
	cmp eax,0
	jz getversion
	cmp eax,1
	jz display_hello
	or [ebp].Client_Reg_Struc.Client_EFlags,1  ;set Carry flag
	ret
	align 4

v86_dispatch endp

getversion proc

	mov word ptr [ebp].Client_Reg_Struc.Client_EAX, 0100h
	ret
	align 4

getversion endp

display_hello proc uses esi

	@VMMCall Begin_Nest_Exec 	;start nested execution
	mov esi, offset szHello
@@:
	lodsb
	and al,al
	jz done

;--- Call int 21h, ah=2 in v86-mode.
;--- Be aware that in Jemm's context is no DOS extender installed.
;--- So there is no translation for DOS functions which use pointers.

	mov byte ptr [ebp].Client_Reg_Struc.Client_EDX,al
	mov byte ptr [ebp].Client_Reg_Struc.Client_EAX+1,2
	mov eax,21h
	@VMMCall Exec_Int
	jmp @B
done:
	@VMMCall End_Nest_Exec		;end nested execution
	ret
	align 4

display_hello endp

;--- install the JLM: just set eax=1
;--- this tells JLOAD that it's ok to add GENERIC to the list of
;--- loaded modules.

install proc uses esi pcomm:ptr JLCOMM

	mov eax,1
	ret
	align 4

install endp

;--- deinstall the JLM: just set eax=1.
;--- this tells JLOAD that it's ok to remove the module.

deinstall proc pcomm:ptr JLCOMM

	mov eax,1
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
