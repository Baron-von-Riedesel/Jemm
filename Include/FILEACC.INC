
;--- dos file access for JLMs
;--- although addresses are linear, they must
;--- be within 64 kB distance of v86 DS register.

w	textequ <word ptr>

;--- open file (for reading)
;--- edx = file name
;--- out: ax=handle

OpenFile proc
	movzx eax,word ptr [ebp].Client_Reg_Struc.Client_DS
	shl eax, 4
	sub edx, eax
	mov w [ebp].Client_Reg_Struc.Client_EDX, dx
	mov w [ebp].Client_Reg_Struc.Client_EAX, 3D00h
	mov eax,21h
	@VMMCall Exec_Int
	mov ax,w [ebp].Client_Reg_Struc.Client_EAX
	bt [ebp].Client_Reg_Struc.Client_EFlags,0
	ret
OpenFile endp

;--- close file
;--- ebx = file handle

CloseFile proc
	mov w [ebp].Client_Reg_Struc.Client_EBX, bx
	mov w [ebp].Client_Reg_Struc.Client_EAX, 3E00h
	mov eax,21h
	@VMMCall Exec_Int
	bt [ebp].Client_Reg_Struc.Client_EFlags,0
	ret
CloseFile endp

;--- get file size
;--- ebx = file handle
;--- out: eax=file size

GetFileSize proc
	mov w [ebp].Client_Reg_Struc.Client_EBX, bx
	mov w [ebp].Client_Reg_Struc.Client_EAX, 4202h   ;goto EOF
	mov w [ebp].Client_Reg_Struc.Client_ECX, 0
	mov w [ebp].Client_Reg_Struc.Client_EDX, 0
	mov eax,21h
	@VMMCall Exec_Int
	bt [ebp].Client_Reg_Struc.Client_EFlags,0
	jc exit
	mov ax, w [ebp].Client_Reg_Struc.Client_EDX
	shl eax, 16
	mov ax, w [ebp].Client_Reg_Struc.Client_EAX
	push eax
	mov w [ebp].Client_Reg_Struc.Client_EAX, 4200h	 ;goto start
	mov w [ebp].Client_Reg_Struc.Client_ECX, 0
	mov w [ebp].Client_Reg_Struc.Client_EDX, 0
	mov eax,21h
	@VMMCall Exec_Int
	pop eax
	bt [ebp].Client_Reg_Struc.Client_EFlags,0
exit:
	ret
GetFileSize endp

;--- Read file into buffer
;--- bx = file handle
;--- cx = bytes to read
;--- edx = buffer (in conv. memory)
;--- out: eax=bytes read

ReadFile proc
	movzx eax,w [ebp].Client_Reg_Struc.Client_DS
	shl eax, 4
	sub edx, eax
	mov w [ebp].Client_Reg_Struc.Client_EBX, bx
	mov w [ebp].Client_Reg_Struc.Client_ECX, cx
	mov w [ebp].Client_Reg_Struc.Client_EDX, dx
	mov w [ebp].Client_Reg_Struc.Client_EAX, 3F00h
	mov eax,21h
	@VMMCall Exec_Int
	movzx eax, w [ebp].Client_Reg_Struc.Client_EAX
	bt [ebp].Client_Reg_Struc.Client_EFlags,0
	ret
ReadFile endp

