
;--- This program check is JemmDbg has been loaded.
;--- If yes, an "int 3" is executed to wake up the debugger.

	.386
	.MODEL FLAT
	option dotname

	include jlm.inc

@pe_file_flags = @pe_file_flags and not 1

	.CODE

print_string proc
	pop esi
	@VMMCall Begin_Nest_Exec
nextitem:
	lodsb
	cmp al,0
	jz done
	mov byte ptr [ebp].Client_Reg_Struc.Client_EDX, al
	mov byte ptr [ebp].Client_Reg_Struc.Client_EAX+1, 2
	mov eax, 21h
	@VMMCall Exec_Int
	jmp nextitem
done:
	@VMMCall End_Nest_Exec
	push esi
	ret
print_string endp

main proc c

	mov eax, 4A50h		; device ID of JemmDbg
	xor edi, edi
	@VMMcall Get_DDB
	jecxz @F			; if ecx==0, JemmDbg isn't installed
	mov eax, 80000000h	; bits 0-15=0 to unload, bit 31=1 to suppress jload msg
	int 3
	ret
@@:
	call print_string
	db "JemmDbg not installed",13,10,0
	mov eax, 80000000h
	ret

main ENDP

	END main

