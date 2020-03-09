
;--- CPUSTAT displays status of CPU. 
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

	.data

dwCR0	dd 0
_msw	dd 0

gdtr	label fword
gdtl	dw 0
gdta	dd 0

idtr	label fword
idtl	dw 0
idta	dd 0

cpubrand label dword
dwCPUIDeax dd 0
dwCPUIDebx dd 0
dwCPUIDedx dd 0
dwCPUIDecx dd 0
		db 0

tradr	dw 0
ldt 	dw 0

modflg	dw 0
wSize	dw 0
bGDT	db 0
bIDT	db 0
bCpu	db 0

;--- gdt for In15 ah=87 move

DESCRIPTOR struct
wLimit		dw ?
wBase0015	dw ?
bBase1623	db ?
bAttrL		db ?
bAttrH		db ?
bBase2431	db ?
DESCRIPTOR ends

gdti15 label DESCRIPTOR
		DESCRIPTOR <0,0,0,0,0,0>
		DESCRIPTOR <0,0,0,0,0,0>
i15src	DESCRIPTOR <-1,0,0,093h,0,0>
i15dst	DESCRIPTOR <-1,0,0,093h,0,0>
		DESCRIPTOR <0,0,0,0,0,0>
		DESCRIPTOR <0,0,0,0,0,0>

	.data?

buffer	db 800h dup (?)

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

cpuid1 proc uses ebx
	invoke printf, CStr("CPUID 1 features (EDX,ECX):",lf)
	mov ebx,dwCPUIDedx
	bt ebx, 0
	jnc @F
	invoke printf, CStr("FPU integrated",lf)
@@:
	bt ebx, 1
	jnc @F
	invoke printf, CStr("VME - Virtual-8086 Mode Enhancement [CR4 VME/PVI & EFL VIF/VIP]",lf)
@@:
	bt ebx, 2
	jnc @F
	invoke printf, CStr("DE - Debugging Extensions [I/O breakpoints & CR4 DE]",lf)
@@:
	bt ebx, 3
	jnc @F
	invoke printf, CStr("PSE - Page Size Extensions [4 MB page size & CR4 PSE]",lf)
@@:
	bt ebx, 4
	jnc @F
	invoke printf, CStr("TSC - Time Stamp Counter [RDTSC & CR4 TSD]",lf)
@@:
	bt ebx, 5
	jnc @F
	invoke printf, CStr("MSR - RDMSR & WRMSR support",lf)
@@:
	bt ebx, 6
	jnc @F
	invoke printf, CStr("PAE - Physical Address Extensions [CR4 PAE]",lf)
@@:
	bt ebx, 7
	jnc @F
	invoke printf, CStr("MCE - Machine Check Exceptions [CR4 MCE]",lf)
@@:
	bt ebx, 8
	jnc @F
	invoke printf, CStr("CX8 - CMPXCHG8B",lf)
@@:
	bt ebx, 9
	jnc @F
	invoke printf, CStr("APIC - on chip APIC exists and enabled",lf)
@@:
	bt ebx, 11
	jnc @F
	invoke printf, CStr("SEP - SYSENTER & SYSEXIT",lf)
@@:
	bt ebx, 12
	jnc @F
	invoke printf, CStr("MTRR -  Memory Type Range Registers",lf)
@@:
	bt ebx, 13
	jnc @F
	invoke printf, CStr("PGE - PTE Global Bit [CR4 PGE]",lf)
@@:
	bt ebx, 14
	jnc @F
	invoke printf, CStr("MCA - Machine Check Architecture",lf)
@@:
	bt ebx, 15
	jnc @F
	invoke printf, CStr("CMOV & FCMOV/FCOM1",lf)
@@:
	bt ebx, 16
	jnc @F
	invoke printf, CStr("PAT - Page Attribute Table",lf)
@@:
	bt ebx, 17
	jnc @F
	invoke printf, CStr("PSE-36 - Page Size Extension",lf)
@@:
	bt ebx, 19
	jnc @F
	invoke printf, CStr("CFLSH - CFLUSH instruction",lf)
@@:
	bt ebx, 21
	jnc @F
	invoke printf, CStr("DS - Debug Store",lf)
@@:
	bt ebx, 22
	jnc @F
	invoke printf, CStr("ACPI - Thermal Monitor & Clock Control",lf)
@@:
	bt ebx, 23
	jnc @F
	invoke printf, CStr("MMX",lf)
