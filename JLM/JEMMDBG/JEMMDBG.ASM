
;--- load the 16-bit DebugR blob resource
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
dwDS16 dd 0
dfDebugger label fword
	dd 0
dwCS16 dd 0
dfGetR0Stk label fword
	dd 3
	dd 0
dwEAX dd 0
dwEDX dd 0
dwScratch dd 0
dfSsEsp df 0

_DATA16 segment para FLAT public 'DATA'

start16 label byte
	incbin <DebugR.bin>
SIZEBIN16 equ $ - offset start16
	db MEMADD dup (?)

_DATA16 ends

	.CODE

GetModuleHandle proc hhandle:dword
	mov eax, hModuleStat
	ret
GetModuleHandle endp

	include printf.inc

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
	mov ds, cs:[dwFlat]
	mov es, [dwFlat]

;--- switch to Jemm's stack

	mov dword ptr [dfSsEsp], esp
	mov word ptr [dfSsEsp+4], ss
	mov [dwEAX], eax
	mov [dwEDX], edx
	call [dfGetR0Stk]
	mov ss, dx
	mov esp, eax
	mov eax, [dwEAX]
	mov edx, [dwEDX]

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

;--- switch back to Debug's stack

	lss esp, [dfSsEsp]
	pop es
	pop ds
	ret
callint10 endp

;--- debugger callback
;--- run an Int 16h

callint16 proc far

	push ds
	push es
	mov ds, cs:[dwFlat]
	mov es, [dwFlat]
	mov dword ptr [dfSsEsp], esp
	mov word ptr [dfSsEsp+4], ss
	mov [dwEAX], eax
	mov [dwEDX], edx
	call [dfGetR0Stk]
	mov ss, dx
	mov esp, eax
	mov eax, [dwEAX]
	mov edx, [dwEDX]

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
	lss esp, [dfSsEsp]
	pop es
	pop ds
	ret
callint16 endp

;--- option stackbase:esp is used so register EBP
;--- ( holding the "client_reg_struct" pointer ) isn't modified.
;--- however, this option is rather problematic for 32-bit code,
;--- since any push will change the offset of stack variables
;--- ( there's NO automatic adjustment ).

	option stackbase:esp

;--- main. esi=cmdline

main proc c

;--- get GDT descriptor for 16-bit code

	mov ebx, offset start16
	mov edx, cs
	lar ecx, edx
	and ecx, 0000ff00h
	shrd eax, ebx, 16	; get lower 16 bits of base
	mov ax, SIZEBIN16 + MEMADD
	and al, 0F0h
	dec ax
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
	mov dword ptr dfGetR0Stk+4, eax

;--- get GDT descriptor for 16-bit data

	xor ch, 8

	push ecx     ; hi32 descriptor
	push edx     ; lo32 descriptor
	push 0       ; flags
	@VMMCall _Allocate_GDT_Selector
	add esp, 3*4

	and eax, eax
	jz errords
	mov [dwDS16], eax

;--- get GDT descriptor as scratchselector for debugger

	mov cx, 9300h	; ensure attributes aren't 0
	push ecx
	push 0
	push 0
	@VMMCall _Allocate_GDT_Selector
	add esp, 3*4
	and eax, eax
	jz errorsc
	mov [dwScratch], eax

	invoke printf, CStr("GDT selectors for code/data/scratch: %X/%X/%X",13,10), dwCS16, dwDS16, dwScratch

	mov [dwFlat], ds

	mov eax, [dwDS16]
	push ebp
	lsl bp, ax
	inc bp
	mov edi, [dwScratch]
	mov ebx, offset callint10	; int 10h vector
	mov edx, offset callint16	; int 16h vector
	mov ecx, ds

;--- registers setup:
;--- ax=debugger's data segment
;--- cx=flat data selector
;--- di=scratch selector
;--- ebx=linear address vio out
;--- edx=linear address kbd in
;--- esi=linear address cmdline

	call [dfDebugger]
	pop ebp

	invoke printf, CStr("JemmDbg loaded and initialized",13,10)
	mov eax, 80000001h	; bit 31=1: suppress JLoad msg
	ret
errorcs:
	invoke printf, CStr("Allocate_GDT_selector() [code] failed",13,10)
	jmp @F
errords:
	invoke printf, CStr("Allocate_GDT_selector() [data] failed",13,10)
	jmp @F
errorsc:
	invoke printf, CStr("Allocate_GDT_selector() [scratch] failed",13,10)
@@:
	xor eax, eax
	ret
main endp

DLL_PROCESS_DETACH equ 0
DLL_PROCESS_ATTACH equ 1

DllMain proc stdcall uses esi edi hModule:dword, dwReason:dword, dwRes:dword

	mov eax, dwReason
	cmp eax, DLL_PROCESS_ATTACH
	jnz @F
	mov eax, hModule
	mov hModuleStat, eax

	mov esi, dwRes
ifdef _DEBUG
	invoke printf, CStr("Cmdline: %s",13,10), [esi].JLCOMM.lpCmdLine
endif
	call main
	jmp done
@@:
	xor eax, eax	; refuse to uninstall
done:
	ret

DllMain endp

	END DllMain
