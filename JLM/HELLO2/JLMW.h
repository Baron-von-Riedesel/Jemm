
// helper procs needed by Open Watcom C

extern struct cb_s * _stdcall Get_Cur_VM_Handle( void );
extern ULONG _stdcall Begin_Nest_Exec(struct Client_Reg_Struc * pcl);
extern ULONG _stdcall End_Nest_Exec(struct Client_Reg_Struc * pcl);
extern ULONG _stdcall Exec_Int( unsigned long intno, struct Client_Reg_Struc * pcl );
