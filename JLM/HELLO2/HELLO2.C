
// for MS VC

#include <jlm.h>

struct Client_Reg_Struc * pcl;

struct cb_s * Get_Cur_VM_Handle()
{
    VxDCall(Get_Cur_VM_Handle);
    _asm mov eax,ebx;
}

ULONG Begin_Nest_Exec()
{
    _asm mov ebp,pcl;
    VxDCall(Begin_Nest_Exec);
}

ULONG End_Nest_Exec()
{
    _asm mov ebp,pcl;
    VxDCall(End_Nest_Exec);
}

ULONG Exec_Int(unsigned long intno)
{
    _asm mov eax, intno;
    _asm mov ebp,pcl;
    VxDCall(Exec_Int);
}

int main()
{
    struct cb_s * hVM;
    unsigned char * psz = "Hello world\r\n";

    hVM = Get_Cur_VM_Handle();
    pcl = (struct Client_Reg_Struc *)hVM->CB_Client_Pointer;
    Begin_Nest_Exec();

    for (;*psz;psz++) {
        pcl->Client_EAX = 0x0200;
        pcl->Client_EDX = *psz;
        Exec_Int(0x21);
    }

    End_Nest_Exec();

    return 1;
};
