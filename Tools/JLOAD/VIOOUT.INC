
;--- low-level video access
;--- no assumption about ds,es.
;--- ss is supposed to be flat.

VPUTCHR PROC
	push ds
	pushad
	push ss
	pop ds
 if ?KD
	test bKDdetected,1
	jz @F
	mov dl, al
	xor ax, ax
	int 41h
	jmp exit
@@:
 endif
if ?USEMONO    
	mov edi,0B0000h
	mov ebx,7
else
	MOV EDI,0B8000h
	CMP BYTE ptr DS:[463h],0B4h
	JNZ @@IS_COLOR
	XOR DI,DI
@@IS_COLOR:
	movzx EBX, WORD PTR DS:[44Eh]
	ADD EDI, EBX
	MOVZX EBX, BYTE PTR DS:[462h]
endif
	mov esi, edi
	MOVZX ECX, BYTE PTR DS:[EBX*2+450h+1]	;ROW
if ?USEMONO
	MOV EAX, 80
else
	MOVZX EAX, WORD PTR DS:[44Ah]
endif
	MUL ECX
	MOVZX EDX, BYTE PTR DS:[EBX*2+450h]	;COL
	ADD EAX, EDX
	MOV DH,CL
	LEA EDI, [EDI+EAX*2]
	MOV AL, [ESP+1Ch]
	CMP AL, 10
	JZ @@NEWLINE
	MOV [EDI], AL
	MOV byte ptr [EDI+1], 07
	INC DL
if ?USEMONO
	cmp dl,80
else
	CMP DL, BYTE PTR DS:[44Ah]
endif
	JB @@OLDLINE
@@NEWLINE:
	MOV DL, 00
	INC DH
if ?USEMONO
	CMP DH, 24
else
	CMP DH, BYTE PTR DS:[484h]
endif
	JBE @@OLDLINE
	DEC DH
	CALL SCROLL_SCREEN
@@OLDLINE:
	MOV DS:[EBX*2+450h],DX
exit:
	POPAD
	pop ds
	RET
	align 4

;--- scroll screen up 1 line
;--- esi -> start screen

SCROLL_SCREEN:
	push es
	push ds
	pop es
	CLD
	mov edi,esi
if ?USEMONO
	mov eax,80
else
	movzx eax,word ptr ds:[44Ah]
endif
	push eax
	lea esi, [esi+2*eax]
if ?USEMONO
	mov CL, 24
else
	MOV CL, DS:[484h]
endif
	mul cl
	mov ecx,eax
	rep movsw
	pop ecx
	mov ax,0720h
	rep stosw
	pop es
	retn
	align 4

VPUTCHR ENDP

