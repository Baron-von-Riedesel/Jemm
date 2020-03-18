
;--- this is an assembler include file in FASM format
;--- to be used for JLMs (Jemm Loadable Modules).
;--- it defines the API exposed by Jemm/JLoad.

;--- parameters, calling convention and return values are the same as
;--- for Win9x.
;--- the register usage usually is the same as for the Win32 stdcall 
;--- convention: registers EAX, ECX and EDX may be changed inside a function,
;---             registers EBX, ESI, EDI, EBP are preserved.
;--- the exception of this rule is Get_Cur_VM_Handle, which returns the
;--- "handle" in EBX.
;--------------------------------------------------------------------------

macro VMMCall name_ {
    int 20h
    dw VMM_#name_
    dw 1
}

macro VMMJmp name_ {
    int 20h
    dw VMM_#name_ + 8000h
    dw 1
}

macro VxDCall name_ {
    int 20h
    dd name_
}

;--- macro to define a hook proc (Hook_V86_Int_Chain)

macro HookProc name_, oldvect {
    jmp $+8
    jmp dword [oldvect]
name_ proc
}

;--------------------------------------------------------------------------
;--- VMM API. This device is installed by JLoad. The name is misleading,
;--- though, VMs aren't supported.

;--- not implemented yet:
;---   Install_Mult_IO_Handlers, Remove_Mult_IO_Handlers
;---   Hook_V86_Fault, Unhook_V86_Fault
;---   Hook_PM_Fault, Unhook_PM_Fault
;---   Get_PM_Int_Vector, Set_PM_Int_Vector

@VMM_Service_no = 0

macro VMM_Service name_ {
VMM_#name_  = @VMM_Service_no
@VMM_Service_no = @VMM_Service_no +1
}

VMM_Service Get_VMM_Version
VMM_Service Get_Cur_VM_Handle
VMM_Service Allocate_V86_Call_Back
VMM_Service Crash_Cur_VM
VMM_Service Hook_V86_Int_Chain
VMM_Service Get_V86_Int_Vector
VMM_Service Set_V86_Int_Vector
VMM_Service Get_PM_Int_Vector
VMM_Service Set_PM_Int_Vector
VMM_Service Simulate_Int
VMM_Service Simulate_Iret
VMM_Service Simulate_Far_Call
VMM_Service Simulate_Far_Jmp
VMM_Service Simulate_Far_Ret
VMM_Service Simulate_Far_Ret_N
VMM_Service Build_Int_Stack_Frame
VMM_Service Simulate_Push
VMM_Service Simulate_Pop
VMM_Service _PageFree
VMM_Service _PhysIntoV86
VMM_Service _LinMapIntoV86
VMM_Service Hook_V86_Fault
VMM_Service Hook_PM_Fault
VMM_Service Begin_Nest_Exec
VMM_Service Exec_Int
VMM_Service Resume_Exec
VMM_Service End_Nest_Exec
VMM_Service Save_Client_State
VMM_Service Restore_Client_State
VMM_Service Simulate_IO
VMM_Service Install_Mult_IO_Handlers
VMM_Service Install_IO_Handler
VMM_Service VMM_Add_DDB
VMM_Service VMM_Remove_DDB
VMM_Service Remove_IO_Handler
VMM_Service Remove_Mult_IO_Handlers
VMM_Service Unhook_V86_Int_Chain
VMM_Service Unhook_V86_Fault
VMM_Service Unhook_PM_Fault
VMM_Service _PageReserve
VMM_Service _PageCommit
VMM_Service _PageDecommit
VMM_Service _PageCommitPhys

;--- the following functions are Jemm specific

VMM_Service Free_V86_Call_Back      ;release v86 callback in EAX
VMM_Service Yield                   ;release cpu for IRQs
VMM_Service MoveMemory              ;copy memory with ints enabled

;--- equates for the page memory functions

;_PageReserve() page parameter:
PR_PRIVATE  EQU 80000400H
PR_SHARED   EQU 80060000H
PR_SYSTEM   EQU 80080000H

;_PageCommit() hpd parameter:
PD_ZEROINIT     EQU 00000001H   ;not supported
PD_NOINIT       EQU 00000002H   ;not supported
PD_FIXEDZERO    EQU 00000003H
PD_FIXED        EQU 00000004H

;_PageCommit() flags parameter:
PC_FIXED        EQU 00000008H   ;PC_FIXED and/or PC_LOCKED must be set
PC_LOCKED       EQU 00000080H
PC_WRITEABLE    EQU 00020000H   ;also valid for _PageCommitPhys()
PC_USER         EQU 00040000H   ;also valid for _PageCommitPhys()
PC_INCR         EQU 40000000H   ;also valid for _PageCommitPhys()

; PTE bits

P_PRESBIT   EQU 0
P_PRES  EQU (1 SHL P_PRESBIT)
P_WRITEBIT  EQU 1
P_WRITE EQU (1 SHL P_WRITEBIT)
P_USERBIT   EQU 2
P_USER  EQU (1 SHL P_USERBIT)
P_ACCBIT    EQU 5
P_ACC   EQU (1 SHL P_ACCBIT)
P_DIRTYBIT  EQU 6
P_DIRTY EQU (1 SHL P_DIRTYBIT)

;--- equates for IO trapping functions

