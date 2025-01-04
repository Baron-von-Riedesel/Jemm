
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

DESCRIPTOR struct
wLimit		dw ?
wBase0015	dw ?
bBase1623	db ?
bAttrL		db ?
bAttrH		db ?
bBase2431	db ?
DESCRIPTOR ends

TSS struct
       dd ?
dwESP0 dd ?
wSS0   dw ?
       org 64h
wFlags dw ?
wOffs  dw ?  
TSS ends

	.data

dwCR0	dd 0
_msw	dd 0

gdtr	label fword
gdtl	dw 0
gdta	dd 0

idtr	label fword
idtl	dw 0
idta	dd 0

;--- gdt for In15 ah=87 move

gdti15 label DESCRIPTOR
		DESCRIPTOR <0,0,0,0,0,0>
		DESCRIPTOR <0,0,0,0,0,0>
i15src	DESCRIPTOR <-1,0,0,093h,0,0>
i15dst	DESCRIPTOR <-1,0,0,093h,0,0>
		DESCRIPTOR <0,0,0,0,0,0>
		DESCRIPTOR <0,0,0,0,0,0>

modflg	dw 0
brk		dw 0

O_GDT	equ 1
O_IDT	equ 2
O_PD	equ 4
O_TSS	equ 8
O_FPU	equ 16

bOpt	db 0	;cmdline options -g -i -p -t
bVerbose db 0	;for -p: 1=display paging tables

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

getldtr proc
	.586p
	cli
	mov ecx,cr0
	inc cx
	mov cr0,ecx
	jmp @F
@@:
	sldt ax
	str dx
	dec cx
	mov cr0,ecx
	sti
	ret
	.586
getldtr endp

malloc proc stdcall wBytes:word
	mov ax, wBytes
	add ax, [brk]
	jc error
	xchg ax, [brk]
error:
	ret
malloc endp

free proc stdcall pMem:ptr
	mov ax, pMem
	and ax, ax
	jz @F
	mov [brk], ax
@@:
	ret
free endp

;--- copy an extended memory region ( physical address in physad ) into buffer

copymem proc stdcall uses si buffer:ptr, physad:dword, size_:word

	mov eax, physad
;	and ax, 0F000h
	mov i15src.wBase0015,ax
	shr eax, 16
	mov i15src.bBase1623,al
	mov i15src.bBase2431,ah
	mov ax, buffer
	movzx eax, ax
	mov dx, ds
	movzx edx, dx
	shl edx, 4
	add eax, edx
	mov i15dst.wBase0015, ax
	shr eax, 16
	mov i15dst.bBase1623, al
	mov i15dst.bBase2431, ah
	push ds
	pop es
	mov cx, size_
	shr cx, 1
	mov si, offset gdti15	;es:si=gdt to use
	mov ah, 87h
	stc
	int 15h
	ret

copymem endp

;--- translate linear address in linad into physical address (returned in eax)

getphysaddr proc stdcall uses ebx esi di linad:dword
	xor di, di
	mov eax, -1		;in case the next instr is "emulated"
	mov eax, cr3
	cmp eax, -1
	jz error
	cmp eax, 0		;NTVDM?
	jz error
	and ax, 0F000h
	mov esi, eax
	invoke malloc, 1000h
	jc error
	mov di, ax
	invoke copymem, di, esi, 1000h
	jc error
	mov ebx, linad
	shr ebx, 20
	and bx, 0FFCh
	mov eax, dword ptr [bx+di]
	and ax, 0F000h
	invoke copymem, di, eax, 1000h
	jc error
	mov ebx, linad
	shr ebx, 10
	and bx, 0FFCh
	mov eax, dword ptr [bx+di]
	and ax,0f000h
	mov edx, linad
	and dx, 0FFFh
	or ax, dx
	push eax
	invoke free, di
	pop eax
	clc
	ret
error:
	invoke free, di
	stc
	ret
getphysaddr endp

