
;--- VMM functions
;--- best viewed with TAB size 4

	.386
	.model flat

	option casemap:none
	option proc:private

	include jemm.inc
	include jemm32.inc
	include jlm.inc
	include jload.inc
	include jload32.inc
	include debug.inc

?MAXBP	equ 32

?APIINT equ 2Fh

BPDYN	struc
dwCallback	dd ?
dwRefData	dd ?
BPDYN	ends

;--- v86-hook

HOOKV86 struc
dwHook	 dd ?
dwOldVec dd ?
HOOKV86 ends

;	.data

DATA_ segment dword public 'CODE'
    
oldint20 		dd 0	;saved Jemm's int 20h vector protected mode
VDS_Call_Table	dd 0	;Jemm's VDS call table
VCPI_Call_Table dd 0	;Jemm's VCPI call table
IO_Trap_Table	dd 0	;Jemm's IO trap table
bprm	 		dd 0	;real-mode address of first bp
dwTSSbase		dd 0	;start TSS of monitor

lpHooks			dd 0	;page for hooks (int chain, faults, ...)
lpV86_Monitor	dd 0
lpStackCurr		dd 0

ScratchPTE		dd 0	;PTE used to simplify page memory management
oldiohandler	dd 0	;saved Jemm's IO handler
oldbp1			dd 0	;saved Jemm's breakpoint 1 (the "reboot" bp)
IO_Handler_Region dd 0	;linear address IO handler array (256 kB)
IO_Handler_Pages dq 0	;64 pages reserved for IO handlers
Int2fHooked     dd 0
ifndef _DEBUG
prevint2f       dd 0
else
prevint2f       dd offset finalint2f
trueprevint2f   dd 0
endif

;--- generic "control block" returned by Get_Cur_VM_Handle

vmcb	cb_s <0,0,?TOS - size Client_Reg_Struc,1>

;--- start of device list known to the int 20h loader

ddb_list label dword
d0001	VxD_Desc_Block <ddb_0004,1,1,1,0,0,"        ",0,0,0,0,0,0,0,offset vmm_services,  ?NUMSERV0001>

;--- VMM service table

vmm_services label dword

					dd Get_VMM_Version				;0=get version
					dd Get_Cur_VM_Handle            ;1
					dd Allocate_V86_Call_Back
					dd Crash_Cur_VM
					dd Hook_V86_Int_Chain
					dd Get_V86_Int_Vector
					dd Set_V86_Int_Vector
					dd Get_PM_Int_Vector
					dd Set_PM_Int_Vector
Simulate_Int		dd 0
Simulate_Iret		dd 0
Simulate_Far_Call	dd 0
					dd Simulate_Far_Jmp
Simulate_Far_Ret	dd 0
					dd Simulate_Far_Ret_N
					dd Build_Int_Stack_Frame
					dd Simulate_Push
					dd Simulate_Pop
					dd _PageFree
					dd _PhysIntoV86
					dd _LinMapIntoV86
					dd Hook_V86_Fault
					dd Hook_PM_Fault
Begin_Nest_Exec		dd 0
Exec_Int			dd 0
Resume_Exec			dd 0
End_Nest_Exec		dd 0
					dd Save_Client_State
					dd Restore_Client_State
Simulate_IO 		dd 0
					dd Install_Mult_IO_Handlers
					dd Install_IO_Handler
					dd VMM_Add_DDB
					dd VMM_Remove_DDB
					dd Remove_IO_Handler
					dd Remove_Mult_IO_Handlers
					dd Unhook_V86_Int_Chain
					dd Unhook_V86_Fault
					dd Unhook_PM_Fault
					dd _PageReserve
					dd _PageCommit
					dd _PageDecommit
					dd _PageCommitPhys
					dd Free_V86_Call_Back
Yield				dd 0        
MoveMemory  		dd 0        
					dd _Allocate_GDT_Selector ; v5.83
					dd _Free_GDT_Selector ; v5.83

?NUMSERV0001 equ ($ - vmm_services)/4

;--- VMM breakpoint table

v86_bp	BPDYN ?MAXBP dup (<>)

DATA_ ends

	.code

;--- InitVMM
;--- ECX -> VMMS structure

InitVMM proc public

	@DbgOutS <"Init enter",10>,?INITDBG

;--- save the vectors received from Jemm
;--- e08_ServiceTable is a VMM_SERV_TABLE struct

	mov esi, [ecx].VMMS.emx08.e08_ServiceTable
	lodsd
	mov Simulate_Int, eax
	lodsd
	mov Simulate_Iret, eax
	lodsd
	mov Simulate_Far_Call, eax
	lodsd
	mov Simulate_Far_Ret, eax
	lodsd
	mov Begin_Nest_Exec, eax
	lodsd
	mov Exec_Int, eax
	lodsd
	mov Resume_Exec, eax
	lodsd
	mov End_Nest_Exec, eax
	lodsd
	mov Simulate_IO, eax
	lodsd
	mov Yield, eax
	lodsd
	mov VDS_Call_Table, eax
	lodsd
	mov VCPI_Call_Table, eax
	lodsd
	mov IO_Trap_Table, eax
	lodsd
	mov lpV86_Monitor, eax
	lodsd
	mov lpStackCurr, eax
	lodsd					;new for v5.69
	mov MoveMemory, eax

;--- init the mapping page for memory management

	call InitMapPage
	jc @@exit

;--- modify Jemm's BP 1 (which is the "reboot" BP)
;--- to become the "generic" BP

	mov esi, [ecx].VMMS.emx08.e08_BPTable
	mov eax, offset V86_Callback_Handler
	xchg eax, [esi+4]
	mov [oldbp1], eax
	mov eax, [ecx].VMMS.emx08.e08_BPTableRM
	inc ax
	mov [bprm],eax

;--- since jemm v5.70, the TSS is no longer at a fix address

	movzx edx, [ecx].VMMS.emx08.e08_TR
	add edx, dword ptr [ecx].VMMS.emx08.e08_GDTR+2
	mov ah,[edx+7]
	mov al,[edx+4]
	shl eax,16
	mov ax,[edx+2]
	mov [dwTSSbase],eax

	mov eax, dword ptr [ecx].VMMS.emx08.e08_IDTR+2
	mov [g_dwIDT], eax