@@:
	bt ebx, 24
	jnc @F
	invoke printf, CStr("FXSAVE/FXRSTOR",lf)
@@:
	bt ebx, 25
	jnc @F
	invoke printf, CStr("SSE",lf)
@@:
	bt ebx, 26
	jnc @F
	invoke printf, CStr("SSE2",lf)
@@:
	bt ebx, 28
	jnc @F
	invoke printf, CStr("HTT - Multi Threading",lf)
@@:
	bt ebx, 29
	jnc @F
	invoke printf, CStr("TM - Thermal Monitoring",lf)
@@:
	bt ebx, 31
	jnc @F
	invoke printf, CStr("PBE - Pending Brk Enable",lf)
@@:
	mov ebx,dwCPUIDecx
	bt ebx, 0
	jnc @F
	invoke printf, CStr("SSE3",lf)
@@:
	bt ebx, 1
	jnc @F
	invoke printf, CStr("PCLMULQDQ - Carryless Multiplication",lf)
@@:
	bt ebx, 2
	jnc @F
	invoke printf, CStr("DTES64 - 64 bit DS Area",lf)
@@:
	bt ebx, 3
	jnc @F
	invoke printf, CStr("MONITOR - MONITOR/MWAIT",lf)
@@:
	bt ebx, 5
	jnc @F
	invoke printf, CStr("VMX - Virtual Machine Extensions",lf)
@@:
	bt ebx, 7
	jnc @F
	invoke printf, CStr("EIST - Intel SpeedStep",lf)
@@:
	bt ebx, 8
	jnc @F
	invoke printf, CStr("TM2 - Thermal Monitor 2",lf)
@@:
	bt ebx, 9
	jnc @F
	invoke printf, CStr("SSSE3",lf)
@@:
	bt ebx, 13
	jnc @F
	invoke printf, CStr("CMPXCHG16B",lf)
@@:
	bt ebx, 19
	jnc @F
	invoke printf, CStr("SSE4.1",lf)
@@:
	bt ebx, 20
	jnc @F
	invoke printf, CStr("SSE4.2",lf)
@@:
	bt ebx, 23
	jnc @F
	invoke printf, CStr("POPCNT",lf)
@@:
	bt ebx, 26
	jnc @F
	invoke printf, CStr("XSAVE",lf)
@@:
	bt ebx, 28
	jnc @F
	invoke printf, CStr("AVX - Advanced Vector Extensions",lf)
@@:
	bt ebx, 30
	jnc @F
	invoke printf, CStr("RDRAND",lf)
@@:
	ret
cpuid1 endp

cpuid7 proc uses ebx
	invoke printf, CStr("CPUID 7 features (EBX):",lf)
    bt ebx,0
    jnc @F
    invoke printf, CStr("access to base of FS and GS",lf)
@@:
    bt ebx,1
    jnc @F
    invoke printf, CStr("IA32_TSC_ADJUST",lf)
@@:
    bt ebx,2
    jnc @F
    invoke printf, CStr("SGX - Software Guard Extensions",lf)
@@:
    bt ebx,3
    jnc @F
    invoke printf, CStr("BMI1 - Bit Manipulation Instruction Set 1",lf)
@@:
    bt ebx,4
    jnc @F
    invoke printf, CStr("TSX Hardware Lock Elision",lf)
@@:
    bt ebx,5
    jnc @F
    invoke printf, CStr("AVX2 - Advanced Vector Extensions 2",lf)
@@:
    bt ebx,7
    jnc @F
    invoke printf, CStr("SMEP - Supervisor Mode Execution Prevention",lf)
@@:
    bt ebx,8
    jnc @F
    invoke printf, CStr("BMI2 - Bit Manipulation Instruction Set 2",lf)
@@:
    ret
cpuid7 endp

cpuid80000001 proc uses ebx
	invoke printf, CStr("CPUID 80000001 features (EDX,ECX):",lf)
	mov ebx,dwCPUIDedx
	bt ebx,11
	jnc @F
	invoke printf, CStr("SYSCALL & SYSRET",lf)
@@:
	bt ebx,26
	jnc @F
	invoke printf, CStr("1 GB pages",lf)
@@:
	bt ebx,29
	jnc @F
	invoke printf, CStr("long mode (cpu is 64-bit)",lf)
@@:
	bt ebx,31
	jnc @F
	invoke printf, CStr("3DNow",lf)
@@:
	mov ebx,dwCPUIDecx
	bt ebx,2
	jnc @F
	invoke printf, CStr("SVM",lf)