BYTE_INPUT      EQU 000H
BYTE_OUTPUT     EQU 004H
WORD_INPUT      EQU 008H
WORD_OUTPUT     EQU 00CH
DWORD_INPUT     EQU 010H
DWORD_OUTPUT    EQU 014H

OUTPUT_BIT      EQU 2
WORD_IO_BIT     EQU 3
DWORD_IO_BIT    EQU 4
STRING_IO_BIT   EQU 5
REP_IO_BIT      EQU 6   ;rep prefix with "string io"
ADDR_32_IO_BIT  EQU 7   ;ECX used instead of CX for "rep string io"
REVERSE_IO_BIT  EQU 8

OUTPUT      EQU (1 SHL OUTPUT_BIT)
WORD_IO     EQU (1 SHL WORD_IO_BIT)
DWORD_IO    EQU (1 SHL DWORD_IO_BIT)
STRING_IO   EQU (1 SHL STRING_IO_BIT)
REP_IO      EQU (1 SHL REP_IO_BIT)

;--------------------------------------------------------------------------
;--- VDMA device. This device is also installed by JLoad

@VDMAD_Service_no = 0
VDMAD_Device equ 4

macro VDMAD_Service name_ {
name_   equ @VDMAD_Service_no  + VDMAD_Device shl 16
@VDMAD_Service_no = @VDMAD_Service_no +1
}

VDMAD_Service VDMAD_Get_Version
VDMAD_Service VDMAD_Lock_DMA_Region
VDMAD_Service VDMAD_Unlock_DMA_Region
VDMAD_Service VDMAD_Scatter_Lock
VDMAD_Service VDMAD_Scatter_Unlock
VDMAD_Service VDMAD_Request_Buffer
VDMAD_Service VDMAD_Release_Buffer
VDMAD_Service VDMAD_Copy_To_Buffer      ;new v5.69
VDMAD_Service VDMAD_Copy_From_Buffer    ;new v5.69

;--------------------------------------------------------------------------

;--- VM control block structure
;--- since VMs aren't supported yet, the fields aren't that useful.
;--- CB_Client_Pointer will always contain a valid pointer.

struct cb_s
CB_VM_Status        DD  ?
CB_High_Linear      DD  ?
CB_Client_Pointer   DD  ?
CB_VMID             DD  ?
ends

if 0
;--- DDB (device description block)
;--- to be used for VMM_Add_DDB / VMM_Remove_DDB

struct VxD_Desc_Block
DDB_Next                dd  ?
DDB_Version             DW  ?
DDB_Req_Device_Number   DW  ?
DDB_Dev_Major_Version   DB  ?
DDB_Dev_Minor_Version   DB  ?
DDB_Flags               DW  ?
DDB_Name                rb  8
DDB_Init_Order          DD  ?
DDB_Control_Proc        DD  ?
DDB_V86_API_Proc        DD  ?
DDB_PM_API_Proc         DD  ?
DDB_V86_API_CSIP        DD  ?
DDB_PM_API_CSIP         DD  ?
DDB_Reference_Data      DD  ?
DDB_Service_Table_Ptr   DD  ?
DDB_Service_Table_Size  DD  ?
DDB_Win32_Service_Table DD  ?
DDB_Prev                DD  ?
DDB_Size                DD  ?
DDB_Reserved1           DD  ?
DDB_Reserved2           DD  ?
DDB_Reserved3           DD  ?
ends
end if

;--- client register structure
;--- note the "Client_Int" member, which is Jemm specific.

struct Client_Reg_Struc
Client_EDI  dd ?    ;+0
Client_ESI  dd ?    ;+4
Client_EBP  dd ?    ;+8
Client_res0 dd ?    ;+12
Client_EBX  dd ?    ;+16
Client_EDX  dd ?    ;+20
Client_ECX  dd ?    ;+24
Client_EAX  dd ?    ;+28
Client_Int  dd ?    ;+32
Client_Error dd ?   ;+36
Client_EIP  dd ?    ;+40
Client_CS   dd ?    ;+44    
Client_EFlags dd ?  ;+48
Client_ESP  dd ?    ;+52
Client_SS   dd ?    ;+56
Client_ES   dd ?    ;+60
Client_DS   dd ?    ;+64
Client_FS   dd ?    ;+68
Client_GS   dd ?    ;+72
ends


;--------------------------------------------------------------------------
;--- JLoad init/term structure
;--- this is 3. parameter for a JLM's DllMain entry
;--- lpRequest is set for LOAD
;--- lpDrivers is set for UNLOAD

struct JLCOMM
wLdrCS      dw ?    ;CS of JLOAD.EXE
wFlags      dw ?    ;flags (see below)
lpCmdLine   dd ?    ;linear address cmdline
lpRequest   dd ?    ;LOAD:   linear address DOS request hdr
virtual at JLCOMM.lpRequest
lpDrivers   dd ?    ;UNLOAD: linear address DOS device driver list start
end virtual
ends

JLF_UNLOAD  equ 1   ;set if JLM is to be unloaded
JLF_DRIVER  equ 2   ;set if JLoad is loaded as driver in config.sys
JLF_R0DEBUG equ 4   ;set if a ring 0 debugger (386SWAT) is present

JLF_UNLOAD_BIT  equ 0
JLF_DRIVER_BIT  equ 1
JLF_R0DEBUG_BIT equ 2