;--- install a int 20h handler

	mov esi, eax
	add esi, 20h*8
	mov ax,[esi+6]
	shl eax,16
	mov ax,[esi+0]
	mov [oldint20],eax
	mov eax, offset Int20_Handler
	mov [esi+0],ax
	shr eax,16
	mov [esi+6],ax
@@exit:
	@DbgOutS <"Init exit",10>,?INITDBG
	ret
	align 4

InitVMM Endp

;--- int 20h dynamic linking

Int20_Handler proc

	test byte ptr [esp].IRETDV86.vEFL+2,2	;called from v86-mode?
	jnz isv86
	pushad
	mov esi,[esp+8*4].IRETDV86.vEIP
	mov eax,[esi]					;it is "INT 20h" followed by a dword
	sub esi,2
	mov [esp+8*4].IRETDV86.vEIP, esi
	movzx ecx, ax
	shr eax,16
	mov edx, offset ddb_list
@@nextdevice:
	cmp ax, [edx].VxD_Desc_Block.DDB_Req_Device_Number	;is device known?
	jz @@device_found
	mov edx, [edx].VxD_Desc_Block.DDB_Next
	and edx, edx
	jnz @@nextdevice
@@error:
;	popad
	call Crash_Cur_VM	;AX:CX contain VM:Function to link to
@@device_found:
	mov bh,ch
	mov bl,0FFh
	and bh,80h
	and ch,7Fh
	cmp ecx, [edx].VxD_Desc_Block.DDB_Service_Table_Size
	jnc @@error
	mov eax, [edx].VxD_Desc_Block.DDB_Service_Table_Ptr
	shl ecx, 2
	shr bh,3
	add bh,15h
	add eax, ecx
	mov word ptr [esi],bx	;opcode for "call/jmp dword ptr []"
	mov [esi+2],eax
	popad
	iretd
isv86:
	jmp cs:[oldint20]
	align 4

Int20_Handler endp

;--- generic breakpoint
;--- has replaced Jemm's "REBOOT" breakpoint on init

V86_Callback_Handler  proc
	mov eax,[ebp].Client_Reg_Struc.Client_CS 
	sub ax,word ptr [bprm+2]
	jz isdefbp
	inc ax
	neg ax
	movzx eax,ax
	shl eax,3
	mov edx, [eax+offset v86_bp].BPDYN.dwRefData
	jmp [eax+offset v86_bp].BPDYN.dwCallback
isdefbp:
	jmp [oldbp1]
	align 4
V86_Callback_Handler endp

Get_VMM_Version proc
	mov eax, ?VERSIONLOW shl 16 + ?VERSIONHIGH
	clc
	ret
	align 4
Get_VMM_Version endp

Get_Cur_VM_Handle proc public 
	mov ebx, offset vmcb
	clc
	ret
	align 4
Get_Cur_VM_Handle endp

;--- deliberately cause a GPF. This will result in an 
;--- invalid opcode exception reported to v86-mode

Crash_Cur_VM proc
	push cs
	pop ss
	align 4
Crash_Cur_VM endp

;--- get a v86 callback in EAX
;--- inp: ESI=callback, EDX=dwRefData
;--- C on error

Allocate_V86_Call_Back proc
	push edi
	mov edi, offset v86_bp
	mov ecx, ?MAXBP
	xor eax, eax
@@nextitem:
	cmp eax, [edi].BPDYN.dwCallback
	jz @@freecb
	add edi, size BPDYN
	loop @@nextitem
	pop edi
	stc
	ret
@@freecb:
	mov [edi].BPDYN.dwCallback, esi
	mov [edi].BPDYN.dwRefData, edx
	sub edi, offset v86_bp
	shr edi, 3
	inc edi
	mov ax, word ptr [bprm+2]
	sub ax, di
	shl eax, 16
	mov ax,di
	shl ax,4
	add ax, word ptr [bprm+0]
	pop edi
	ret
	align 4
Allocate_V86_Call_Back endp

;--- free a v86 callback in EAX

Free_V86_Call_Back proc
	movzx edx, ax
	shr eax, 16
	inc eax
	movzx ecx, word ptr [bprm+2]
	sub ecx, eax
	jc @@fail
	cmp ecx, ?MAXBP
	jae @@fail
	push ecx
	add ecx, eax
	shl ecx, 4
	dec eax
	shl eax, 4
	add eax, edx
	movzx edx, word ptr [bprm+0]
	add ecx, edx
	cmp eax, ecx
	pop ecx
	jnz @@fail
	mov [v86_bp+ecx*8].BPDYN.dwCallback,0
	ret
@@fail:
	stc
	ret
	align 4
Free_V86_Call_Back endp

;--- eax = word/dword to push

Simulate_Push proc
	MOVZX edx, word ptr [EBP].Client_Reg_Struc.Client_ESP
	MOVZX ecx, word ptr [EBP].Client_Reg_Struc.Client_SS
	sub dx,2
	SHL ecx, 4
	add ecx, edx
	MOV word ptr [EBP].Client_Reg_Struc.Client_ESP,dx
	mov [ecx],ax
	ret
	align 4
Simulate_Push endp

;--- out: eax = word which has been poped

Simulate_Pop proc
	MOVZX edx, word ptr [EBP].Client_Reg_Struc.Client_ESP
	MOVZX ecx, word ptr [EBP].Client_Reg_Struc.Client_SS
	SHL ecx, 4
	add ecx, edx
	movzx eax,word ptr [ecx]
	add dx,2
	MOV word ptr [EBP].Client_Reg_Struc.Client_ESP,dx
	ret
	align 4
Simulate_Pop endp

;--- cx == segment
;--- edx == offset

Simulate_Far_Jmp proc
	mov [EBP].Client_Reg_Struc.Client_EIP, edx
	mov word ptr [EBP].Client_Reg_Struc.Client_CS,cx
	ret
	align 4
Simulate_Far_Jmp endp

;--- eax == number of bytes to pop 

Simulate_Far_Ret_N proc
	push eax
	call [Simulate_Far_Ret]
	pop eax
	add word ptr [EBP].Client_Reg_Struc.Client_ESP, ax
	ret
	align 4
Simulate_Far_Ret_N endp

;--- cx=segment, edx=offset to call