getattr proc stdcall buffer:ptr
	pusha
	mov di, buffer
	test dl, 10h
	jz syssegs
	mov si, CStr("code")
	test dl, 8
	jnz @F
	mov si, CStr("data")
@@:
	call cpy
	jmp done
syssegs:
	and dl, 0Fh
	cmp dl, 2
	jnz @F
	mov si, CStr("LDT ")
	call cpy
	jmp done
@@:
	cmp dl, 5
	jnz @F
	mov si, CStr("task gate ")
	call cpy
	jmp done
@@:
	test dl, 111b
	jnz @F
	mov si, CStr("undef ")
	call cpy
	jmp done
@@:
	mov si, CStr("386 ")
	test dl, 8
	jz @F
	mov si, CStr("386 ")
@@:
	call cpy

	mov si, CStr("tss ")
	test dl, 4
	jz @F
	mov si, CStr("gate ")
@@:
	call cpy

done:
	mov byte ptr [di], 0
	dec di
	cmp byte ptr [di], ' '
	jnz @F
	mov byte ptr [di], 0
@@:
	popa
	ret
cpy:
	lodsb
	stosb
	and al, al
	jnz cpy
	dec di
	retn

getattr endp

;--- the GDT/IDT is read with int 15h, ah=87h
;--- this is not really correct, since this function
;--- is supposed to read from physical addresses, while
;--- the addresses in GDTR/IDTR are linear;
;--- for jemmex, it often works, though, since its
;--- code/data usually are identity-mapped, starting
;--- at 0x110000.

DispGDT proc

local wSize:word
local buffer2[80]:byte

	xor di, di
	invoke getphysaddr, gdta
	jc nogdt
	mov ebx, eax

	mov cx,gdtl 
	inc cx
	mov wSize, cx

	invoke malloc, cx
	jc error
	mov di, ax

	invoke copymem, di, ebx, wSize
	jc error

	mov cx, wSize
	shr cx, 3
	jcxz nogdt
	mov si, di
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
	invoke getattr, addr buffer2
	push si
	sub si, di
	invoke printf, CStr("GDT[%4X]: %08lX:%04X %04X (%s)",lf), si, ebx, cx, dx, addr buffer2
	pop si
@@:
	add si, sizeof DESCRIPTOR
	pop cx
	loop nextitem
	invoke free, di
nogdt:
	ret
error:
	invoke printf, CStr("Int 15h, ah=87h failed",lf)
	invoke free, di
	ret
DispGDT endp

DispIDT proc

local pMem:ptr
local wSize:word

	mov pMem, 0
	invoke getphysaddr, idta
	jc noidt
	mov esi, eax

	mov cx,idtl 
	inc cx
	cmp cx, 8*100h
	jbe @F
	mov cx, 8*100h
@@:
	mov wSize, cx
	invoke malloc, cx
	jc error
	mov pMem, ax
	invoke copymem, pMem, esi, wSize
	jc error

	mov cx, wSize
	shr cx, 3
	jcxz noidt
	mov si, pMem
	xor di, di
nextitem:
	push cx
	mov ax,[si+6]
	shl eax, 16
	mov ax,[si+0]
	mov bx,[si+2]
	mov dx,[si+4]
	invoke printf, CStr("IDT[%4X]: %04X:%08lX %04X",lf), di, bx, eax, dx
@@:
	inc di
	add si, sizeof DESCRIPTOR
	pop cx
	loop nextitem
	invoke free, pMem
noidt:
	ret
error:
	invoke free, pMem
	invoke printf, CStr("Int 15h, ah=87h failed",lf)
	ret
DispIDT endp

;--- get # of PTEs in a page table
;--- eax->physical address pt

getPTEs proc stdcall uses si di ebx pPT:ptr

	mov ebx, eax
	mov di, pPT
	and bx, 0F000h
	invoke copymem, di, ebx, 1000h
	jc exit
	mov si, di
	xor dx, dx
	mov cx, 1024
nextitem:
	lodsd
	test al,1
	jz @F
	inc dx
@@:
	loop nextitem
	mov ax, dx
	clc
