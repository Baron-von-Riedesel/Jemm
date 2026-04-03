
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

ifndef ?KD
?KD equ 0
endif

;--- constants

?PAGEMAP		equ	3FEh	;page table for mapping page tables (it's a PDE index)

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
externdef dfOldint20:fword
externdef g_dwIDT:dword
if ?KD
externdef bKDdetected:byte
endif