@@:
	bt ebx,6
	jnc @F
	invoke printf, CStr("SSE4A",lf)
@@:
	ret
cpuid80000001 endp

main proc c argc:word, argv:word

	mov si,80h
	mov cl,es:[si]
	inc si

	.while (cl)
		mov al,es:[si]
		inc si
		dec cl
		.if (al == ' ' || al == 9)
			;
		.elseif ( cl > 0 && ( al == '-' || al == '/'))
			mov al,es:[si]
			inc si
			dec cl
			or al,20h
			.if (al == 'i')
				mov bIDT, 1
			.elseif (al == 'g')
				mov bGDT, 1
			.else
				jmp usage
			.endif
		.else
usage:
			invoke printf, CStr("usage: CPUSTAT [ options ]",lf)
			invoke printf, CStr("    -g: display GDT if in V86 mode",lf)
			invoke printf, CStr("    -i: display IDT if in V86 mode",lf)
			jmp exit
		.endif
	.endw

	pushf
	mov ax,7000h
	PUSH AX					 ; also kept after a POPF
	POPF					 ; a 286 always sets it to Null
	PUSHF
	POP AX
	popf
	and ah,0F0h
	cmp AH,70H				;on a 80386 (real-mode) 7x is in AH
	jnz is286
	db 66h		;MASM doesn't know SMSW EAX
	smsw ax
	mov [_msw],eax
	jmp is386
is286:
	smsw ax
	invoke printf, CStr("MSW: %X",lf), ax
	invoke printf, CStr("CPU is not 80386 or better",lf)
	jmp exit
is386:
	and ax,1
	mov [modflg],ax

	mov eax,[_msw]
	bt eax,31
	setc dl
	movzx si,dl
	bt eax,18
	setc dl
	movzx di,dl
	bt eax,16
	setc cl
	movzx cx,cl
	bt ax,5
	setc dl
	movzx dx,dl

	mov bx,CStr('Real')
	bt ax,0
	setc al
	jnc @F
	mov bx,CStr('V86')
@@:    
	movzx ax,al
	invoke printf, CStr("MSW: %lX (PG=%x, AM=%x, WP=%x, NE=%x, PE=%x); %s-mode",lf),_msw, si, di, cx, dx, ax, bx 

	db 66h
	sgdt gdtr
	db 66h
	sidt idtr

	cmp bGDT, 0
	jnz optional
	cmp bIDT, 0
	jnz optional

	mov eax, 0		;in case the next instr is "emulated"
	mov eax, cr0 	;cr0 (=msw)
	mov [dwCR0],eax
	and ax,1

	cmp ax,modflg
	jz @F
	invoke printf, CStr("'MOV EAX,CR0' emulated incorrectly!",lf)
@@:
	invoke printf, CStr("CR0: %lX",lf),dwCR0

	invoke printf, CStr("GDTR: %lX,%X  "),gdta,gdtl
	invoke printf, CStr("IDTR: %lX,%X",lf),idta,idtl

	mov eax, -1		;in case the next instr is "emulated"
	mov eax, cr2
	invoke printf, CStr("CR2: %lX  "),eax

	mov eax, -1		;in case the next instr is "emulated"
	mov eax, cr3
	invoke printf, CStr("CR3: %lX",lf),eax

	invoke hascpuid
	jc nocpuid

	mov eax, -1		;in case the next instr is "emulated"
	xor cx,cx
	xor dx,dx
	xor bx,bx
	mov eax, cr4	;priviledged instruction
	test al,1
	setnz cl
	test al,2
	setnz dl
	test al,10h
	setnz bl
	test al,20h
	setnz ch
	movzx si,ch
	test al,80h
	setnz ch
	movzx di,ch
	test ax,200h
	setnz ch
	movzx bp,ch
	mov ch,0
	invoke printf, CStr("CR4: %lX (VME=%X, PVI=%X, PSE=%X, PAE=%X, PGE=%X, OSFXSR=%X)",lf), eax,cx,dx,bx,si,di,bp

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
	call cpuid1		;display cpuid 1 in more detail

	cmp byte ptr dwCPUIDeax,7
	jc @F
	mov eax,7		;get extended features (returns features in ebx, ecx, edx)
	mov ecx,0
	cpuid
	call cpuid7
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
	call cpuid80000001		;display value returned in edx in more detail
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
	jc nocpuid
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
nocpuid:
if 0
	cmp [bCpu],5
	jb @F
	fnstsw ax
	fnstcw [wSize]
	invoke printf, CStr("FCW: %X  FSW: %X",lf), [wSize], ax