exit:
	ret
getPTEs endp

;--- print page table
;--- iPD: index in page directory

printPT proc stdcall uses si pPT:ptr, iPD:word

	mov si, pPT
	mov cx, 1024
nextitem:
	push cx
	test cl, 7
	jnz @F
;--- index page directory specifies address bits 22-31
;--- index page table specifies address bits 12-21
	movzx eax, di
	shl eax, 22
	mov dx, cx
	sub dx, 1024
	neg dx
	movzx edx, dx
	shl edx, 12
	or eax, edx
	invoke printf, CStr(lf,"%8lX: "), eax
@@:
	lodsd
	.if al & 1
		invoke printf, CStr("%8lX "), eax
	.else
		invoke printf, CStr("-------- ")
	.endif
	pop cx
	loop nextitem
	invoke printf, CStr(lf,lf)
	ret
printPT endp

;--- print page directory
;--- if bVerbose==1, call printPT to display PTEs.

printpd proc stdcall uses si di pPD:ptr

local pPT:ptr

	invoke malloc, 1000h
	jc error
	mov pPT, ax

	mov si, pPD
	xor di, di
nextitem:
	lodsd
	test al, 1
	jz skipitem
	test al, 80h  ; perhaps a 4 MB page?
	jz @F
	mov dx, di
	shl edx, 22

;--- 4MB page PTE:
;--- bits 22-31: address 22-31
;--- bits 13-20: address 32-39
;--- bit 21: 0
;--- bit 12: PAT

	mov ecx, eax
	shr ecx, 13
	movzx ecx, cl
	mov ebx, eax
	and ebx, 0ffc00000h
	invoke printf, CStr("%8lX: %08lX (4 MB page: phys=%X%08lX)",lf), edx, eax, cx, ebx
	jmp skipitem
@@:
	push eax
	invoke getPTEs, pPT
	pop ecx
	jc error
	mov dx, di
	shl edx, 22
	invoke printf, CStr("%8lX: %08lX (%4u pages)",lf), edx, ecx, ax
	.if bVerbose
		invoke printpt, pPT, di
	.endif
skipitem:
	inc di
	cmp di, 1024
	jnz nextitem
	invoke free, pPT
error:
	ret
printpd endp

DispPD proc

local pMem:ptr

	mov pMem, 0
	invoke malloc, 1000h
	jc error
	mov pMem, ax
	mov eax, -1		;in case the next instr is "emulated"
	mov eax, cr3
	cmp eax, -1
	jz done
	and eax, eax
	jz done
	and ax, 0F000h
	invoke copymem, pMem, eax, 1000h
	jc error
	invoke printf, CStr(lf,"page directory",lf)
	invoke printf, CStr("-------------------------------",lf)
	invoke printpd, pMem
done:
	invoke free, pMem
	ret
error:
	invoke free, pMem
	invoke printf, CStr("Int 15h, ah=87h failed",lf)
	ret
DispPD endp

;--- display IO permission bitmap

DispIOPB proc stdcall uses si di pBitmap:ptr, size_:word

local wEnd:word
local wItems:word

	mov ecx, 10000h
	movzx eax, size_
	shl eax, 3
	cmp ecx, eax
	jb @F
	mov ecx, eax
@@:
	mov wEnd, cx
	invoke printf, CStr("trapped Ports:",lf)
	mov si, pBitmap
	xor edi, edi
	mov wItems, di
nextport:
	bt [si], edi 
	jnc skipitem
	invoke printf, CStr("%4X "), di
	inc wItems
	cmp wItems, 8
	jnz skipitem
	invoke printf, CStr(lf)
	mov wItems, 0
skipitem:
	inc di
	cmp di, wEnd
	jnz nextport
	cmp wItems, 0
	jz @F
	invoke printf, CStr(lf)
@@:
	ret
DispIOPB endp

;--- display Interrupt redirection bitmap

