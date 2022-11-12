
;--- load the 16-bit DebugJ blob resource
;--- and call its initialization routine.
;--- JWasm used ( Masm won't work )

	.386
	.MODEL FLAT, stdcall
	option casemap:none


MEMADD    equ 500h
DEVICE_ID equ 4A50h

CStr macro text:vararg
local sym
	.const
sym db text,0
	.code
	exitm <offset sym>
endm

	include jlm.inc

	.data

;--- the DDB must be make public. The link step will "export" this
;--- symbol. This is the simplest method to make JLoad know the
;--- device id.

	public ddb

ddb VxD_Desc_Block < 0, 0, DEVICE_ID, 1, 0, 0, "JEMMDBG", 0, 0, 0 >

hModuleStat dd 0
dwFlat dd 0
dwBase dd 0
dwDS16 dd 0


_DATA16 segment para FLAT public 'DATA'

start16 label byte
	incbin <DebugJ.bin>
SIZEBIN16 equ $ - offset start16
	db MEMADD dup (?)

_DATA16 ends

	.CODE

GetModuleHandle proc hhandle:dword
	mov eax, hModuleStat
	ret
GetModuleHandle endp

	include printf.inc

	option stackbase:esp

MEMADD equ 500h

PUSHADS struct
_edi dd ?
_esi dd ?
_ebp dd ?
     dd ?
_ebx dd ?
_edx dd ?
_ecx dd ?
_eax dd ?
PUSHADS ends

;--- debugger callback
;--- run an Int 10h

callint10 proc far
	push ds
	push es
	movzx esp, sp
	mov ds, cs:[dwFlat]
	mov es, [dwFlat]
	mov ss, [dwFlat]
	add esp, [dwBase]
	pushad

	push ebx
	@VMMCall Get_Cur_VM_Handle
	mov ebp, [ebx].cb_s.CB_Client_Pointer
	pop ebx

	push [ebp].Client_Reg_Struc.Client_EAX
	push [ebp].Client_Reg_Struc.Client_EBX
	push [ebp].Client_Reg_Struc.Client_ECX
	push [ebp].Client_Reg_Struc.Client_EDX
	mov word ptr [ebp].Client_Reg_Struc.Client_EAX, ax
	mov word ptr [ebp].Client_Reg_Struc.Client_EBX, bx

	@VMMCall Begin_Nest_Exec
	mov eax, 10h
	@VMMCall Exec_Int
	@VMMCall End_Nest_Exec

;--- return cursor pos for int 10h, ah=3
	cmp byte ptr [ebp].Client_Reg_Struc.Client_EAX+1, 3
	jnz @F
	mov ax, word ptr [ebp].Client_Reg_Struc.Client_EDX
	mov word ptr [esp+4*4].PUSHADS._edx, ax
@@:
	pop [ebp].Client_Reg_Struc.Client_EDX
	pop [ebp].Client_Reg_Struc.Client_ECX
	pop [ebp].Client_Reg_Struc.Client_EBX
	pop [ebp].Client_Reg_Struc.Client_EAX
	popad
	mov ss, [dwDS16]
	sub esp, [dwBase]
	pop es
	pop ds
	ret
callint10 endp

;--- debugger callback
;--- run an Int 16h

callint16 proc far

	push ds
	push es
	movzx esp, sp
	mov ds, cs:[dwFlat]
	mov es, [dwFlat]
	mov ss, [dwFlat]
	add esp, [dwBase]
	pushad

	@VMMCall Get_Cur_VM_Handle
	mov ebp, [ebx].cb_s.CB_Client_Pointer

	push [ebp].Client_Reg_Struc.Client_EAX
	mov word ptr [ebp].Client_Reg_Struc.Client_EAX, ax

	@VMMCall Begin_Nest_Exec
	mov eax, 16h
	@VMMCall Exec_Int
	@VMMCall End_Nest_Exec

	mov ax, word ptr [ebp].Client_Reg_Struc.Client_EAX
	pop [ebp].Client_Reg_Struc.Client_EAX

	mov word ptr [esp].PUSHADS._eax, ax
	popad
	mov ss, [dwDS16]
	sub esp, [dwBase]
	pop es
	pop ds
	ret
callint16 endp

main proc c

local dwCS16:dword

	mov ebx, offset start16
	mov [dwBase], ebx

;--- get GDT descriptor for 16-bit code

	mov edx, cs
	lar ecx, edx
	and ecx, 0000ff00h
	shrd eax, ebx, 16	; get lower 16 bits of base
	mov ax, SIZEBIN16
	add ax, MEMADD
	shld edx, ebx, 16	; get upper 16 bits of base
	mov cl, dl
	shr edx, 8
	shl ecx, 8
	shrd ecx, edx, 8

	push ecx
	push eax

	push ecx     ; hi32 descriptor
	push eax     ; lo32 descriptor
	push 0       ; flags
	@VMMCall _Allocate_GDT_Selector
	add esp, 3*4
	pop edx
	pop ecx
	and eax, eax
	jz errorcs
	mov dwCS16, eax
	invoke printf, CStr("GDT selector for code: %X",13,10), eax

;--- get GDT descriptor for 16-bit data

	xor ch, 8

	push ecx     ; hi32 descriptor
	push edx     ; lo32 descriptor
	push 0       ; flags
	@VMMCall _Allocate_GDT_Selector
	add esp, 3*4
	and eax, eax
	jz errords
	invoke printf, CStr("GDT selector for data: %X",13,10), eax
	mov [dwDS16], eax
	mov [dwFlat], ss
	mov ebx, offset callint10	; int 10h vector
	mov edx, offset callint16	; int 16h vector

	mov ecx, dwCS16
	push cs
	push offset @F
	push ecx
	push 0
	retd
@@:
	invoke printf, CStr("JemmDbg loaded and initialized",13,10)

if 0
;--- activate debugger
	int 3
endif

	mov eax, 1
	ret
errorcs:
	invoke printf, CStr("Allocate_GDT_selector() [code] failed",13,10)
	jmp @F
errords:
	invoke printf, CStr("Allocate_GDT_selector() [data] failed",13,10)
@@:
	xor eax, eax
	ret
main ENDP

DLL_PROCESS_DETACH equ 0
DLL_PROCESS_ATTACH equ 1

DllMain proc stdcall uses esi edi hModule:dword, dwReason:dword, dwRes:dword

	mov eax, dwReason
	cmp eax, DLL_PROCESS_ATTACH
	jnz @F
	mov eax, hModule
	mov hModuleStat, eax
	call main
	jmp done
@@:
	xor eax, eax	; refuse to uninstall
done:
	ret

DllMain endp

	END DllMain