Build_Int_Stack_Frame proc
	push ecx
	push edx
	mov eax, [EBP].Client_Reg_Struc.Client_EFlags
	call Simulate_Push
	pop edx
	pop ecx
	call [Simulate_Far_Call]
	and byte ptr [ebp].Client_Reg_Struc.Client_EFlags+1,not (1+2)
	ret
	align 4
Build_Int_Stack_Frame endp

;--- in: EDI = save buffer
;--- no return value

Save_Client_State proc
	push edi
	push esi
	mov esi, ebp
	mov ecx, (size Client_Reg_Struc) / 4
	rep movsd
	pop esi
	pop edi
	ret
	align 4
Save_Client_State endp

;--- in: ESI = save buffer
;--- no return value

Restore_Client_State proc
	push edi
	push esi
	mov edi, ebp
	mov ecx, (size Client_Reg_Struc) / 4
	rep movsd
	pop esi
	pop edi
	ret
	align 4
Restore_Client_State endp

;--- Allocate_GDT_Selector( high32 descriptor, low32 descriptor, flags )
;--- returns selector in eax, GDT selector in loword edx, GDT size in hiword edx
;--- high32 desc: [esp+4][8]
;--- low32  desc: [esp+4][4]
;--- flags:       [esp+4][0]

_Allocate_GDT_Selector proc
	mov ecx, 8
	sub esp, ecx
	sgdt [esp]
	movzx edx, word ptr [esp]
	mov eax, [esp+2]
	inc edx
	add esp, ecx
nextdesc:
	cmp ecx, edx
	jae notfound
	cmp byte ptr [eax+ecx+5], 0
	jz found
	add ecx, 8
	jmp nextdesc
found:
	push edx
	mov edx, [esp+8][1*4]
	mov [eax+ecx+0], edx
	mov edx, [esp+8][2*4]
	mov [eax+ecx+4], edx
	pop edx
	mov eax, ecx
	ret
notfound:
	xor eax, eax
	xor edx, edx
	ret
_Allocate_GDT_Selector endp

;--- Free_GDT_Selector( wSelector, flags )
;--- todo: limit checks

_Free_GDT_Selector proc
	mov ecx, [esp+4]
	sub esp, 8
	sgdt [esp]
	mov eax, [esp+2]
	add esp, 8
	mov byte ptr [eax+ecx+5],0
	ret
_Free_GDT_Selector endp

;-------------------------
;--- the IO-port trapping is implemented very simple
;--- there is an array of 65536 vectors in a 256 kB memory region
;--- for all possible IO ports. On init the memory is uncommitted,
;--- but if someone installs a port trap in a 400h set which has
;--- no other trap yet, a new page will be allocated.

;--- called with port in EDX, value in EAX, type in CX

New_IO_Handler proc
	movzx edx,dx
	mov esi, [IO_Handler_Region]
	cmp dword ptr [esi+edx*4],0
	jz @F
	jmp dword ptr [esi+edx*4]
@@:
	VMMJmp Simulate_IO
	align 4

New_IO_Handler endp

;--- scan Jemm's table of IOTRAPENTRYs
;--- the table defines ranges, but there may be "holes" ( untrapped ports )
;--- so first check if the port is actually really trapped.

ImportJemmIOTraps proc uses esi

	@DbgOutS <"ImportJemmIOTraps",10>, ?IODBG
	mov esi, [IO_Trap_Table]
	lodsd
	mov [esi-4], offset New_IO_Handler
	mov [oldiohandler],eax
	lodsd
	mov ecx, eax
	jecxz @@done
@@nextrange:
	lodsb			; get bStart field
	movzx edx, al
	lodsb			; get bEnd field
	movzx eax, al
	sub eax, edx
	inc eax
	push ecx
	mov ecx, eax
	lodsd			; get dwProc field
	push esi
	mov esi, eax
@@nextport:
	push ecx
	push edx

	mov eax, [dwTSSbase]
	movzx ecx, [eax].TSSSEG.tsOfs
	add eax, ecx
	bt [eax], edx				; port trapped?
	jnc @F
	call CommitTrapPage
	jc @F
	mov eax, [IO_Handler_Region]
	mov [edx*4+eax], esi
@@:
	pop edx
	pop ecx
	inc edx			; next port
	loop @@nextport
	pop esi
	pop ecx
	loop @@nextrange
@@done:
	ret
	align 4

ImportJemmIOTraps endp

;--- dx=port

CommitTrapPage proc
	movzx edx, dx
	mov eax, edx
	shr eax, 10		;0-FFFF -> 0-3F
	bt dword ptr [IO_Handler_Pages], eax
	jc @@iscommitted
	push edx
	push PC_FIXED or PC_WRITEABLE
	push 0
	push PD_ZEROINIT
	push 1
	mov ecx, [IO_Handler_Region]
	shr ecx, 12
	add eax, ecx
	push eax
	call _PageCommit
	add esp,5*4
	pop edx
	and eax, eax
	jz @@error
	mov eax, edx
	shr eax, 10
	bts dword ptr [IO_Handler_Pages], eax
@@iscommitted:
	clc
	ret
@@error:
	stc
	ret
CommitTrapPage endp

;--- ESI=callback
;--- EDX=port

Install_IO_Handler proc
	cld
	cmp [IO_Handler_Region],0
	jnz @@isallocated
	@DbgOutS <"Install_IO_Handler: reserve 256 kB region",10>, ?IODBG
	push edx
	push 0
	push 64
	push PR_SYSTEM
	call _PageReserve	; reserve 64*4=256 kB [ 65536 ports, one dword per port ]
	add esp,3*4
	pop edx
	cmp eax,-1
	jz @@error
	mov [IO_Handler_Region],eax
	@DbgOutS <"Install_IO_Handler: region=">, ?IODBG
	@DbgOutD eax, ?IODBG
	@DbgOutS <10>, ?IODBG
	push edx
	call ImportJemmIOTraps
	pop edx
@@isallocated:
	@DbgOutS <"Install_IO_Handler: port=">, ?IODBG
	@DbgOutW edx, ?IODBG
	@DbgOutS <10>, ?IODBG
	call CommitTrapPage
	jc @@error
	mov eax, edx
	shl eax, 2
	add eax, [IO_Handler_Region]
	cmp dword ptr [eax], 0		; port already trapped?
	jnz @@error
	mov [eax], esi
	mov eax, [dwTSSbase]
	movzx ecx, [eax].TSSSEG.tsOfs
	add eax, ecx
	bts [eax],edx				; mark port as "trapped" in IOPB
	clc
	ret
