
;--- this is an assembler include file in MASM format,
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

;--- v5.83: VMMCall renamed to @VMMCall ( VMMCALL is a x86 instruction now )

ifndef __POASM__
@VMMCall macro name_
    int 20h
    dw VMM_&name_
    dw 1
    endm
else
@VMMCall macro name_
    int 20h
    dw VMM_ # name_
    dw 1
    endm
endif

ifndef __POASM__
VMMJmp macro name_
    int 20h
    dw VMM_&name_ + 8000h
    dw 1
    endm
else
VMMJmp macro name_
    int 20h
    dw VMM_ # name_ + 8000h
    dw 1
    endm
endif

VxDCall macro name_
    int 20h
    dd name_
    endm

;--- macro to define a hook proc (Hook_V86_Int_Chain)

HookProc macro name_, oldvect
    jmp $+8
    jmp dword ptr [oldvect]
name_ proc
    endm

;--------------------------------------------------------------------------
;--- VMM API. This device is installed by JLoad. The name is misleading,
;--- though, VMs aren't supported.

;--- the following functions aren't implemented yet and will always return
;--- an error: 
;---   Install_Mult_IO_Handlers, Remove_Mult_IO_Handlers
;---   Hook_V86_Fault, Unhook_V86_Fault
;---   Hook_PM_Fault, Unhook_PM_Fault
;---   Get_PM_Int_Vector, Set_PM_Int_Vector

@@VMM_Service_no = 0

ifndef __POASM__
VMM_Service macro name_
VMM_&name_  equ @@VMM_Service_no
@@VMM_Service_no = @@VMM_Service_no +1
    endm
else
VMM_Service macro name_
VMM_#name_  equ @@VMM_Service_no
@@VMM_Service_no = @@VMM_Service_no +1
    endm
endif

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

;--- added in v5.83

VMM_Service _Allocate_GDT_Selector
VMM_Service _Free_GDT_Selector

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
PC_CACHEWT      EQU 00080000H   ;write thru
PC_CACHEDIS     EQU 00100000H   ;cache disable
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

@@VDMAD_Service_no = 0
VDMAD_Device equ 4

VDMAD_Service macro name_
name_   equ @@VDMAD_Service_no  + VDMAD_Device shl 16
@@VDMAD_Service_no = @@VDMAD_Service_no +1
    endm

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

cb_s    STRUC
CB_VM_Status        DD  ?
CB_High_Linear      DD  ?
CB_Client_Pointer   DD  ?
CB_VMID             DD  ?
cb_s    ENDS

;--- DDB (device description block)
;--- to be used for VMM_Add_DDB / VMM_Remove_DDB

UNDEFINED_INIT_ORDER	EQU 080000000H

VxD_Desc_Block  STRUC
DDB_Next                DD  ?
DDB_Version             DW  ?
DDB_Req_Device_Number   DW  0
DDB_Dev_Major_Version   DB  0
DDB_Dev_Minor_Version   DB  0
DDB_Flags               DW  0
ifndef __POASM__
DDB_Name                DB  8 dup (20h)
else
DDB_Name                DB  8 dup (?)
endif
DDB_Init_Order          DD  UNDEFINED_INIT_ORDER
DDB_Control_Proc        DD  ?
DDB_V86_API_Proc        DD  0
DDB_PM_API_Proc         DD  0
DDB_V86_API_CSIP        DD  0
DDB_PM_API_CSIP         DD  0
DDB_Reference_Data      DD  ?
DDB_Service_Table_Ptr   DD  0
DDB_Service_Table_Size  DD  0
DDB_Win32_Service_Table DD  0
DDB_Prev                DD  0
DDB_Size                DD  SIZE(VxD_Desc_Block)
DDB_Reserved1           DD  0  ;holds PE module handle
DDB_Reserved2           DD  0
DDB_Reserved3           DD  0
VxD_Desc_Block  ENDS

;--- client register structure
;--- note the "Client_Int" member, which is Jemm specific.

Client_Reg_Struc  struc
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
Client_Reg_Struc ends


;--------------------------------------------------------------------------
;--- JLoad init/term structure
;--- this is 3. parameter for a JLM's DllMain entry
;--- lpRequest is set for LOAD
;--- lpDrivers is set for UNLOAD

JLCOMM  struc
wLdrCS      dw ?    ;CS of JLOAD.EXE
wFlags      dw ?    ;flags (see below)
lpCmdLine   dd ?    ;linear address cmdline
union
lpRequest   dd ?    ;LOAD:   linear address DOS request hdr
lpDrivers   dd ?    ;UNLOAD: linear address DOS device driver list start
ends
JLCOMM  ends

JLF_UNLOAD  equ 1   ;set if JLM is to be unloaded
JLF_DRIVER  equ 2   ;set if JLoad is loaded as driver in config.sys
JLF_R0DEBUG equ 4   ;set if a ring 0 debugger (386SWAT) is present

JLF_UNLOAD_BIT  equ 0
JLF_DRIVER_BIT  equ 1
JLF_R0DEBUG_BIT equ 2
