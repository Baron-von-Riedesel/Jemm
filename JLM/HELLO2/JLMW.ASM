
;--- helpers for (Watcom) C

	.386
    .model flat
    
	include jlm.inc

	.code

Get_Cur_VM_Handle proc stdcall public uses ebx
    VMMCall Get_Cur_VM_Handle
    mov eax, ebx
    ret
    align 4
Get_Cur_VM_Handle endp

Begin_Nest_Exec proc stdcall public uses ebp pcl:ptr
    mov ebp,pcl
    VMMCall Begin_Nest_Exec 
    ret
    align 4
Begin_Nest_Exec endp

End_Nest_Exec proc stdcall public uses ebp pcl:ptr
    mov ebp,pcl
    VMMCall End_Nest_Exec
	ret
    align 4
End_Nest_Exec endp

Exec_Int proc stdcall public uses ebp intno:dword, pcl:ptr
    mov eax, intno
    mov ebp,pcl
    VMMCall Exec_Int
    ret
    align 4
Exec_Int endp

	end