DispRedir proc stdcall uses si di pBitmap:ptr
	invoke printf, CStr("Interrupt redirection bitmap:",lf)
	mov bx, 0
	mov di, pBitmap
nextbit:
	bt [di], bx
	jnc skipitem
	invoke printf, CStr("%2X "), bx
skipitem:
	inc bx
	cmp bh, 0
	jz nextbit
	invoke printf, CStr(lf)
	ret
DispRedir endp

DispTSS proc stdcall wSel:word, dwBase:dword, wLimit:word

local wSize:word
local dwPhys:dword
local pTSS:ptr
local pIOPB:ptr
local Redir[32]:byte

	mov pTSS, 0
	mov pIOPB, 0
	invoke getphysaddr, dwBase
	mov dwPhys, eax
	invoke printf, CStr("TSS %X: address linear/phys=%lX/%lX, limit=%X",lf), wSel, dwBase, eax, wLimit
	invoke malloc, sizeof TSS
	jc noiopb
	mov pTSS, ax
	invoke copymem, ax, dwPhys, sizeof TSS
	mov bx, pTSS
	invoke printf, CStr("  SS:ESP0=%X:%lX, offset IOPB=%X",lf), [bx].TSS.wSS0, [bx].TSS.dwESP0, [bx].TSS.wOffs
	mov ax, wLimit
	sub ax, [bx].TSS.wOffs
	jbe noiopb
	cmp ax, 8192
	jb @F
	mov ax, 8192
@@:
	mov wSize, ax
	invoke malloc, ax
	jc noiopb
	mov pIOPB, ax
	movzx edx, [bx].TSS.wOffs
	add edx, dwPhys
	invoke copymem, pIOPB, edx, wSize
	jc noiopb
	invoke DispIOPB, pIOPB, wSize
if 1
	mov eax, cr4
	test al, 1
	jz noiopb
	mov bx, pTSS
	movzx edx, [bx].TSS.wOffs
	sub edx, 32
	add edx, dwPhys
	invoke copymem, addr Redir, edx, 32
	jc noiopb
	invoke DispRedir, addr Redir
endif
noiopb:
	invoke free, pIOPB
	invoke free, pTSS
	ret
DispTSS endp

;--- scan GDT and display all TSSes

DispAllTSS proc

local wSize:word
local dwPhys:dword

	xor di, di
	invoke getphysaddr, gdta
	jc error
	mov esi, eax
	mov cx, gdtl 
	inc cx
	mov wSize, cx
	invoke malloc, cx
	jc error
	mov di, ax
	invoke copymem, di, esi, wSize
	jc error
	mov si, di
nextitem:
	cmp [si].DESCRIPTOR.bAttrL, 8Bh
	jnz skipitem
	mov bh, [si].DESCRIPTOR.bBase2431
	mov bl, [si].DESCRIPTOR.bBase1623
	shl ebx, 16
	mov bx, [si].DESCRIPTOR.wBase0015
	mov ax, si
	sub ax, di
	invoke DispTSS, ax, ebx, [si].DESCRIPTOR.wLimit
skipitem:
	add si, sizeof DESCRIPTOR
	mov ax, wSize
	add ax, di
	cmp si, ax
	jb nextitem
error:
	invoke free, di
	ret
DispAllTSS endp

;--- main()

main proc c

local wSize:word

	mov si, 80h
	mov cl, es:[si]
	inc si

	.while cl
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
				or bOpt, O_IDT
			.elseif (al == 'g')
				or bOpt, O_GDT
			.elseif (al == 'p')
				or bOpt, O_PD
			.elseif (al == 't')
				or bOpt, O_TSS
			.elseif (al == 'v')
				or bVerbose, 1
			.elseif (al == 'f')
				or bOpt, O_FPU
			.else
				jmp usage
			.endif
		.else