@@:
endif
if 0	;not available in real/v86 mode
	str ax
	movzx eax,ax
	sldt bx
	movzx ebx,bx
	invoke printf, CStr("LDT: %lX, TR: %lX",lf),ebx, eax
endif
if 0
	mov eax, dr6
	mov ecx, dr7
	invoke printf, CStr("DR6: %lX  DR7: %lX",lf), eax, ecx
	pushfd
	pop eax
	invoke printf, CStr("EFL: %lX, ESP: %lX",lf), eax, esp
endif

optional:
	.if (bGDT)
		.if byte ptr [_msw] & 1	;v86 mode?
			call DispGDT
		.else
			invoke printf, CStr("no GDT in real-mode",lf)
		.endif
	.endif
	.if (bIDT)
		.if byte ptr [_msw] & 1	;v86 mode?
			call DispIDT
		.else
			invoke printf, CStr("no IDT in real-mode",lf)
		.endif
	.endif

exit:
	mov al,0
	ret

main endp

;--- the GDT/IDT is read with int 15h, ah=87h
;--- this is not really correct, since this function
;--- is supposed to read from physical addresses, while
;--- the addresses in GDTR/IDTR are linear;
;--- for jemmex, it often works, though, since its
;--- code/data usually are identity-mapped, starting
;--- at 0x110000.

DispGDT proc
	mov cx,gdtl 
	inc cx
	cmp cx,sizeof buffer
	jc @F
	mov cx,sizeof buffer
@@:
	mov wSize,cx
	shr cx,1
	mov eax, gdta
	mov i15src.wBase0015,ax
	shr eax, 16
	mov i15src.bBase1623,al
	mov i15src.bBase2431,ah
	mov ax, offset buffer
	movzx eax,ax
	mov dx,ds
	movzx edx,dx
	shl edx, 4
	add eax, edx
	mov i15dst.wBase0015,ax
	shr eax, 16
	mov i15dst.bBase1623,al
	mov i15dst.bBase2431,ah
	push ds
	pop es
	mov si, offset gdti15
	mov ah,87h
	stc
	int 15h
	jc error
	mov cx, wSize
	shr cx, 3
	jcxz nogdt
	mov si, offset buffer
nextitem:
	push cx
	mov cx,[si+0]
	mov bh,[si+7]
	mov bl,[si+4]
	shl ebx,16
	mov bx,[si+2]
	mov dx,[si+5]
	movzx eax,cx
	or eax, ebx
	or ax, dx
	and eax, eax
	jz @F
	mov di,si
	sub di, offset buffer
	invoke printf, CStr(<"GDT[%4X]: %08lX:%04X %04X",lf>), di, ebx, cx, dx
@@:
	add si, 8
	pop cx
	loop nextitem
nogdt:
	ret
error:
	invoke printf, CStr(<"Int 15h, ah=87h failed",lf>)
	ret
DispGDT endp

DispIDT proc
	mov cx,idtl 
	inc cx
	cmp cx,sizeof buffer
	jc @F
	mov cx,sizeof buffer
@@:
	mov wSize,cx
	shr cx,1
	mov eax, idta
	mov i15src.wBase0015,ax
	shr eax, 16
	mov i15src.bBase1623,al
	mov i15src.bBase2431,ah
	mov ax, offset buffer
	movzx eax,ax
	mov dx,ds
	movzx edx,dx
	shl edx, 4
	add eax, edx
	mov i15dst.wBase0015,ax
	shr eax, 16
	mov i15dst.bBase1623,al
	mov i15dst.bBase2431,ah
	push ds
	pop es
	mov si, offset gdti15	;es:si=gdt to use
	mov ah,87h
	stc
	int 15h
	jc error
	mov cx, wSize
	shr cx, 3
	jcxz noidt
	mov si, offset buffer
	xor di,di
	int 3
nextitem:
	push cx
	mov ax,[si+6]
	shl eax, 16
	mov ax,[si+0]
	mov bx,[si+2]
	mov dx,[si+4]
	invoke printf, CStr(<"IDT[%4X]: %04X:%08lX %04X",lf>), di, bx, eax, dx
@@:
	inc di
	add si, 8
	pop cx
	loop nextitem
noidt:
	ret
error:
	invoke printf, CStr(<"Int 15h, ah=87h failed",lf>)
	ret
DispIDT endp

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
