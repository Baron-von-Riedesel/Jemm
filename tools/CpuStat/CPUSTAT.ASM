
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

dwCPUIDedx dd 0
dwCPUIDecx dd 0

tradr	dw 0
ldt 	dw 0

modflg	dw 0
wSize	dw 0
bGDT	db 0
bIDT	db 0
bCpu	db 0

;--- gdt for In15 ah=87 move

gdt label byte
		dq 0
		dq 0
		dw -1
wSrc0	dw 0
bSrc1	db 0
		db 0F3h
		db 0
bSrc2	db 0
		dw -1
wDst0	dw 0
bDst1	db 0
		db 0F3h
		db 0
bDst2	db 0
		dq 0
		dq 0

	.data?

buffer	db 800h dup (?) 	   

	.code

	include printf.inc

	.586

getcpuid proc
	pushfd						; save EFlags
	cli
	pushd 240000h				; set AC bit in eflags, reset IF
	popfd						; pop extended flags
	pushfd						; push extended flags
	pop ax
	pop ax						; get HiWord(EFlags) into AX
	popfd						; restore EFlags
	test al,04
	je @F
	inc cl
	test al,20h
	jz @F
	xor eax,eax
	inc eax						; get register 1
	cpuid
	mov [dwCPUIDedx],edx
	mov [dwCPUIDecx],ecx
	mov cl,ah					; cpu
	clc
	ret
@@:
	stc
	ret
getcpuid endp

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
	mov bx,CStr('Real-mode')
	test al,1
	jz @F
	mov bx,CStr('V86-mode')

@@:    
	mov si,CStr('Paging on')
	test eax,80000000h
	jnz @F
	mov si,CStr('Paging off')
@@:
	invoke printf, CStr("MSW: %lX (%s, %s)",lf),_msw, bx, si

	mov eax, 0		;in case the next instr is "emulated"
	mov eax, cr0 	;cr0 (=msw)
	mov [dwCR0],eax
	and ax,1

	cmp ax,modflg
	jz @F
	invoke printf, CStr("'MOV EAX,CR0' emulated incorrectly!",lf)
@@:
	invoke printf, CStr("CR0: %lX",lf),dwCR0

	db 66h
	sgdt gdtr
	invoke printf, CStr("GDTR: %lX,%X",lf),gdta,gdtl
	db 66h
	sidt idtr
	invoke printf, CStr("IDTR: %lX,%X",lf),idta,idtl

	mov eax, -1		;in case the next instr is "emulated"
	mov eax, cr2
	invoke printf, CStr("CR2: %lX",lf),eax

	mov eax, -1		;in case the next instr is "emulated"
	mov eax, cr3
	invoke printf, CStr("CR3: %lX",lf),eax

	invoke getcpuid
	mov [bCpu],cl
	jc nocpuid
	cmp cl,5
	jb no586

	mov eax, -1		;in case the next instr is "emulated"
	mov eax, cr4
	invoke printf, CStr("CR4: %lX",lf),eax
no586:
	invoke printf, CStr("CPUID.01.EDX: %lX",lf), [dwCPUIDedx]
	invoke printf, CStr("CPUID.01.ECX: %lX",lf), [dwCPUIDecx]

nocpuid:
	pushfd
	pop eax
	invoke printf, CStr("EFL: %lX",lf),eax
	cmp [bCpu],5
	jb nofpu
	fnstsw ax
	fnstcw [wSize]
	invoke printf, CStr("FCW: %X  FSW: %X",lf), [wSize], ax
nofpu:

if 0	;not available in real/v86 mode
	str ax
	movzx eax,ax
	sldt bx
	movzx ebx,bx
	invoke printf, CStr("LDT: %lX, TR: %lX",lf),ebx, eax
endif

	test byte ptr [_msw],1	;v86 mode?
	jz @F
	.if (bGDT)
		call DispGDT
	.endif
	.if (bIDT)
		call DispIDT
	.endif
@@:

exit:
	mov al,0
	ret

main endp

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
	mov wSrc0,ax
	shr eax, 16
	mov bSrc1,al
	mov bSrc2,ah
	mov ax, offset buffer
	movzx eax,ax
	mov dx,ds
	movzx edx,dx
	shl edx, 4
	add eax, edx
	mov wDst0,ax
	shr eax, 16
	mov bDst1,al
	mov bDst2,ah
	push ds
	pop es
	mov si, offset gdt
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
exit:
	ret
error:
	invoke printf, CStr(<"Int 15h, ah=87h failed",lf>)
	jmp exit
DispGDT endp

DispIDT proc
	mov cx,idtl 
	inc cx
	mov wSize,cx
	shr cx,1
	mov eax, idta
	mov wSrc0,ax
	shr eax, 16
	mov bSrc1,al
	mov bSrc2,ah
	mov ax, offset buffer
	movzx eax,ax
	mov dx,ds
	movzx edx,dx
	shl edx, 4
	add eax, edx
	mov wDst0,ax
	shr eax, 16
	mov bDst1,al
	mov bDst2,ah
	push ds
	pop es
	mov si, offset gdt
	mov ah,87h
	stc
	int 15h
	jc error
	mov cx, wSize
	shr cx, 3
	jcxz noidt
	mov si, offset buffer
nextitem:
	push cx
	mov ax,[si+6]
	shl eax, 16
	mov ax,[si+0]
	mov bx,[si+2]
	mov dx,[si+4]
	mov di,si
	sub di, offset buffer
	shr di, 3
	invoke printf, CStr(<"IDT[%4X]: %04X:%08lX %04X",lf>), di, bx, eax, dx
@@:
	add si, 8
	pop cx
	loop nextitem
noidt:
exit:
	ret
error:
	invoke printf, CStr(<"Int 15h, ah=87h failed",lf>)
	jmp exit
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