@@error:
	@DbgOutS <"Install_IO_Handler: trap port=">, ?IODBG
	@DbgOutW edx, ?IODBG
	@DbgOutS <"failed",10>, ?IODBG
	stc
	ret
	align 4
Install_IO_Handler endp

;--- untrap port, dx=port

Remove_IO_Handler proc
	@DbgOutS <"Remove_IO_Handler: untrap port=">, ?IODBG
	@DbgOutW edx, ?IODBG
	@DbgOutS <10>, ?IODBG
	xor ecx, ecx
	cmp [IO_Handler_Region],ecx
	jz @@error
	mov eax, edx
	shr eax, 10		;0-FFFF -> 0-3F
	bt dword ptr [IO_Handler_Pages], eax
	jnc @@error
	mov eax, edx
	shl eax, 2
	add eax, [IO_Handler_Region]
	cmp [eax],ecx
	jz @@error
	mov [eax], ecx
	mov eax, [dwTSSbase]
	movzx ecx, [eax].TSSSEG.tsOfs
	add eax, ecx
	btc [eax],edx
	clc
	ret
@@error:
	@DbgOutS <"Remove_IO_Handler: untrap port=">, ?IODBG
	@DbgOutW edx, ?IODBG
	@DbgOutS <"failed",10>, ?IODBG
	stc
	ret
	align 4
Remove_IO_Handler endp

;--- not implemented
;--- API?

Install_Mult_IO_Handlers proc
	stc
	ret
	align 4
Install_Mult_IO_Handlers endp

;--- not implemented
;--- API?

Remove_Mult_IO_Handlers proc
	stc
	ret
	align 4
Remove_Mult_IO_Handlers endp

;--- interrupt hooking

;--- get vector EAX in CX:EDX

Get_V86_Int_Vector proc
	cmp eax,256
	jae @@error
	movzx edx,word ptr [eax*4+0]
	mov cx,word ptr [eax*4+2]
	clc
	ret
@@error:
	stc
	ret
	align 4
Get_V86_Int_Vector endp

;--- set vector EAX in CX:EDX

Set_V86_Int_Vector proc
	cmp eax,256
	jae @@error
	mov word ptr [eax*4+0],dx
	mov word ptr [eax*4+2],cx
	clc
	ret
@@error:
	stc
	ret
	align 4
Set_V86_Int_Vector endp

;--- the Get_PM/Set_PM API is supposed to set the vectors of the current VM
;--- if it's in protected-mode. So not really needed by Jemm.

;--- in: eax=int#
;--- out: cx=segment
;---     edx=offset

Get_PM_Int_Vector proc
	stc
	ret
	align 4
Get_PM_Int_Vector endp

;--- in: eax=int#
;---      cx=segment
;---     edx=offset

Set_PM_Int_Vector proc
	stc
	ret
	align 4
Set_PM_Int_Vector endp

;--- hook v86 interrupt chain
;--- eax = int#
;--- esi = hook proc

;--- what is done here?
;--- when the first hook is installed, a 4 kB page is allocated.
;--- the first 2048 bytes of this page hold 256 HOOKV86 entries
;--- where the last installed hook proc and the original value
;--- of the IDT are saved.
;--- the second 2048 bytes hold 256 code fragments, with this structure:
;--- +2048: push 0        ;int 0 hook
;---        jmp v86_hook
;---        db 0          ;used to save bit status of interrupt table
;--- +2056: push 1        ;int 1 hook
;---        jmp v86_hook
;---        db 0

Hook_V86_Int_Chain proc
	cmp eax,100h
	jnc @@error
	cmp [lpHooks],0
	jnz @@isallocated
	push eax
	push 0
	push 1
	push PR_SYSTEM
	call _PageReserve
	add esp,3*4
	cmp eax, -1
	jz @@error2
	push eax
	push PC_FIXED or PC_WRITEABLE
	push 0
	push PD_ZEROINIT
	push 1
	shr eax, 12
	push eax
	call _PageCommit
	add esp,5*4
	pop ecx
	and eax, eax
	jz @@error2
	mov [lpHooks], ecx
	pop eax
@@isallocated:
	mov edx,[lpHooks]
	cmp dword ptr [edx+eax*8],0
	jz @@newhook
	mov ecx,[edx+eax*8].HOOKV86.dwHook
	mov [edx+eax*8].HOOKV86.dwHook, esi
	mov eax, [esi-4]
	mov [eax], ecx
	jmp @@done
@@error2:
	pop eax
@@error:
	@DbgOutS <"Hook_V86_Int_chain: exit error",10>, ?JLMDBG
	stc
	ret
@@newhook:
	@DbgOutS <"Hook_V86_Int_chain: new hook",10>, ?JLMDBG
	mov [edx+eax*8].HOOKV86.dwHook, esi
	push ebx
	push esi

if 0
	mov ecx, [esi-4]
	mov dword ptr [ecx], 0
endif

;--- the IDT is modified. EAX=Int#
;--- 1. store the current offset in IDT in HOOKV86.dwOldVec
;--- 2. set the offset in IDT to the thunk code for this int
;--- 3. generate the thunk code: "push #int" & "jmp near32 v86hook"
;--- 4. modify the int bitmap in TSS

	@DbgOutS <"Hook_V86_Int_chain: modifying IDT",10>, ?JLMDBG
	mov ecx, [g_dwIDT]
	mov si, [ecx+eax*8+6]
	shl esi,16
	mov si,[ecx+eax*8+0]
	mov [edx+eax*8].HOOKV86.dwOldVec, esi
	lea edx, [edx+256*8+eax*8]
	mov ebx, edx
	mov [ecx+eax*8+0],bx
	shr ebx,16
	mov [ecx+eax*8+6],bx

	mov byte ptr [edx], 06Ah		;push byte
	mov byte ptr [edx+1], al
	add edx,2
	mov byte ptr [edx], 0E9h		;jmp near32
	mov ecx, offset v86_hook
	sub ecx, edx
	sub ecx, 5						; v5.82: adjust size of "jmp near32"
	mov dword ptr [edx+1], ecx

	@DbgOutS <"Hook_V86_Int_chain: modifying Int bitmap",10>, ?JLMDBG
	mov ebx, [dwTSSbase]
	movzx ecx, [ebx].TSSSEG.tsOfs
	add ebx, ecx
	sub ebx, 32    ;=256/8
	bts [ebx],eax
	setc byte ptr [edx+5]	;save previous bit state

	pop esi
	pop ebx
