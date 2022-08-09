
// for Open Watcom C
// OW inline assembly doesn't know values of enums!
// therefore it needs external module jlmw.asm

#include <jlm.h>
#include "jlmw.h"

struct Client_Reg_Struc * pcl;

int main()
{
    struct cb_s * hVM;
    unsigned char * psz = "Hello world\r\n";

    hVM = Get_Cur_VM_Handle();
    pcl = (struct Client_Reg_Struc *)hVM->CB_Client_Pointer;
    Begin_Nest_Exec(pcl);

    for (;*psz;psz++) {
        pcl->Client_EAX = 0x0200;
        pcl->Client_EDX = *psz;
        Exec_Int(0x21, pcl);
    }

    End_Nest_Exec(pcl);

    return 1;
};
