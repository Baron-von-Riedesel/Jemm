
;*** implements debug displays
;--- written by japheth
;--- public domain
;--- to be assembled with JWasm or Masm v6.1+

	.486P
	.model FLAT
	option proc:private
	option dotname

	include jemm.inc		;common declarations
	include jemm32.inc		;declarations for Jemm32
	include debug.inc

if ?BUFFERED
?BUFFSTA	equ 4F8h;physical start address buffer
?BUFFOFS	equ 4FCh;offset in buffer
?BUFFSIZ	equ 100000h
endif

;--- publics/externals

	include external.inc

;--- macros

;	assume SS:FLAT,DS:FLAT,ES:FLAT

if ?DBGOUT

if ?BUFFERED
.text$01 segment
DbgPTE	dd 0
.text$01 ends
endif

.text$03 segment

;--- make no assumptions about DS and ES here!
;--- also don't push/pop segment registers!

VPUTCHR PROC public
	PUSHAD
if ?BUFFERED
	test byte ptr ss:[417h],10h  ;scroll lock on?
	jz @@done
	mov edi,ss:[?BUFFSTA]
	and edi,edi
	jz @@done
	mov ecx,ss:[?BUFFOFS]
	lea edx,[edi+ecx]
	and dx,0F000h
	or dl, PTF_PRESENT or PTF_RW or PTF_USER
	mov ebx,[DbgPTE]
	mov ss:[ebx], edx
	mov esi,cr3
	mov cr3,esi

	@SYSPTE2LINEAR edi, ebx

	movzx ebx,cx
	and bh,0Fh
	mov ss:[edi+ebx],al
	inc ecx
	and ecx,?BUFFSIZ-1
	mov ss:[?BUFFOFS],ecx
@@done:
else
if ?USEMONO
	mov edi,0B0000h
	mov ebx,7
else
	MOV EDI,0B8000h
	CMP BYTE ptr SS:[463h],0B4h
	JNZ @@IS_COLOR
	XOR DI,DI
@@IS_COLOR:
	movzx EBX, WORD PTR SS:[44Eh]
	ADD EDI, EBX
	MOVZX EBX, BYTE PTR SS:[462h]
endif
	mov esi, edi
	MOVZX ECX, BYTE PTR SS:[EBX*2+450h+1] ;ROW
if ?USEMONO
	MOV EAX, 80
else
	MOVZX EAX, WORD PTR SS:[44Ah]
endif
	MUL ECX
	MOVZX EDX, BYTE PTR SS:[EBX*2+450h]   ;COL
	ADD EAX, EDX
	MOV DH,CL
	LEA EDI, [EDI+EAX*2]
	MOV AL, [ESP+1Ch]
	CMP AL, 10
	JZ @@NEWLINE
	MOV SS:[EDI], AL
	MOV byte ptr SS:[EDI+1], 07
	INC DL
if ?USEMONO
	cmp dl,80
else
	CMP DL, BYTE PTR SS:[44Ah]
endif
	JB @@OLDLINE
@@NEWLINE:
	MOV DL, 00
	INC DH
if ?USEMONO
	CMP DH, 24
else
	CMP DH, BYTE PTR SS:[484h]
endif
	JBE @@OLDLINE
	DEC DH
	CALL @@SCROLL_SCREEN
@@OLDLINE:
	MOV SS:[EBX*2+450h],DX
endif
	POPAD
	RET

ife ?BUFFERED

;--- scroll screen up 1 line
;--- esi -> start screen

@@SCROLL_SCREEN:
	CLD
	mov edi,esi
if ?USEMONO
	mov eax,80
else
	movzx eax,word ptr ss:[44Ah]
endif
	push eax
	lea esi, [esi+2*eax]
if ?USEMONO
	mov CL, 24
else
	MOV CL, SS:[484h]
endif
	mul cl
	mov ecx,eax
@@nextcell:
	lodsw cs:[esi]
	mov ss:[edi],ax
	add edi,2
	loop @@nextcell
	pop ecx
	mov ax,0720h
@@nextcell2:
	mov ss:[edi],ax
	add edi,2
	loop @@nextcell2
	retn

endif

VPUTCHR ENDP

;--- print a string which is hard-coded behind the call to this function

ifdef _DEBUG
	include dprintf.inc
endif

if 0

