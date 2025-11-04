
;--- JLoad's PE file loader
;--- this code is copied to linear address ?SYSTEMADDR when
;--- JLoad is running for the first time.
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
	include winnt.inc
	include debug.inc

	.data

;--- variables

g_dwIDT		dd 0	;linear address IDT

if ?USEVCPIEXIT
vcpi		label fword
vcpiofs		dd 0
vcpisel 	dd 0
endif

	.code

;--- entry from real-mode - must be at offset 0.
;--- This is a true VCPI entry, meaning SS:ESP still on host stack.
;--- CS,DS,ES=Flat (v5.86: CS is correct, but DS/ES was just an assumption)
;--- ecx->VMMS structure
;--- edi=phys page for protected-mode stack
;--- ebp=vcpi entry (if ?USEVCPIEXIT is 1)
;--- out: EDX=returncode from JLM

start proc stdcall public

;--- v5.86: don't assume DS/ES are flat. It's true for Jemm, but
;--- another program may have hooked into int 67h, ax=DE0Ch!
	mov eax, cs
	add eax, 8
	mov ds, eax
	mov es, eax

	or edi, PTF_PRESENT or PTF_RW or PTF_USER

;--- set the 4kB stack allocated in 16-bit init code
;--- to be fixed: don't modify PTEs of the F8000000-F83FFFFF region, it's
;--- reserved for Jemm!

	xchg edi,ds:[?PAGEDIR+?PAGETABSYS+0FFCh]  ;set the stack PTE ( =F83FF000h )

;--- init stack. It's flat; since Jemm's ?SYSBASE is 0F8000000h, the
;--- stack is F8400000h.

	mov ss, eax
	mov esp, ?SYSBASE + 400000h

if ?USEVCPIEXIT
	mov [vcpiofs],ebp
	mov [vcpisel],cs
endif

	push edi			;save old PTE for stack
	cmp word ptr [dfOldint20+4],0	;already initialized?
	jnz @F
	call InitVMM
	jc @@exit
@@:
	call Get_Cur_VM_Handle
	mov ebp,[ebx].cb_s.CB_Client_Pointer

	.if ([ecx].VMMS.wFlags & JLF_UNLOAD)
		call SearchJLM
		jc @@error
		mov ebx, [eax].VxD_Desc_Block.DDB_Reserved1
	.else
		call LoadJLM
		jc @@error
		mov esi,[ebx+3Ch]
		add esi, ebx	;point to NT header
		call DoFixups
		jc @@error
		call FreeDiscardableSections
		call SetDDB
	.endif

;--- call the modules entry point

	mov esi,[ebx].IMAGE_DOS_HEADER.e_lfanew
	add esi, ebx	;point to NT header

	mov edi, ebx
	mov eax, [esi].IMAGE_NT_HEADERS.OptionalHeader.AddressOfEntryPoint
	add eax, edi
	push edi
	push esi
	test [esi].IMAGE_NT_HEADERS.FileHeader.Characteristics, IMAGE_FILE_DLL
	jz isapp
	test [ecx].VMMS.wFlags, JLF_UNLOAD
	jz @@isload
	push ecx
	push DLL_PROCESS_DETACH
	push edi
	call eax
	pop esi
	pop edi
	and ax, ax		; check AX only!
	jz @@exit
	jmp @@unload
@@isload:
	push ecx
	push DLL_PROCESS_ATTACH
	push edi
isapp:
	call eax
	pop esi
	pop edi
	and ax, ax		; check AX only!
	jz @@unload
	test [esi].IMAGE_NT_HEADERS.FileHeader.Characteristics, IMAGE_FILE_DLL
	jnz @@exit
@@unload:
	call UnloadJLM
	jmp @@exit
@@error:
	xor eax,eax
