
;--- CPUID displays status of CPU. 
;--- Public Domain.
;--- Masm syntax. To be assembled with JWasm or Masm.
;--- uses 16-bit printf

	.286 
	.model small
	.dosseg
	.stack 400h

bs	equ 8
lf	equ 10

printf proto c :ptr BYTE, :VARARG

CStr macro y:VARARG
local sym
	.const
sym db y,0
	.code
	exitm <offset sym>
	endm

DStr macro text:vararg
local sym
	.const
sym db text,0
	.data
	exitm <offset sym>
endm

	.data

cpubrand label dword
dwCPUIDeax dd 0
dwCPUIDebx dd 0
dwCPUIDedx dd 0
dwCPUIDecx dd 0
		db 0
bCpu	db 0

;--- cpuid.1 EDX features
;--- note: bit 10,20,30 not assigned!

cpuid1_edx_bits db 0,1,2,3,4,5,6,7,8,9,11,12,13,14,15,16,17,19,21,22,23,24,25,26,28,29,31
cpuid1_edx_str label word
	dw DStr("FPU integrated",lf)
	dw DStr("VME - Virtual-8086 Mode Enhancement [CR4 VME/PVI & EFL VIF/VIP]",lf)
	dw DStr("DE - Debugging Extensions [I/O breakpoints & CR4 DE]",lf)
	dw DStr("PSE - Page Size Extensions [4 MB page size & CR4 PSE]",lf)
	dw DStr("TSC - Time Stamp Counter [RDTSC & CR4 TSD]",lf)
	dw DStr("MSR - RDMSR & WRMSR support",lf)
	dw DStr("PAE - Physical Address Extensions [CR4 PAE]",lf)
	dw DStr("MCE - Machine Check Exceptions [CR4 MCE]",lf)
	dw DStr("CX8 - CMPXCHG8B",lf)
	dw DStr("APIC - on chip APIC exists and enabled",lf)
	dw DStr("SEP - SYSENTER & SYSEXIT",lf)
	dw DStr("MTRR -  Memory Type Range Registers",lf)
	dw DStr("PGE - PTE Global Bit [CR4 PGE]",lf)
	dw DStr("MCA - Machine Check Architecture",lf)
	dw DStr("CMOV & FCMOV/FCOM1",lf)
	dw DStr("PAT - Page Attribute Table",lf)
	dw DStr("PSE-36 - Page Size Extension",lf)
	dw DStr("CFLSH - CFLUSH instruction",lf)
	dw DStr("DS - Debug Store",lf)
	dw DStr("ACPI - Thermal Monitor & Clock Control",lf)
	dw DStr("MMX -  64-bit MultiMedia Extensions",lf)
	dw DStr("FXSAVE/FXRSTOR",lf)
	dw DStr("SSE",lf)
	dw DStr("SSE2",lf)
	dw DStr("HTT - Multi Threading",lf)
	dw DStr("TM - Thermal Monitoring",lf)
	dw DStr("PBE - Pending Brk Enable",lf)

cpuid1_ecx_bits db 0,1,2,3,5,7,8,9,13,19,20,23,26,28,30
cpuid1_ecx_str label word
	dw DStr("SSE3",lf)
	dw DStr("PCLMULQDQ - Carryless Multiplication",lf)
	dw DStr("DTES64 - 64 bit DS Area",lf)
	dw DStr("MONITOR - MONITOR/MWAIT",lf)
	dw DStr("VMX - Virtual Machine Extensions",lf)
	dw DStr("EIST - Intel SpeedStep",lf)
	dw DStr("TM2 - Thermal Monitor 2",lf)
	dw DStr("SSSE3",lf)
	dw DStr("CMPXCHG16B",lf)
	dw DStr("SSE4.1",lf)
	dw DStr("SSE4.2",lf)
	dw DStr("POPCNT",lf)
	dw DStr("XSAVE",lf)
	dw DStr("AVX - Advanced Vector Extensions",lf)
	dw DStr("RDRAND",lf)