@@done:
	@DbgOutS <"Hook_V86_Int_chain: exit ok",10>, ?JLMDBG
	clc
	ret
	align 4
Hook_V86_Int_Chain endp

;--- the generic v86 hook proc
;--- installing a hook proc for a v86 int creates the following code:
;--- push byte ptr int#
;--- jmp near32 v86_hook

v86_hook proc

;--- ?TOS: top of ring0 stack
;--- IRETDV86: struct of an IRETD in v86 mode ( eip, cs, efl, esp, ss, es, ds, fs, gs )
	cmp esp, ?TOS - (sizeof IRETDV86 + 4)
	jnz @@nov86

	push 0					;adjust to match Client_Reg_Struc ()
	pushad
	mov ebp,esp 			;ebp -> Client_Reg_Struc
	push ss
	pop ds
	push ss
	pop es
	cld
	mov eax,[lpStackCurr]
	mov ecx,[lpHooks]
	mov esp,[eax]

;--- get the old vector in IDT and store it in int# member of client struct

	movzx eax,byte ptr [ebp].Client_Reg_Struc.Client_Error  ; eax=int#

ifdef _DEBUG
	cmp ax, 2Fh
	jnz @F
	cmp word ptr [ebp].Client_Reg_Struc.Client_EAX, 168Fh
	jz skiplog
@@:
endif
	@DbgOutS <"v86_hook: int=">, ?JLMDBG
	@DbgOutW eax, ?JLMDBG
	@DbgOutS <10>, ?JLMDBG
skiplog:

	mov edx, [ecx+eax*8].HOOKV86.dwOldVec
	mov [ebp].Client_Reg_Struc.Client_Int, edx
	call CallV86Hooks  ; expects eax=int#
	mov esp,ebp
	popad
	jnc @@done
	ret 4   ; exit by jumping to old vector
@@done:
	add esp,4+4
	iretd
@@nov86:
	jmp cs:[lpV86_Monitor]
	align 4
v86_hook endp

;--- call hooks for an int
;--- must have been ensured that there are hooks!
;--- a hook proc is called with:
;--- eax = int#
;--- (ebx = VM)
;--- ebp = client
;--- out: NC if interrupt has been serviced.


CallV86Hooks proc
	mov ecx,[lpHooks]
	mov ecx, [ecx+eax*8].HOOKV86.dwHook
@@nexthook:
	push ecx
	push eax
	call ecx
	pop eax
	pop ecx
	jnc @@done
	mov edx,[ecx-4]
	mov ecx,[edx]
	and ecx, ecx
	jnz @@nexthook
	stc
@@done:
	ret
	align 4
CallV86Hooks endp

;--- eax = int#
;--- esi = hook proc

Unhook_V86_Int_Chain proc
	cmp eax,100h
	jnc @@error
	mov ecx,[lpHooks]
	jecxz @@error
	mov edx,[ecx+eax*8]
	and edx,edx
	jz @@error
	xor ecx,ecx
@@nextitem:
	cmp edx,esi
	jz @@found
	mov ecx,[edx-4]
	mov edx,[ecx]
	and edx,edx
	jnz @@nextitem
@@error:
	stc
	ret
@@found:
	mov edx,[edx-4]
	mov edx,[edx]
	and ecx,ecx
	jnz @@notfirst
	mov ecx,[lpHooks]
	and edx, edx
	jz @@islast
	lea ecx,[ecx+eax*8]
@@notfirst:
	mov [ecx],edx
	ret
@@islast:
	mov [ecx+eax*8].HOOKV86.dwHook,edx
	cmp byte ptr [ecx+eax*8+2048+7],0
	jnz @@nobitres
	push ebx
	mov ebx, [dwTSSbase]
	movzx edx, [ebx].TSSSEG.tsOfs
	add ebx, edx
	sub ebx, 32    
	btr [ebx],eax
	pop ebx
@@nobitres:
	mov ecx,[ecx+eax*8].HOOKV86.dwOldVec
	mov edx, [g_dwIDT]
	mov [edx+eax*8+0],cx
	shr ecx,16
	mov [edx+eax*8+6],cx
	ret
	align 4
Unhook_V86_Int_Chain endp

Hook_V86_Fault proc
Hook_V86_Fault endp
Unhook_V86_Fault proc
Unhook_V86_Fault endp
Hook_PM_Fault proc
Hook_PM_Fault endp
Unhook_PM_Fault proc
Unhook_PM_Fault endp

	stc
	ret

	align 4

;--- _PhysIntoV86(physpg, VM, VMLinPgNum, nPages, flags)

physpg     equ <esp+1*4>
VM         equ <esp+2*4>
VMLinPgNum equ <esp+3*4>
nPages     equ <esp+4*4>
flags      equ <esp+5*4>

_PhysIntoV86 proc
	mov ecx, [nPages]
	push esi
	push edi
	mov esi, 8[physpg]
	mov edi, 8[VMLinPgNum]
	mov eax, esi
	mov edx, edi
	cmp eax, 100h
	jbe @@done
	lea edi, [edi*4 + (?PAGEMAP shl 22)]
	cld
	shl esi,12
@@nextitem:
	mov eax, esi
	or eax,7
	stosd
	add esi,1000h
	loop @@nextitem
	mov eax,cr3
	mov cr3,eax
@@done:
	pop edi
	pop esi
	ret
@@error:
	xor eax,eax
	ret
	align 4
_PhysIntoV86 endp

;--- _LinMapIntoV86(LinPgNum, VM, VMLinPgNum, nPages, flags)

LinPgNum  equ <esp+1*4>
VM        equ <esp+2*4>
VMLinPgNum equ <esp+3*4>
nPages     equ <esp+4*4>
flags      equ <esp+5*4>

_LinMapIntoV86 proc
	mov ecx, [nPages]
	push esi
	push edi
	mov esi, 8[LinPgNum]
	mov edi, 8[VMLinPgNum]
	mov eax, esi
	mov edx, edi
	cmp eax, 100h
	jbe @@done
	lea esi, [esi*4 + (?PAGEMAP shl 22)]
	lea edi, [edi*4 + (?PAGEMAP shl 22)]
	cld
	rep movsd
	mov eax,cr3
	mov cr3,eax
