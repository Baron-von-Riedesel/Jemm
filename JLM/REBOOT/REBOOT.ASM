
;--- sample how to handle DEVICE_REBOOT_NOTIFY control message
;--- requires Jemm v5.86+

	.386
	.MODEL FLAT, stdcall
	option casemap:none

	include jlm.inc

DLL_PROCESS_ATTACH equ 1
DLL_PROCESS_DETACH equ 0   

DEVICE_ID equ 4435h

	.data

	public ddb

ddb VxD_Desc_Block <0,0,DEVICE_ID,1,0,0,"REBOOT",0, ctrlproc >

string1 db 13,10,"rebooting - press a key...",0

	.CODE

ctrlproc proc
	cmp eax, DEVICE_REBOOT_NOTIFY
	jz reboot_notify
	clc
	ret
reboot_notify:
	@VMMCall Begin_Nest_Exec	 ;start nested execution
	mov eax,offset string1
	call printstring
	mov byte ptr [ebp].Client_Reg_Struc.Client_EAX+1, 0
	mov eax,16h
	@VMMCall Exec_Int
	@VMMCall End_Nest_Exec		 ;end nested execution
	clc
	ret
ctrlproc endp

printstring proc uses esi
	mov esi, eax
	cld
nextitem:
	lodsb
	and al,al
	jz done
	mov byte ptr [ebp].Client_Reg_Struc.Client_EAX, al
	mov byte ptr [ebp].Client_Reg_Struc.Client_EAX+1, 0Eh
	mov eax,10h
	@VMMCall Exec_Int
	jmp nextitem
done:
	ret
printstring endp

DllMain PROC stdcall hModule:dword, dwReason:dword, dwRes:dword

	mov eax,dwReason
	cmp eax, DLL_PROCESS_ATTACH
	jnz @F
	mov eax,1
	jmp exit
@@:
	cmp eax,DLL_PROCESS_DETACH
	jnz @F
	mov eax,1
@@:
exit:
	ret
DllMain endp

	END DllMain