cpuid1m label word
	dw DStr("CPUID 1 features (EDX,ECX):",lf)
	dw offset dwCPUIDedx,offset cpuid1_edx_bits,offset cpuid1_edx_str,sizeof cpuid1_edx_bits
	dw offset dwCPUIDecx,offset cpuid1_ecx_bits,offset cpuid1_ecx_str,sizeof cpuid1_ecx_bits

cpuid1x_edx_bits db 11,22,26,29,31
cpuid1x_edx_str label word
	dw DStr("SYSCALL & SYSRET",lf)
	dw DStr("MMX Extensions",lf)
	dw DStr("1 GB pages",lf)
	dw DStr("long mode (cpu is 64-bit)",lf)
	dw DStr("3DNow",lf)

cpuid1x_ecx_bits db 0,2,6,21
cpuid1x_ecx_str label word
	dw DStr("LahfSahf -  LAHF/SAHF supported in 64-bit",lf)
	dw DStr("SVM -  Secure Virtual Machine",lf)
	dw DStr("SSE4A",lf)
	dw DStr("TBM - Trailing Bit Manipulation",lf)

cpuid1xm label word
	dw DStr("CPUID 80000001 features (EDX,ECX):",lf)
	dw offset dwCPUIDedx,offset cpuid1x_edx_bits,offset cpuid1x_edx_str,sizeof cpuid1x_edx_bits
	dw offset dwCPUIDecx,offset cpuid1x_ecx_bits,offset cpuid1x_ecx_str,sizeof cpuid1x_ecx_bits

cpuid7_ebx_bits db 0,1,2,3,4,5,7,8,18
cpuid7_ebx_str label word
	dw DStr("access to base of FS and GS",lf)
	dw DStr("IA32_TSC_ADJUST",lf)
	dw DStr("SGX - Software Guard Extensions",lf)
	dw DStr("BMI1 - Bit Manipulation Instruction Set 1",lf)
	dw DStr("TSX Hardware Lock Elision",lf)
	dw DStr("AVX2 - Advanced Vector Extensions 2",lf)
	dw DStr("SMEP - Supervisor Mode Execution Prevention",lf)
	dw DStr("BMI2 - Bit Manipulation Instruction Set 2",lf)
	dw DStr("RDSEED - RDSEED supported",lf)

cpuid7m label word
	dw DStr("CPUID 7 features (EBX):",lf)
	dw offset dwCPUIDebx,offset cpuid7_ebx_bits,offset cpuid7_ebx_str,sizeof cpuid7_ebx_bits

	.code

	.586

	include printf.inc

hascpuid proc
	push di
	mov di,sp
	and sp,0fffch	;make sure we don't get an exc 11 (if AM set in CR0)
	pushfd						; save EFlags
	cli
	pushd 240000h				; set AC bit in eflags, reset IF
	popfd						; pop extended flags
	pushfd						; push extended flags
	pop ax
	pop ax						; get HiWord(EFlags) into AX
	popfd						; restore EFlags
	test al,04	;AC bit set?
	je @F
	test al,20h	;CPUID bit set?
	jz @F
	mov sp,di
	pop di
	clc
	ret
@@:
	mov sp,di
	pop di
	stc
	ret
hascpuid endp

;--- print features

print_cpuid_regs proc stdcall uses ebx si di items:word, pp:ptr
	mov si,pp
	lodsw
	invoke printf, ax
	mov cx,items
nextreg:
	push si
	push cx
	mov bx,[si+0]
	mov di,[si+4]
	mov cx,[si+6]
	mov si,[si+2]

	mov ebx,[bx]
nextitem:
	push cx
	lodsb
	movzx eax,al
	bt ebx, eax
	jnc @F
	mov cx,[di]
	invoke printf, CStr("%2u %s"), ax, cx
	add di,2
@@:
	pop cx
	loop nextitem
	pop cx
	pop si
	add si,4*2
	loop nextreg
	ret
print_cpuid_regs endp

main proc c

	pushf
	mov ax,7000h
	PUSH AX					 ; also kept after a POPF
	POPF					 ; a 286 always sets it to Null
	PUSHF
	POP AX
	popf
	and ah,0F0h
	cmp AH,70H				;on a 80386 (real-mode) 7x is in AH
	jz is386
	invoke printf, CStr("CPU is not 80386 or better",lf)
	jmp exit
