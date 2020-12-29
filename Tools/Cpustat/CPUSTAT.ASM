
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

modflg	dw 0
wSize	dw 0
bGDT	db 0
bIDT	db 0

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

myint0c:
myint0d:
	shr ecx,1
	iret

DispSegLimits proc

local limitss:dword
local limitds:dword
local limites:dword
local limitfs:dword
local limitgs:dword

	push ds
	push es
	push fs
	push gs
	xor ax,ax
	mov ds,ax
	mov es,ax
	mov fs,ax
	mov gs,ax

	mov ax,cs
	shl eax,16
	mov ax,offset myint0d
	cli
	xchg eax,ds:[13*4]
	push eax

;--- SS limit violation creates an exception 0Ch!
	mov ax,cs
	shl eax,16
	mov ax,offset myint0c
	xchg eax,ds:[12*4]
	push eax
if 0
	mov dx,ss
	mov bx,sp
	xor ax,ax
	mov ss,ax
	mov sp,400h
endif
	mov ecx,-1
	mov al,ss:[ecx]
if 0
	mov ss,dx
	mov sp,bx
endif
	mov limitss,ecx
	pop eax
	mov ds:[12*4],eax

	mov ecx,-1
	mov al,ds:[ecx]
	mov limitds,ecx

	mov ecx,-1
	mov al,es:[ecx]
	mov limites,ecx

	mov ecx,-1
	mov al,fs:[ecx]
	mov limitfs,ecx

	mov ecx,-1
	mov al,gs:[ecx]
	mov limitgs,ecx

	pop eax
	mov ds:[13*4],eax
	sti
	pop gs
	pop fs
	pop es
	pop ds
	invoke printf, CStr("SS-DS-ES-FS-GS limits: %lX-%lX-%lX-%lX-%lX",lf), limitss, limitds, limites, limitfs, limitgs
	ret

DispSegLimits endp

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

	mov eax, -1		;in case the next instr is "emulated"

	call hascpuid	;if CPUID is supported, CR4 exists as well
	jc nocr4

	mov eax, cr4	;priviledged instruction
	mov ch,0
	mov bp,sp
	test al,1		;VME?
	setnz cl
	push cx
	test al,2		;PVI?
	setnz cl
	push cx
	test al,8		;DE?
	setnz cl
	push cx
	test al,10h		;PSE?
	setnz cl
	push cx
	test al,20h		;PAE?
	setnz cl
	push cx
	test al,40h		;MCE?
	setnz cl
	push cx
	test al,80h		;PGE?
	setnz cl
	push cx
	test ax,200h	;OSFXSR?
	setnz cl
	push cx
	test ax,400h	;OSXMMEXP?
	setnz cl
	push cx
	invoke printf, CStr("CR4: %lX (VME=%X, PVI=%X, DE=%X, PSE=%X, PAE=%X, MCE=%X, PGE=%X, OSFXSR=%X, OSXMMEX=%X)",lf), eax,
		word ptr [bp-2],word ptr [bp-4],word ptr [bp-6],word ptr [bp-8],word ptr [bp-10],word ptr [bp-12],word ptr [bp-14],word ptr [bp-16],word ptr [bp-18]
	mov sp,bp

nocr4:
	fnstsw ax
	fnstcw [wSize]
	invoke printf, CStr("FCW: %X  FSW: %X",lf), [wSize], ax

	mov eax, dr0
	mov ebx, dr1
	mov ecx, dr2
	mov edx, dr3
	invoke printf, CStr("DR0-DR3: %lX %lX %lX %lX",lf), eax, ebx, ecx, edx
	mov eax, dr6
	mov ecx, dr7
	invoke printf, CStr("DR6: %lX  DR7: %lX",lf), eax, ecx
	pushfd
	pop eax
	invoke printf, CStr("EFL: %lX, ESP: %lX",lf), eax, esp

	.if !(byte ptr _msw & 1)
		call DispSegLimits
	.endif

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