usage:
			invoke printf, CStr("usage: CPUSTAT [ options ]",lf)
			invoke printf, CStr("    -f: clear FPU status",lf)
			invoke printf, CStr("    -g: display GDT if in V86 mode",lf)
			invoke printf, CStr("    -i: display IDT if in V86 mode",lf)
			invoke printf, CStr("    -p: display PD if in V86 mode",lf)
			invoke printf, CStr("    -t: display TSS+IOPB if in V86 mode",lf)
			invoke printf, CStr("    -v: make -p display paging tables",lf)
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
	db 66h					;MASM doesn't know SMSW EAX
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
	bt eax,31	; PG
	setc dl
	movzx si,dl
	bt eax,18	; AM
	setc dl
	movzx di,dl
	bt eax,16	; WP
	setc cl
	movzx cx,cl
	bt ax,5		; NE   
	setc dl
	movzx dx,dl

	.data
wMP dw 0
wEM dw 0
wTS dw 0
	.code

	bt ax,3		; TS
	setc byte ptr [wTS]
	bt ax,2		; EM
	setc byte ptr [wEM]
	bt ax,1		; MP
	setc byte ptr [wMP]

	mov bx,CStr('Real')
	bt ax,0		; PE
	setc al
	jnc @F
	mov bx,CStr('V86')
@@:    
	movzx ax,al
	invoke printf, CStr("MSW: %lX (PG=%x AM=%x WP=%x NE=%x TS=%u EM=%u MP=%u PE=%x); %s-mode",lf),_msw, si, di, cx, dx, wTS, wEM, wMP, ax, bx 

	db 66h			; probably useless, just lgdt may need operand size prefix
	sgdt gdtr     
	db 66h			; probably useless, just lidt may need operand size prefix
	sidt idtr

	cmp bOpt, 0
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

	invoke printf, CStr("GDTR: %lX,%X, IDTR: %lX,%X",lf),gdta,gdtl,idta,idtl

	test [_msw],1
	jnz @F
	call getldtr
	invoke printf, CStr("LDTR: %X, TR: %X",lf), ax, dx
@@:

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
	push bp
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
	pop bp

nocr4:

;--- might be a good idea to check CR0.MP & CR0.EM bits.
;--- if CR0.MP=1, a fwait opcode will raise an exception 07 if CR0.TS=1
;--- if CR0.EM=1, any fp opcode will raise an exception 07.
;--- MP=bit 1, EM=bit 2, TS=bit 3.

	test [_msw], 4
	jz @F
	invoke printf, CStr("CR0.EM=1, won't run FPU instructions",lf)
	jmp nofpu
@@:
	fnstsw ax
	fnstcw wSize
	invoke printf, CStr("FCW: %X  FSW: %X",lf), wSize, ax
nofpu:

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
	.if (bOpt & O_GDT)
		.if byte ptr [_msw] & 1	;v86 mode?
			call DispGDT
		.else
			invoke printf, CStr("no GDT in real-mode",lf)
		.endif
	.endif
	.if (bOpt & O_IDT)
		.if byte ptr [_msw] & 1	;v86 mode?
			call DispIDT
		.else
			invoke printf, CStr("no IDT in real-mode",lf)
		.endif
	.endif
	.if (bOpt & O_PD)
		.if byte ptr [_msw] & 1	;v86 mode?
			call DispPD
		.else
			invoke printf, CStr("no paging tables in real-mode",lf)
		.endif
	.endif
	.if (bOpt & O_TSS)
		.if byte ptr [_msw] & 1	;v86 mode?
			call DispAllTSS
		.else
			invoke printf, CStr("no TSS in real-mode",lf)
		.endif
	.endif
	.if (bOpt & O_FPU)
		.if byte ptr [_msw] & 20h ; NE bit set?
		.else
			in al, 0A1h		; unmask IRQ 0Dh
			and al, not 20h
			out 0A1h, al
			mov al,0
			out 0F0h, al
		.endif
		fninit
	.endif

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
	mov [brk],sp
	mov cx, es
	sub ax, cx
	mov bx, 1000h	;request a full 64kB dgroup
	add bx, ax
	mov ah, 4Ah
	int 21h
	jc @F
	call main
@@:
	mov ah,4Ch
	int 21h

	END start
