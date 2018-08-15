
/* Header file for Jemm JLMs which defines the subset of the Win3x/Win9x */
/* ring 0 API (VMM) that Jemm/JLoad exposes.                             */
/* The parameters and return values of the functions are the same as in  */
/* the Windows implementation, register usage is as in Win32: EAX, ECX   */
/* and EDX may be modified inside functions, the other registers are     */
/* preserved (exception: Get_Cur_VM_Handle).                             */

typedef unsigned char   UCHAR;
typedef unsigned short  USHORT;
typedef unsigned long   ULONG;

struct Pushad_Struc {
    ULONG Pushad_EDI;       /* Client's EDI */
    ULONG Pushad_ESI;       /* Client's ESI */
    ULONG Pushad_EBP;       /* Client's EBP */
    ULONG Pushad_ESP;       /* ESP before pushad */
    ULONG Pushad_EBX;       /* Client's EBX */
    ULONG Pushad_EDX;       /* Client's EDX */
    ULONG Pushad_ECX;       /* Client's ECX */
    ULONG Pushad_EAX;       /* Client's EAX */
};

#define VMM_DEVICE_ID       0x00001
#define VDMAD_DEVICE_ID     0x00004

#define GetVxDServiceOrdinal(service)   __ ## service


#define Begin_Service_Table(device, seg) \
    enum device##_SERVICES { \
    device##_dummy = (device##_DEVICE_ID << 16) - 1,

#define Declare_Service(service) \
    GetVxDServiceOrdinal(service),

#define Declare_SCService(service, args, local) \
    GetVxDServiceOrdinal(service),

#define End_Service_Table(device, seg) \
    Num_##device##_Services};

#define VXDINLINE static __inline

/*  */

#define GetVxDServiceAddress(service)   service

#ifdef __WATCOMC__

// Open Watcom C currently can't call the VMM services directly
// because ENUM values aren't accessible by the inline assembler.

#define VxDCall(service) \
    _asm int 20h \
    _asm dd (GetVxDServiceOrdinal(service) ) \

#define VxDJmp(service) \
    _asm int 20h \
    _asm dd (GetVxDServiceOrdinal(service) | 0x8000 ) \

#else

#define VxDCall(service) \
    _asm _emit 0xcd \
    _asm _emit 0x20 \
    _asm _emit (GetVxDServiceOrdinal(service) & 0xff) \
    _asm _emit (GetVxDServiceOrdinal(service) >> 8) & 0xff \
    _asm _emit (GetVxDServiceOrdinal(service) >> 16) & 0xff \
    _asm _emit (GetVxDServiceOrdinal(service) >> 24) & 0xff \

#define VxDJmp(service) \
    _asm _emit 0xcd \
    _asm _emit 0x20 \
    _asm _emit (GetVxDServiceOrdinal(service) & 0xff) \
    _asm _emit ((GetVxDServiceOrdinal(service) >> 8) & 0xff) | 0x80 \
    _asm _emit (GetVxDServiceOrdinal(service) >> 16) & 0xff \
    _asm _emit (GetVxDServiceOrdinal(service) >> 24) & 0xff \

#endif

#define VMMCall VxDCall

#define VMMJmp  VxDJmp

#define SERVICE __cdecl

#define VMM_Service Declare_Service

Begin_Service_Table(VMM, VMM)

VMM_Service (Get_VMM_Version)
VMM_Service (Get_Cur_VM_Handle)
VMM_Service (Allocate_V86_Call_Back)
VMM_Service (Crash_Cur_VM)
VMM_Service (Hook_V86_Int_Chain)
VMM_Service (Get_V86_Int_Vector)
VMM_Service (Set_V86_Int_Vector)
VMM_Service (Get_PM_Int_Vector)
VMM_Service (Set_PM_Int_Vector)
VMM_Service (Simulate_Int)
VMM_Service (Simulate_Iret)
VMM_Service (Simulate_Far_Call)
VMM_Service (Simulate_Far_Jmp)
VMM_Service (Simulate_Far_Ret)
VMM_Service (Simulate_Far_Ret_N)
VMM_Service (Build_Int_Stack_Frame)
VMM_Service (Simulate_Push)
VMM_Service (Simulate_Pop)
VMM_Service (_PageFree)
VMM_Service (_PhysIntoV86)
VMM_Service (_LinMapIntoV86)
VMM_Service (Hook_V86_Fault)
VMM_Service (Hook_PM_Fault)
VMM_Service (Begin_Nest_Exec)
VMM_Service (Exec_Int)
VMM_Service (Resume_Exec)
VMM_Service (End_Nest_Exec)
VMM_Service (Save_Client_State)
VMM_Service (Restore_Client_State)
VMM_Service (Simulate_IO)
VMM_Service (Install_Mult_IO_Handlers)
VMM_Service (Install_IO_Handler)
VMM_Service (VMM_Add_DDB)
VMM_Service (VMM_Remove_DDB)
VMM_Service (Remove_IO_Handler)
VMM_Service (Remove_Mult_IO_Handlers)
VMM_Service (Unhook_V86_Int_Chain)
VMM_Service (Unhook_V86_Fault)
VMM_Service (Unhook_PM_Fault)
VMM_Service (_PageReserve)
VMM_Service (_PageCommit)
VMM_Service (_PageDecommit)
VMM_Service (_PageCommitPhys)

End_Service_Table(VMM, VMM)

struct cb_s {
    ULONG CB_VM_Status;     /* VM status flags */
    ULONG CB_High_Linear;   /* Address of VM mapped high */
    ULONG CB_Client_Pointer;
    ULONG CB_VMID;
    ULONG CB_Signature;
};

struct Client_Reg_Struc {
    ULONG Client_EDI;       /* Client's EDI */
    ULONG Client_ESI;       /* Client's ESI */
    ULONG Client_EBP;       /* Client's EBP */
    ULONG Client_res0;      /* ESP at pushall */
    ULONG Client_EBX;       /* Client's EBX */
    ULONG Client_EDX;       /* Client's EDX */
    ULONG Client_ECX;       /* Client's ECX */
    ULONG Client_EAX;       /* Client's EAX */
    ULONG Client_IntNo;
    ULONG Client_Error;     /* Dword error code */
    ULONG Client_EIP;       /* EIP */
    USHORT Client_CS;       /* CS */
    USHORT Client_res1;     /*   (padding) */
    ULONG Client_EFlags;    /* EFLAGS */
    ULONG Client_ESP;       /* ESP */
    USHORT Client_SS;       /* SS */
    USHORT Client_res2;     /*   (padding) */
    USHORT Client_ES;       /* ES */
    USHORT Client_res3;     /*   (padding) */
    USHORT Client_DS;       /* DS */
    USHORT Client_res4;     /*   (padding) */
    USHORT Client_FS;       /* FS */
    USHORT Client_res5;     /*   (padding) */
    USHORT Client_GS;       /* GS */
    USHORT Client_res6;     /*   (padding) */
};
