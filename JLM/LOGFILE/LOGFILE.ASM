
;--- redirect Int 41h character output to a buffer.

	.386
	.model flat, stdcall

	.nolist
	include jlm.inc
	.list

DEVICE_ID equ 6510h

cr equ 13
lf equ 10

DLL_PROCESS_ATTACH  equ 1
DLL_PROCESS_DETACH  equ 0

BUFFERSIZE equ 8192 * 1024

CStr macro text:VARARG
local sym
	.const
sym db text,0
	.code
	exitm <offset sym>
endm

	.data

;--- the DDB must be make public. The linker will "export" this
;--- symbol. This is the simplest method to make JLoad know the
;--- device id.

	public ddb

ddb VxD_Desc_Block <0,0,DEVICE_ID,1,0,0,"LOGFILE",0, 0, v86_dispatch>

logfile_start dd 0    ;linear address buffer
logfile_ofs   dd 0    ;current write offset into buffer
XMSEntry      dd 0    ;XMS "entry" address, set by Init
XMSHdl        dd 0    ;XMS handle of buffer
dwBufferPhys  dd 0    ;physical address buffer
oldint41      df 0

	.code

;--- dispatcher for v86 services

v86_dispatch proc

	@VMMCall Simulate_Far_Ret	;emulate a RETF in v86

	and [ebp].Client_Reg_Struc.Client_EFlags,not 1  ;clear Carry flag
	movzx eax, word ptr [ebp].Client_Reg_Struc.Client_EAX
	cmp eax,0
	jz getversion
	cmp eax,1
	jz getdata
	cmp eax,2
	jz cleardata
	or [ebp].Client_Reg_Struc.Client_EFlags,1  ;set Carry flag
	ret
	align 4

v86_dispatch endp

getversion proc

	mov word ptr [ebp].Client_Reg_Struc.Client_EAX, 0100h
	ret
	align 4

getversion endp

getdata proc

	mov eax, XMSHdl
	mov [ebp].Client_Reg_Struc.Client_EDX, eax
	mov eax, logfile_ofs
	mov [ebp].Client_Reg_Struc.Client_ECX, eax
	ret
	align 4

getdata endp

cleardata proc

	mov logfile_ofs,0
	ret
	align 4

cleardata endp

myint41 proc
	cmp ax,0
	jnz exit
	push ds
	push ebx
	mov ebx, cs
	add ebx, 8
	mov ds, ebx
	mov ebx, [logfile_start]
	add ebx, [logfile_ofs]
	mov [ebx], dl
	inc [logfile_ofs]
	and [logfile_ofs], BUFFERSIZE - 1
	pop ebx
	pop ds
exit:
	IRETD
myint41 endp

	include printf.inc

;--- call int 2Fh

Int2F proc
	mov word ptr [ebp].Client_Reg_Struc.Client_EAX, ax
	@VMMCall Begin_Nest_Exec
	mov eax, 2Fh
	@VMMCall Exec_Int
	@VMMCall End_Nest_Exec
	ret
Int2F endp

;--- call XMS

XMSCall proc
	mov [ebp].Client_Reg_Struc.Client_EAX, eax
	mov [ebp].Client_Reg_Struc.Client_EDX, edx
	@VMMCall Begin_Nest_Exec
	movzx edx, word ptr [XMSEntry+0]
	mov cx, word ptr [XMSEntry+2]
	@VMMCall Simulate_Far_Call
	@VMMCall Resume_Exec
	@VMMCall End_Nest_Exec
	mov eax,[ebp].Client_Reg_Struc.Client_EAX
	dec ax        ;Zero AX-reg. if success, -1 if error.
	ret
XMSCall endp

;--- get XMS entry and alloc a 8 MB buffer

InitXMS proc
	mov ax, 4300h			;Inquire about an XMS manager.
	call Int2F
	mov eax, [ebp].Client_Reg_Struc.Client_EAX
	cmp al, 80h 			;Is an XMS manager installed?
	jne I_XErr1
	mov ax, 4310h			;Get XMS manager "entry" address.
	call Int2F
	mov bx, word ptr [ebp].Client_Reg_Struc.Client_ES
	shl ebx, 16
	mov bx, word ptr [ebp].Client_Reg_Struc.Client_EBX
	mov [XMSEntry], ebx

	mov ah, 9				;Ask XMS manager for 8 MB of memory.
	mov dx, BUFFERSIZE shr 10
	call XMSCall
	jnz I_XErr2
	mov edx, [ebp].Client_Reg_Struc.Client_EDX
	mov [XMSHdl],edx

	mov ah,0Ch 				;"Lock" XMS memory
	call XMSCall
	jnz I_XErr3

	mov eax,[ebp].Client_Reg_Struc.Client_EDX
	shl eax,16				;Get XMS buffer address
	mov ax, word ptr [ebp].Client_Reg_Struc.Client_EBX
	mov [dwBufferPhys],eax
	ret