@@exit:
	@dprintf ?INITDBG, <"start exit (returns to v86)",10>
	mov edx, eax	;save returncode in edx
	pop eax

	lea esp, [ebp].Client_Reg_Struc.Client_EIP
	mov ds:[?PAGEDIR+?PAGETABSYS+0FFCh], eax	;restore stack PTE

	mov eax, cr3	;flush TLB to validate the just restored stack PTE
	mov cr3, eax

if ?USEVCPIEXIT
	mov ax,0DE0Ch
	call [vcpi]
else
	iretd
endif
	align 4
start endp

;--- ecx=VMMS
;--- ebx=module handle

SetDDB proc
	pushad
	movzx esi, [ecx].VMMS.pDDB
	and esi, esi
	jz exit
	@dprintf ?PEDBG, <"SetDDB: calling VMM_Add_DDB",10>
	mov eax, [ebx+3Ch]
	add eax, ebx
	mov eax,[eax].IMAGE_NT_HEADERS.OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXPORT*sizeof IMAGE_DATA_DIRECTORY].VirtualAddress
	add eax, ebx
	mov eax,[eax].IMAGE_EXPORT_DIRECTORY.AddressOfFunctions
	add eax, ebx
	mov esi, [eax]
	add esi, ebx
	mov [esi].VxD_Desc_Block.DDB_Reserved1, ebx	;store module in DDB
	call VMM_Add_DDB
exit:
	mov [ebx+38h],esi	;store DDB in module
	popad
	ret
	align 4
SetDDB endp

;--- search a JLM
;--- ECX=VMMS
;--- to find a JLM, it must have an associated DDB with an ID or a name
;--- out: NC: EAX=module handle
;---       C: eax=return code
;--- if NC, ECX is preserved

SearchJLM proc

	movzx edi, [ecx].VMMS.pDDB
	and edi, edi
	jz error
	movzx eax, word ptr [ebp].Client_Reg_Struc.Client_DS
	shl eax, 4
	add edi, eax
	movzx eax,[edi].VxD_Desc_Block.DDB_Req_Device_Number
	push ecx
	push edi
	lea edi, [edi].VxD_Desc_Block.DDB_Name
	call FindDevice
	pop edi
	pop ecx
	jc error2
	@dprintf ?PEDBG, <"SearchJLM: device found",10>
	ret
error2:
	@dprintf ?PEDBG, <"SearchJLM: device not found",10>
	jmp @F
error:
	@dprintf ?PEDBG, <"SearchJLM: no DDB",10>
@@:
	mov cx,2      ;not found
	stc
	ret
	align 4

SearchJLM endp

;--- load a JLM
;--- 1. find an address space in system region
;--- 2. commit the pages
;--- 3. read the file with nested execution
;---    fixups aren't resolved yet!
;--- inp: ECX -> VMMS, EBP -> client regs
;--- out: NC if ok
;---    EBX=module handle
;---    ESI=DDB