@@done:
	pop edi
	pop esi
	ret
@@error:
	xor eax,eax
	ret
	align 4
_LinMapIntoV86 endp

;--- page memory

;--- bits in PTE:
;--- 200h = begin of a memory object
;--- 400h = PTE is a mapped phys page (don't free it!)
;--- 800h = not used

GetFreePages proc
	push edi
	push esi
	push ecx
	mov eax, [VCPI_Call_Table]
	call dword ptr [eax+3*4]	;VCPI_GetFreePages
	pop ecx
	pop esi
	pop edi
	ret
	align 4
GetFreePages endp

AllocPage proc
	push edi
	push esi
	push ecx
	mov eax, [VCPI_Call_Table]
	call dword ptr [eax+4*4]
	pop ecx
	pop esi
	pop edi
	ret
	align 4
AllocPage endp

FreePage proc
	push edi
	push esi
	push ecx
	mov eax, [VCPI_Call_Table]
	call dword ptr [eax+5*4]
	pop ecx
	pop esi
	pop edi
	ret
	align 4
FreePage endp

;--- to simplify memory management,
;--- a "mapping" page table is maintained which
;--- maps all page tables in linear address space
;--- at address ?PAGEMAP << 22 (currently 3FEh << 22 = FF800000h)

InitMapPage proc
	pushad
	call AllocPage
	cmp ah,0
	jnz @@error
	or edx,3							;set P, R/W, S
	mov ds:[?PAGEDIR+?PAGEMAP*4],edx	;set the PDE
	mov ds:[?PAGEDIR+?PAGETABSYS+0FF8h],edx  ;map the table in scratch region

	call AllocPage			;alloc a second page (scratch PTE)
	cmp ah,0
	jnz @@error
	or edx,3
	mov [ScratchPTE],edx

	mov eax, cr3			;flush TLB
	mov cr3, eax		


	mov eax, edx			;fill mapping table PDE with scratch PTE
	mov edi, ?SYSBASE + 3FE000h
	cld
	mov ecx, 1000h/4
	push edi
	rep stosd
	pop edi

	mov eax,ds:[?PAGEDIR+0] 			;copy PDE page table 0
	mov [edi+0],eax
	mov eax,ds:[?PAGEDIR+(?SYSBASE shr 20)]		;copy PDE "jemm"
	mov [edi+(?SYSBASE shr 20)],eax
	mov eax,ds:[?PAGEDIR+(?SYSTEMADDR shr 20)]	;copy PDE "jload"
	mov [edi+(?SYSTEMADDR shr 20)],eax
	mov eax,ds:[?PAGEDIR+?PAGEMAP*4]	;copy PDE "pagemap"
	mov [edi+?PAGEMAP*4],eax
	
;--- now move scratch PTE to scratch region and clear it
	
	mov dword ptr ds:[?PAGEDIR+?PAGETABSYS+0FF8h],edx

	mov eax, cr3
	mov cr3, eax

	mov ecx, 1000h/4
	xor eax, eax
	rep stosd
	mov dword ptr ds:[?PAGEDIR+?PAGETABSYS+0FF8h],0

	popad
	clc
	ret
@@error:
	popad
	xor eax, eax
	stc
	ret
	align 4
InitMapPage endp

;--- _PageFree(hMem, flags)
;--- this function has no size parameter
;--- _page: linear address of block
;--- flags: 0 or PR_STATIC

_page  equ <esp+1*4+4>
flags  equ <esp+2*4+4>

_PageFree proc public

	push esi
	mov esi, [_page]
	shr esi, 12
	lea esi, [esi*4 + ?PAGEMAP shl 22]
	lodsd
	test ah,2	;begin of a block?
	jz	@@error
@@nextitem:
	test al,1	;committed page?	
	jz @F
	test ah,4	;mapped page?
	jnz @F
	mov edx, eax
	and dx,0F000h
	call FreePage
@@:
	mov dword ptr [esi-4],0
;	cmp esi, (?PAGEMAP + 400000h) shl 22	;end of page map?
	cmp esi, (?PAGEMAP shl 22 ) + 400000h	;end of page map?
	jz @@done
	lodsd
	and eax, eax
	jz @@done
	test ah,2
	jz @@nextitem
@@done:
	mov eax,cr3
	mov cr3,eax
	push 1
	pop eax
	pop esi
	ret
@@error:
	pop esi
	xor eax,eax
	ret
	align 4
_PageFree endp

;--- _PageReserve(page, npages, flags)
;--- page = specific page or 
;--- PR_PRIVATE (80000400h), PR_SHARED (80060000h), PR_SYSTEM (80080000h)
;--- flags: ???
;--- out: linear address in EAX or -1
;--- "private" starts at 400000h
;--- "shared" possibly at F8000000h downwards?
;--- system at ?SYSTEMADDR (usually F8400000h)
;--- the first PTE will have the 

_page  equ <esp+1*4>
npages equ <esp+2*4>
flags  equ <esp+3*4>

_PageReserve proc public
	cmp dword ptr [npages],0
	jz @@error
	mov eax, ?SYSTEMADDR shr 10
	mov ecx, 400000h/4 - (?SYSTEMADDR shr 12)
	cmp dword ptr [_page],PR_SYSTEM
	jz @F
	cmp dword ptr [_page],PR_PRIVATE   ;currently only unspecified regions are supported
	jnz @@error
	mov eax, ?PRIVATEADDR shr 10
	mov ecx, (?SYSTEMADDR - ?PRIVATEADDR) shr 12
@@:
	mov edx, [npages]
	dec edx
	push edi
	push ebx
	lea edi, [eax + (?PAGEMAP shl 22)]
	cld

;--- the mapping region at FF800000-FFBFFFFF contains no
;--- invalid addresses. A 00000000 entry means it is either an
;--- unused PTE of an partially used PT, or it is a still unused PT.
;--- so all what has to be done is scanning the region for a sequence
;--- of 00000000 dwords.

@@continuescan:    
	xor eax, eax
	repnz scasd
	jnz @@error2
	cmp ecx, edx	;enough potential entries left?
	jc @@error2
	lea ebx, [edi-4]
	and edx, edx	;size just one page?
	jz @@found
	push ecx
	mov ecx, edx
	repz scasd
	pop ecx
	jz @@found
	mov eax, edx
	sub eax, ecx
	sub ecx, eax
	jmp @@continuescan
@@found:

;--- now backup the PDEs and PTEs with true RAM

	mov ecx, edx
	inc ecx
	mov edi, ebx
	.while (ecx)
		mov eax, edi
		sub eax, ?PAGEMAP shl 22
		shr eax, 10
		cmp dword ptr ds:[?PAGEDIR + EAX],0	;does a PDE exist?
		jnz @F
		push eax
		call AllocPage
		cmp ah,0
		pop eax
		jnz @@error
		or edx,7
		mov ds:[?PAGEDIR + EAX],edx
		and dl, not 4
		mov ds:[(?PAGEMAP shl 22) + (?PAGEMAP shl 12) + EAX],edx
		push edi
		push ecx
		mov edi, eax
		shl edi, 10
		add edi, ?PAGEMAP shl 22
		mov eax, cr3
		mov cr3, eax
		xor eax, eax
		mov ecx, 1000h/4
		rep stosd
		pop ecx
		pop edi
@@:
		mov eax, 6		;set USER + R/W + NP
		cmp edi,ebx		;first PTE?
		setz ah
		shl ah,1		;set first "available" bit in PTE
		stosd
		dec ecx
	.endw
	mov eax, ebx
	sub eax, ?PAGEMAP shl 22
	shl eax, 10
	pop ebx
	pop edi
	ret
@@error2:
	pop ebx
	pop edi
@@error:
	or eax,-1
	ret
	align 4
_PageReserve endp

;--- _PageCommit(page, npages, hpd, pagerdata, flags)
;--- returns eax != 0 if ok, eax == 0 on failure
;--- page: linear page number
;--- hpd: PD_FIXED | PD_FIXEDZERO
;--- pagerdata: must be ZERO
;--- flags: PC_FIXED, PC_LOCKED, PC_USER, PC_WRITEABLE
;--- if PC_FIXED or PC_LOCKED is set, none of the pages must be committed

_page      equ <esp+1*4+8>
npages     equ <esp+2*4+8>
hpd        equ <esp+3*4+8>
pagerdata  equ <esp+4*4+8>
flags      equ <esp+5*4+8>

_PageCommit proc public
	push esi
	push ebx
	mov esi, [_page]
	shl esi, 2
	add esi, ?PAGEMAP shl 22
	mov ebx, [flags]
	mov ecx, [npages]
	xor edx, edx
	cld
	and ecx, ecx
	jz @@error
@@nextitem:
	lodsd
	and al,al			;valid address space?
	jz @@error
	test al,P_PRES		;page committed?
	setz al
	test bl,PC_FIXED or PC_LOCKED
	jz @F
	cmp al,0			;no committed page allowed
	jz @@error
@@:
	movzx eax,al
	add edx, eax
	loop @@nextitem
	
	push edx
	call GetFreePages
	cmp ah,0
	pop eax
	jnz @@error
	cmp edx, eax
	jc	@@error 				; not enough free pages

	mov ecx, [npages]
	mov esi, [_page]
	shl esi, 2
	add esi, ?PAGEMAP shl 22
	mov ebx, [flags]
	shr ebx, 16 				; move PC_WRITEABLE and PC_USER to BL
	or bl,P_PRES				; also set the PRESENT bit
@@nextitem2:
	lodsd
	test al,P_PRES
	jnz @F
	call AllocPage
	cmp ah,0
	jnz @@error
	mov eax,[esi-4]
	mov al,0
	or al, bl
	or eax, edx
	mov [esi-4], eax
	test byte ptr [hpd],1	;zero init?
	jz @F
	push ecx
	push edi
	mov edi, esi
	sub edi, 4 + (?PAGEMAP shl 22)
	shl edi, 10
	mov ecx,1000h/4
	xor eax, eax
	rep stosd
	pop edi
	pop ecx
@@:
	loop @@nextitem2
	pop ebx
	pop esi
	push 1
	pop eax
	ret
@@error:
	pop ebx
	pop esi
	xor eax, eax
	ret
	align 4
_PageCommit endp

;--- _PageDecommit(page, npages, flags)
;--- page: linear page number
;--- flags: must be zero
;--- returns: eax == 0 on failure

_page      equ <esp+1*4>
npages     equ <esp+2*4>
flags      equ <esp+3*4>

_PageDecommit proc public

	mov ecx, [npages]
	jecxz @@error
	push esi
	mov esi, 4[_page]
	shl esi, 2
	add esi, ?PAGEMAP shl 22
@@nextitem:
	lodsd
	mov edx, eax
	test al,P_PRES		;committed page?
	jz @@notcommitted
	test ah,4			;mapped page?
	jnz @F
	mov dl,0
	and dh,0F0h
	push eax
	call FreePage
	pop edx
@@:
	and edx, 0200h		;preserve the "begin block" bit
	or dl,P_WRITE or P_USER
	mov [esi-4],edx
@@notcommitted:
	loop @@nextitem
	pop esi
	mov ecx,cr3
	mov cr3,ecx
	ret
@@error:
	xor eax, eax
	ret
	align 4
_PageDecommit endp

;--- _PageCommitPhys(page, npages, physpg, flags)
;--- flags: use PC_INCR to map a contiguous phys region;
;--- PC_USER and PC_WRITEABLE also relevant;
;--- v5.83: added PC_CACHEWT and PC_CACHEDIS;
;--- returns: eax == 0 on failure

_page      equ <esp+1*4>
npages     equ <esp+2*4>
physpg     equ <esp+3*4>
flags      equ <esp+4*4>

_PageCommitPhys proc

	mov ecx, [npages]
	jecxz @@error
	push esi
	mov esi, 4[_page]
	shl esi, 2
	add esi, ?PAGEMAP shl 22
	mov edx, esi
	cld
@@nextitem:
	lodsd
	cmp al,0			;valid PTE?
	jz @@error2
	test al,P_PRES		;all PTEs must be non-committed!
	jnz @@error2
	loop @@nextitem
	push edi
	push ebx
	mov esi, edx
	mov ecx, 12[npages]
	mov ebx, 12[physpg]
	mov edi, 12[flags]
	xor edx, edx
	test edi,PC_INCR
	jz @F
	mov dh,10h
@@:
	shr edi, 16
	and edi, (PC_WRITEABLE or PC_USER or PC_CACHEWT or PC_CACHEDIS) shr 16
	or edi, 401h		;mark this PTE as a "mapped" page (400h)
	shl ebx, 12
@@nextitem2:
	lodsd
	and ah,0Fh
	movzx eax,ax
	or eax, edi
	or eax, ebx
	mov [esi-4], eax
	add ebx, edx
	loop @@nextitem2
	pop ebx
	pop edi
	pop esi
	ret
@@error2:
	pop esi
@@error:
	xor eax, eax
	ret
	align 4
_PageCommitPhys endp

;--- in: eax->ID to find
;--- out: eax = hModule

FindDevice proc public
	mov edx,offset ddb_list
@@:
	cmp ax, [edx].VxD_Desc_Block.DDB_Req_Device_Number
	jz found
	mov edx,[edx].VxD_Desc_Block.DDB_Next
	and edx, edx
	jnz @B
	stc
	ret
found:
	mov eax, edx
	ret
	align 4

FindDevice endp

;--- esi -> DDB
;--- C set on failure
;--- new v5.74: alloc v86 breakpoint if v86 api is to be installed

VMM_Add_DDB proc public
	@DbgOutS <"VMM_Add_DBB, ID=">, ?JLMDBG
	movzx eax, [esi].VxD_Desc_Block.DDB_Req_Device_Number
	@DbgOutW eax, ?JLMDBG
	@DbgOutS <10>, ?JLMDBG
	mov edx, offset ddb_list
@@nextitem:
	and eax,eax
	jz @F
	cmp ax, [edx].VxD_Desc_Block.DDB_Req_Device_Number
	jz error
@@:
	mov ecx, edx
	mov edx,[edx].VxD_Desc_Block.DDB_Next
	and edx, edx
	jnz @@nextitem
	and eax,eax
	jz done
	cmp [esi].VxD_Desc_Block.DDB_V86_API_Proc,0		;v86 API?
	jz done
	@DbgOutS <"VMM_Add_DBB: JLM with API",10>, ?JLMDBG
	push ecx
	push esi
	mov esi,[esi].VxD_Desc_Block.DDB_V86_API_Proc
	xor edx,edx
	call Allocate_V86_Call_Back
	pop esi
	pop ecx
	jc error
	@DbgOutS <"VMM_Add_DBB: callback allocated",10>, ?JLMDBG
	mov [esi].VxD_Desc_Block.DDB_V86_API_CSIP, eax
	cmp [Int2fHooked],0
	jnz done
	inc [Int2fHooked]
	pushad
	mov eax, ?APIINT
	mov esi, offset Int2fHook
	call Hook_V86_Int_Chain
	@DbgOutS <"VMM_Add_DBB: Int 2F hooked, addr=">, ?JLMDBG
	@DbgOutD esi, ?JLMDBG
	@DbgOutS <10>, ?JLMDBG
	popad
done:
	mov [ecx].VxD_Desc_Block.DDB_Next, esi
	ret
error:
	stc
	ret
	align 4
VMM_Add_DDB endp

ifdef _DEBUG
	dd offset trueprevint2f
finalint2f proc
	cmp word ptr [ebp].Client_Reg_Struc.Client_EAX, 168Fh
	jz done
	@DbgOutS <"finalint2f: ax=">, ?JLMDBG
	@DbgOutW [ebp].Client_Reg_Struc.Client_EAX, ?JLMDBG
	@DbgOutS <10>, ?JLMDBG
done:
	stc
	ret
finalint2f endp
endif

;--- a hook proc must be prefixed by the flat address
;--- of the variable where the previous value is stored

	dd offset prevint2f
Int2fHook proc

ifdef _DEBUG
	cmp word ptr [ebp].Client_Reg_Struc.Client_EAX, 168Fh	;that happens pretty often, so don't log it
	jz @F
endif
	@DbgOutS <"Int2fHook: client_ax=">, ?JLMDBG
	@DbgOutW [ebp].Client_Reg_Struc.Client_EAX, ?JLMDBG
	@DbgOutS <10>, ?JLMDBG
@@:
	cmp word ptr [ebp].Client_Reg_Struc.Client_EAX, 1684h
	jnz not_ours
	@DbgOutS <"Int2FHook: ax=1684h detected, ID=">, ?JLMDBG
	movzx eax,word ptr [ebp].Client_Reg_Struc.Client_EBX
	@DbgOutW eax, ?JLMDBG
	@DbgOutS <10>, ?JLMDBG
	mov edx, offset ddb_list
@@nextitem:
	cmp ax, [edx].VxD_Desc_Block.DDB_Req_Device_Number
	jz found
	mov edx,[edx].VxD_Desc_Block.DDB_Next
	and edx, edx
	jnz @@nextitem
	xor eax, eax
	jmp @F
found:
	mov byte ptr [ebp].Client_Reg_Struc.Client_EAX, 0	;v5.82: set AL to 0 if ok
	mov eax, [edx].VxD_Desc_Block.DDB_V86_API_CSIP
@@:
	mov word ptr [ebp].Client_Reg_Struc.Client_EDI, ax
	shr eax, 16
	mov word ptr [ebp].Client_Reg_Struc.Client_ES, ax

	clc
	ret
not_ours:
	stc
	ret
	align 4
Int2fHook endp

;--- edi -> DDB
;--- C set on failure
;--- new v5.74: free v86 breakpoint if v86 api exists

VMM_Remove_DDB proc public
	xor eax, eax
	and edi, edi
	jz @@error
	mov edx, offset ddb_list
@@nextitem:
	cmp edx, edi
	jz @@found
	mov eax, edx
	mov edx,[edx].VxD_Desc_Block.DDB_Next
	and edx, edx
	jnz @@nextitem
@@error:
	stc
	ret
@@found:
	and eax, eax	;dont remove the first device
	jz @@error
	mov ecx,[edx].VxD_Desc_Block.DDB_Next
	mov [eax].VxD_Desc_Block.DDB_Next, ecx
	mov eax, [edi].VxD_Desc_Block.DDB_V86_API_CSIP
	and eax, eax
	jz @F
	call Free_V86_Call_Back
@@:
	clc
	ret
	align 4
VMM_Remove_DDB endp

	end