is386:
	invoke hascpuid
	jnc @F
	invoke printf, CStr("CPUID not implemented",lf)
	jmp exit
@@:
	mov eax,0
	cpuid
	mov dwCPUIDeax, eax
	mov dwCPUIDebx, ebx
	mov dwCPUIDecx, ecx
	mov dwCPUIDedx, edx
	invoke printf, CStr("CPUID.00: EAX=%lX string=%s",lf), \
		eax, offset dwCPUIDebx

	mov eax,1
	cpuid
	mov [bCpu],ah
	mov dwCPUIDebx, ebx
	mov dwCPUIDecx, ecx
	mov dwCPUIDedx, edx
	invoke printf, CStr("CPUID.01: EAX-EBX-ECX-EDX: %lX-%lX-%lX-%lX",lf), \
		dwCPUIDeax, dwCPUIDebx, dwCPUIDecx, dwCPUIDedx
	mov eax, dwCPUIDebx
	shr eax,16
	mov ah,0
	invoke printf, CStr("Logical Processors (EBX[16-23], req. HTT=1): %u",lf), ax

	invoke print_cpuid_regs, 2, offset cpuid1m	;display cpuid 1 in more detail

	cmp byte ptr dwCPUIDeax,7
	jc @F
	mov eax,7		;get extended features (returns features in ebx, ecx, edx)
	mov ecx,0
	cpuid
	mov dwCPUIDebx, ebx
	invoke print_cpuid_regs, 1, offset cpuid7m
@@:
	mov eax,80000000h
	cpuid
	mov dwCPUIDeax, eax
	invoke printf, CStr("CPUID.80000000: EAX=%lX",lf), eax

	cmp byte ptr dwCPUIDeax,1
	jc nobrand
	mov eax,80000001h
	cpuid
	mov dwCPUIDebx, ebx
	mov dwCPUIDecx, ecx
	mov dwCPUIDedx, edx
	invoke printf, CStr("CPUID.80000001: EAX-EBX-ECX-EDX=%lX-%lX-%lX-%lX",lf), \
		eax, ebx, ecx, edx
	invoke print_cpuid_regs, 2, offset cpuid1xm	;display values returned in edx, ecx

	cmp byte ptr dwCPUIDeax, 5
	jb nobrand
	mov eax,80000002h
	cpuid
	mov cpubrand+0, eax
	mov cpubrand+4, ebx
	mov cpubrand+8, ecx
	mov cpubrand+12, edx
	invoke printf, CStr("CPUID.80000002/3/4: brand=%s"), offset cpubrand
	mov eax,80000003h
	cpuid
	mov cpubrand+0, eax
	mov cpubrand+4, ebx
	mov cpubrand+8, ecx
	mov cpubrand+12, edx
	invoke printf, CStr("%s"), offset cpubrand
	mov eax,80000004h
	cpuid
	mov cpubrand+0, eax
	mov cpubrand+4, ebx
	mov cpubrand+8, ecx
	mov cpubrand+12, edx
	invoke printf, CStr("%s",lf), offset cpubrand
nobrand:
	cmp byte ptr dwCPUIDeax,8
	jc no8ex
	mov eax,80000008h
	cpuid
	mov dwCPUIDeax, eax
	invoke printf, CStr("CPUID.80000008: EAX-EBX-ECX-EDX=%lX-%lX-%lX-%lX",lf), \
		eax, ebx, ecx, edx
	mov eax,dwCPUIDeax
	mov cx, ax
	and cx,0ffh
	shr ax,8
	and ax,0ffh
	invoke printf, CStr("physical/linear address bits=%u/%u",lf), cx, ax
no8ex:
exit:
	mov al,0
	ret

main endp

start:
	mov ax,@data
	mov ds,ax
	mov bx,ss
	mov cx,ds
	sub bx,cx
	shl bx,4
	add bx,sp
	mov ss,ax
	mov sp,bx
	call main
	mov ah,4Ch
	int 21h

	END start