LoadJLM proc
	@dprintf ?PEDBG, <"LoadJLM enter, ecx=%X, calling SearchJLM",10>, ecx
	pushad
	call SearchJLM	;already loaded?
	jnc error3
	mov ecx,[esp].PUSHADS.rECX ;restore ecx
	movzx edi, [ecx].VMMS.pHdr
	movzx eax, word ptr [ebp].Client_Reg_Struc.Client_DS
	shl eax, 4
	add edi, eax
	mov ax, [ecx].VMMS.hFile
	mov word ptr [ebp].Client_Reg_Struc.Client_EBX, ax
	mov bx, [ecx].VMMS.pBuffer
	mov esi, [edi].IMAGE_NT_HEADERS.OptionalHeader.SizeOfImage
	shr esi, 12
	push 0
	push esi
	push PR_SYSTEM
	call _PageReserve
	add esp,3*4
	cmp eax,-1
	jz error
	mov [esp].PUSHADS.rEBX, eax   ;linear address
	shr eax, 12
	push PC_FIXED or PC_WRITEABLE
	push 0
	push PD_ZEROINIT
	push esi
	push eax
	call _PageCommit
	add esp,5*4
	and eax, eax
	jz error
	mov esi,[edi].IMAGE_NT_HEADERS.OptionalHeader.SizeOfHeaders
	.if (esi > 1000h)
		mov esi, 1000h
	.endif
	xor eax, eax
	mov edi, [esp].PUSHADS.rEBX
	call ReadFile
	jc error2a
	add edi, [edi+3Ch]
	movzx ecx, [edi].IMAGE_NT_HEADERS.FileHeader.NumberOfSections
	add edi, sizeof IMAGE_NT_HEADERS
	.while (ecx)
		push ecx
		push edi
		mov ecx, [edi].IMAGE_SECTION_HEADER.SizeOfRawData
		mov eax, [edi].IMAGE_SECTION_HEADER.PointerToRawData
		mov edi, [edi].IMAGE_SECTION_HEADER.VirtualAddress
		add edi, [esp+2*4].PUSHADS.rEBX
		.while (ecx)
			mov esi, ecx
			.if (esi > 1000h)
				mov esi, 1000h
			.endif
			push ecx
			push eax
			call ReadFile
			jc error2
			pop eax
			pop ecx
			add eax, esi
			add edi, esi
			sub ecx, esi
		.endw
		pop edi
		pop ecx
		add edi, sizeof IMAGE_SECTION_HEADER
		dec ecx
	.endw
	popad
	ret
error3:
	@dprintf ?PEDBG, <"LoadJLM: JLM already loaded",10>
	stc
	popad
	mov cx,0B7h	;already exists
	ret
error2:
	add esp,4*4
error2a:
	@dprintf ?PEDBG, <"LoadJLM: ReadFile error2",10>
error:
	stc
	popad
	mov cx,8	;memory error
	ret
	align 4
LoadJLM endp

;--- unload the JLM's memory block
;--- inp: EDI=linear address

UnloadJLM proc
	pushad
	@dprintf ?PEDBG, <"UnloadJLM enter",10>
	mov edi,[edi+38h]	; address DDB stored in header
	and edi,edi
	jz @F
	@dprintf ?PEDBG, <"UnloadJLM: calling VMM_Remove_DDB",10>
	call VMM_Remove_DDB
@@:
	mov edi,[esp].PUSHADS.rEDI
	push 0     ;flags
	push edi
	call _PageFree
	add esp, 2*4
	popad
	ret
	align 4
UnloadJLM endp

;--- read a file portion (4kB)
;--- eax = file pos
;--- si = bytes to read
;--- bx = buffer offset
;--- edi = target addr
;--- Client_BX = file handle
;--- Client_DS = buffer segment

ReadFile proc

	mov word ptr [ebp].Client_Reg_Struc.Client_EDX, ax
	shr eax, 16
	mov word ptr [ebp].Client_Reg_Struc.Client_ECX, ax
	mov word ptr [ebp].Client_Reg_Struc.Client_EAX, 4200h
	call Begin_Nest_Exec
	mov eax, 21h
	call Exec_Int
	test [ebp].Client_Reg_Struc.Client_EFlags,1
	.if (ZERO?)
		mov word ptr [ebp].Client_Reg_Struc.Client_ECX, si
		mov word ptr [ebp].Client_Reg_Struc.Client_EDX, bx
		mov byte ptr [ebp].Client_Reg_Struc.Client_EAX+1, 3Fh
		mov eax, 21h
		call Exec_Int
		test [ebp].Client_Reg_Struc.Client_EFlags,1
		.if (ZERO?)
			movzx ecx, si
			push esi
			movzx esi, word ptr [ebp].Client_Reg_Struc.Client_DS
			shl esi, 4
			movzx ebx, bx
			add esi, ebx
			shr ecx, 2
			push edi
			rep movsd
			pop edi
			pop esi
		.endif
	.endif
	call End_Nest_Exec
	mov ah,byte ptr [ebp].Client_Reg_Struc.Client_EFlags
	sahf
	ret
	align 4