I_XErr1:
	mov eax,CStr('No XMS manager')
	stc
	ret
I_XErr2:
	mov eax,CStr('XMS memory allocation failed')
	stc
	ret
I_XErr3:
	mov eax,CStr('XMS lock memory error')
	stc
	ret
	align 4
InitXMS endp

;--- free XMS memory block
;
ExitXMS proc
	xor edx, edx
	xchg edx, [XMSHdl]
	and edx, edx
	stc
	jz exit
	mov ah,00Dh
	push edx
	call XMSCall
	mov ah,00Ah
	pop edx
	call XMSCall
	clc
exit:
	ret
ExitXMS endp

;--- map XMS block into linear address space

MapBuffer proc uses edi
	mov eax, BUFFERSIZE shr 12
	test word ptr [dwBufferPhys], 0fffh  ; buffer aligned to 4k page?
	jz @F
	inc eax
@@:
	mov edi, eax
	push 0
	push eax
	push PR_SYSTEM
	@VMMCall _PageReserve	;alloc address space
	add esp,3*4
	cmp eax,-1
	jz error1
	mov dx, word ptr [dwBufferPhys]
	and dx, 0C00h
	or ax, dx
	mov [logfile_start], eax;linear address starts at kB boundary
	shr eax, 12 			;convert linear address to page number

	push PC_INCR or PC_WRITEABLE
	mov edx, [dwBufferPhys]
	shr edx, 12
	push edx   ; physical address
	push edi   ; size in pages
	push eax   ; linear address
	@VMMCall _PageCommitPhys ;backup address space with XMS memory
	add esp,4*4
	and eax, eax
	jz error2
	ret
error1:
	mov eax,CStr('No address space for buffer')
	stc
	ret
error2:
	mov eax,CStr('Mapping XMS block failed')
	stc
	ret
MapBuffer endp

;--- release buffer address space
;--- _PageFree(hMem,flags)

UnmapBuffer proc
	mov eax, [logfile_start]
	and ax, 0F000h
	push 0
	push eax
	@VMMCall _PageFree
	add esp, 2*4
	cmp eax, 1   ; C if eax == 0
	ret
UnmapBuffer endp

;--- install the JLM

install proc

	call InitXMS
	jc error

	call MapBuffer
	jc error2

	mov eax, 41h
	@VMMCall Get_PM_Int_Vector
	mov dword ptr [oldint41+0],edx
	mov word ptr [oldint41+4],cx
	mov edx, offset myint41
	mov ecx, cs
	mov eax, 41h
	@VMMCall Set_PM_Int_Vector
	mov eax,1
	ret
error2:
	push eax
	call ExitXMS
	pop eax
error:
	invoke printf, CStr("%s",10), eax
	xor eax, eax
	ret
	align 4

install endp

;--- deinstall the JLM

deinstall proc

	mov edx,dword ptr [oldint41+0]
	mov cx,word ptr [oldint41+4]
	mov eax, 41h
	@VMMCall Set_PM_Int_Vector
	call UnmapBuffer
	jc error
	call ExitXMS
	jc error
	mov eax,1
	ret
error:
	xor eax, eax
	ret
	align 4

deinstall endp

DllMain proc stdcall uses ebx esi hModule:dword, dwReason:dword, dwRes:dword

	mov eax,dwReason
	mov esi, install
	cmp eax,DLL_PROCESS_ATTACH
	jz @F
	mov esi, deinstall
	cmp eax,DLL_PROCESS_DETACH
	jnz exit
@@:    
	push ebp
	@VMMCall Get_Cur_VM_Handle
	mov ebp,[ebx].cb_s.CB_Client_Pointer
	call esi
	pop ebp
exit:
	ret
	align 4

DllMain endp

	end DllMain
