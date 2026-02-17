
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

SLOWDOWN equ 256            ;to slow down debug displays

;--- publics/externals

	include external.inc

if ?DBGOUT

.text$03 segment

;--- make no assumptions about DS and ES here!
;--- also don't push/pop segment registers!

VPUTCHR PROC public
	PUSHAD
if ?KD
	cmp cs:[bKD],0	; kernel debugger detected?
	jz @F
	mov edx, eax	; then redirect output to it
	xor eax, eax
	int 41h
	popad
	ret
@@:
endif
if ?AUXIO
	call AuxPutChar
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

ife ?AUXIO

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
 if SLOWDOWN
	mov ecx,SLOWDOWN
@@:
	in al,61h
	cmp al,ah
	jz @B
	mov ah,al
	loop @B
 endif
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
	ret
Debug_Init endp

.text$04 ends

endif

	END