;--- 386SWAT isn't compatible with Jemm, because this debugger
;--- expects that extended memory is mapped into linear address space,
;--- at least those parts of XMS memory that 386SWAT uses for itself.
;--- Jemm simply doesn't do that; it maps the memory that it needs and
;--- nothing else.

;--- check if int 3 vector still points to
;--- the monitor code segment. If no, assume 386SWAT has intruded

DebugBreak proc public
	cmp word ptr cs:[offset V86GDT+3*8+4],FLAT_CODE_SEL
	jz @@noswat
	pushfd
	or byte ptr [esp+1],1  ;set TF
	popfd
@@noswat:
	ret
DebugBreak endp

endif

.text$03 ends

.text$04 segment

;--- init debug
;--- ESI -> Jemminit

Debug_Init proc public

if ?BUFFERED
	cmp [bNoPool],0
	jz @@ok
@@error:
;--- severe error. disable debug output
	mov byte ptr ds:[VPUTCHR],0C9h
	ret
@@ok:
	mov edx, [XMS_Handle_Table.xht_pArray]
 if 1;e ?INTEGRATED
	movzx ecx, [XMS_Handle_Table.xht_numhandles]
	movzx eax, [XMS_Handle_Table.xht_sizeof]
@@nextitem:
	test [edx].XMS_HANDLE.xh_flags, XMSF_FREE
	jz @@skipitem
  if 1;?XMS35
	test word ptr [edx].XMS_HANDLE.xh_baseK+2, 0FFC0h
	jnz @@skipitem
  endif
	cmp [edx].XMS_HANDLE.xh_sizeK, ?BUFFSIZ / 1024
	jnc  @@founditem
@@skipitem:
	add edx,eax
	loop @@nextitem
	jmp @@error
@@founditem:
	jz @@splitdone
	push ebx
	mov ebx, edx
@@nextitem2:
	test [ebx].XMS_HANDLE.xh_flags, XMSF_INPOOL
	jnz @@founditem2
	add ebx,eax
	loop @@nextitem2
	pop ebx
	jmp @@error
@@founditem2:
	mov [ebx].XMS_HANDLE.xh_flags, XMSF_FREE
	mov eax, [edx].XMS_HANDLE.xh_baseK
	add eax, ?BUFFSIZ / 1024
	mov [ebx].XMS_HANDLE.xh_baseK, eax
	mov eax, [edx].XMS_HANDLE.xh_sizeK
	sub eax, ?BUFFSIZ / 1024
	mov [ebx].XMS_HANDLE.xh_sizeK, eax
	pop ebx
@@splitdone:
	mov [edx].XMS_HANDLE.xh_flags, XMSF_USED
	mov [edx].XMS_HANDLE.xh_locks, 1
	mov [edx].XMS_HANDLE.xh_sizeK, ?BUFFSIZ / 1024
	mov eax, [edx].XMS_HANDLE.xh_baseK
 else
	mov eax, ?BUFFSIZ / 1024
	cmp [edx+sizeof XMS_HANDLE].XMS_HANDLE.xh_sizeK, eax
	jc @@error
	sub [edx+sizeof XMS_HANDLE].XMS_HANDLE.xh_sizeK, eax
	add [edx].XMS_HANDLE.xh_sizeK, eax
	mov eax, [edx+sizeof XMS_HANDLE].XMS_HANDLE.xh_baseK
	add [edx+sizeof XMS_HANDLE].XMS_HANDLE.xh_baseK, ?BUFFSIZ / 1024
 endif

;--- now in EAX physical address of debug output buffer.
;--- we need a 4 kB page of linear address space to map
;--- the physical memory

	shl eax, 10
	mov ds:[?BUFFSTA],eax

	mov edx,[PageMapHeap]
	mov [DbgPTE], edx

	mov ecx,?BUFFSIZ / 4096
	or al, PTF_PRESENT or PTF_RW or PTF_USER
@@nextitem3:
	mov [edx],eax
	pushad
	mov eax,cr3
	mov cr3,eax
	@SYSPTE2LINEAR edi, edx
	mov ecx, 4096/4
	xor eax, eax
	rep stosd
	popad
	add eax,4096
	loop @@nextitem3

	add edx,4
	mov [PageMapHeap], edx

	xor eax, eax
	mov ds:[?BUFFOFS],eax
endif ;?BUFFERED
	ret
Debug_Init endp

.text$04 ends

endif

	END
