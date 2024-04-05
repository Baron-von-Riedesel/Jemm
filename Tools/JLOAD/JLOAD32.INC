
;--- macros

CStr macro text:vararg
local sym
	.const
 ifidni <text>,<"">
sym db 0
 else
sym db text,0
 endif
	.code
	exitm <offset sym>
endm

;--- constants

?PAGEMAP		equ	3FEh	;page table for mapping page tables

;--- structs

;--- publics

InitVMM	proto
FindDevice proto
VMM_Add_DDB proto
VMM_Remove_DDB proto
_PageReserve proto
_PageCommit proto
_PageDecommit proto
_PageFree proto
Get_Cur_VM_Handle proto

externdef Begin_Nest_Exec:dword
externdef Exec_Int:dword
externdef End_Nest_Exec:dword

externdef VDS_Call_Table:dword
externdef ddb_0004:VxD_Desc_Block
externdef oldint20:dword
externdef g_dwIDT:dword