ReadFile endp

;--- walk relocations for PE binary loaded at linear address EBX
;--- inp: EBX = module handle, ESI=IMAGE_NT_HEADERS

DoFixups proc 

	@dprintf ?INITDBG, <"DoFixups enter",10>
	pushad
	mov edx,ebx
	mov ebx,[esi].IMAGE_NT_HEADERS.OptionalHeader.ImageBase

	mov ebp, [esi].IMAGE_NT_HEADERS.OptionalHeader.SizeOfImage
	mov ecx, [esi].IMAGE_NT_HEADERS.OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_BASERELOC*sizeof IMAGE_DATA_DIRECTORY].Size_
	jecxz done
	mov esi, [esi].IMAGE_NT_HEADERS.OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_BASERELOC*sizeof IMAGE_DATA_DIRECTORY].VirtualAddress
	add esi,edx
nextblock:

	mov edi, [esi].IMAGE_BASE_RELOCATION.VirtualAddress
	cmp edi, ebp
	jnc done			;invalid relocations found!!!

	push ecx
	push esi
	push edx
	push ebx

	add edi, edx
	sub edx, ebx
	mov ecx, [esi].IMAGE_BASE_RELOCATION.SizeOfBlock
	add ecx, esi
	add esi, sizeof IMAGE_BASE_RELOCATION
	xor eax, eax
	.while (esi < ecx)
		lods word ptr [esi]
		mov bl,ah
		and ah,0Fh
		shr bl,4
		.if (bl == IMAGE_REL_BASED_HIGHLOW)
			add [edi+eax],edx
		.endif
	.endw
	pop ebx
	pop edx
	pop esi
	pop ecx
	mov eax,[esi].IMAGE_BASE_RELOCATION.SizeOfBlock
	add esi, eax
	sub ecx, eax
	ja nextblock
done:
	popad
	@dprintf ?INITDBG, <"DoFixups exit",10>
	clc
	ret
	align 4
DoFixups endp

;--- free all objects marked as discardable
;--- inp: ESI -> IMAGE_NT_HEADERS
;--- inp: EBX = module base

FreeDiscardableSections proc 

	@dprintf ?INITDBG, <"FreeDiscardableSections enter",10>
	pushad
	movzx ecx,[esi].IMAGE_NT_HEADERS.FileHeader.NumberOfSections
	lea edi,[esi+size IMAGE_NT_HEADERS]
	jecxz @@done
@@nextitem:
	test [edi].IMAGE_SECTION_HEADER.Characteristics, IMAGE_SCN_MEM_DISCARDABLE
	jz @@skipitem
	mov eax, [edi].IMAGE_SECTION_HEADER.VirtualAddress
	mov edx, [edi].IMAGE_SECTION_HEADER.Misc.VirtualSize
	add edx, 1000h-1
	shr edx, 12
	jz @@skipitem
	.if (eax)
		push ecx

		add eax, ebx
		shr eax, 12
		push 0
		push edx
		push eax
		call _PageDecommit
		add esp,3*4

		pop ecx
	.endif
@@skipitem:
	add edi, size IMAGE_SECTION_HEADER
	loop @@nextitem
@@done:
	popad
	@dprintf ?INITDBG, <"FreeDiscardableSections exit",10>
	clc
	ret
	align 4
FreeDiscardableSections endp

;--- get address of 4k DOS buffer (during load only)
;--- ecx=JLCOMM ptr

GetDOSBuffer proc public
	movzx eax,[ecx].VMMS.pBuffer
	movzx edx,word ptr [ebp].Client_Reg_Struc.Client_DS
	shl edx,4
	add eax,edx
	ret
GetDOSBuffer endp

if ?TRACE

	include vioout.inc 
	include dprintf.inc 

endif

	end start


