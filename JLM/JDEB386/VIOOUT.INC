
;--- protected-mode code for vio output
;--- ds=es=flat, cs=flat, ss=unknown

cr equ 13
lf equ 10
bs equ 8	; backspace
PAUSEKEY equ 1

@getcursorpos macro
	movzx ebx, byte ptr ds:[462h];page
	mov bx, ds:[EBX*2+450h]
endm

@setcursorpos macro
	movzx ebx, byte ptr ds:[462h];page
	mov ds:[EBX*2+450h], ax
endm

;--- print a char
;--- no registers modified

VioPutChar proc

wCols textequ <di>
bChar textequ <dh>
bRows textequ <dl>

	pushad

	mov bChar, al
	mov ch, ds:[0484h]			; rows-1
	mov cl, ds:[044Ah]			; cols
	mov bRows, ch
	@getcursorpos				; bh=row, bl=col
	mov al, bh		;row pos
	mov ch, 0
	mov wCols, cx
	mul cl
	add ax, ax
	mov bh, 00  ; bx=col pos
	add bx, bx
	add bx, ax
	mov si, ds:[044Eh]			; page offset
	cmp word ptr ds:[0463H],3B4h
	jz @F
	add si, 8000h
@@:
	movzx esi, si
	add esi, 0B0000h

	mov al, bChar

	cmp al, cr
	jnz @F
	mov ax, bx
	shr ax, 1
	div cl
	mov al, ah
	xor ah, ah
	add ax, ax
	sub bx, ax
	jmp char_done
@@:
	cmp al, lf
	jnz @F
	add bx, cx
	add bx, cx
	jmp char_done
@@:
	cmp al, bs
	jnz @F
	sub bx, 2
	jmp char_done
@@:
	movzx ebx, bx
	mov ds:[ebx+esi], al
	inc ebx
	inc ebx
char_done:
	mov al, bRows
	inc al
	mul cl
	add ax, ax
	cmp bx, ax
	jc @F
	call scrollup
	mov ebx, eax
@@:
	mov eax, ebx
	push eax
	mov cx, wCols
	shr eax, 1
	div cl
	xchg al, ah
	@setcursorpos
	pop eax
	call cursorset
if PAUSEKEY
	call checkpause
endif
	popad
	ret

cursorset:
	add ax, ds:[044EH]	;offset page
	mov dx, ds:[0463H]
	shr ax, 1			;the CRT offset is one plane only, no attribute bytes 
	mov cl, al			;first high byte
	mov al, 0eh
	out dx, ax
	mov ah, cl			;then low byte
	mov al, 0fh
	out dx, ax
	retn

scrollup:			;scroll up one line
	cld
	movzx ecx, wCols
	mov edi, esi
	push edi
	movzx esi, cx
	lea esi, [esi*2+edi]
	mov al, bRows
	mul cl
	push ecx
	movzx ecx, ax
	shr ecx,1
	rep movsd
	pop ecx
	push edi
	mov eax,07200720h
	push ecx
	shr ecx, 1
	rep stosd
	pop ecx
	pop eax
	pop edi
	sub eax, edi
	mov edi, ecx		; restore "wCols"
	retn

wCols textequ <>
bChar textequ <>
bRows textequ <>

VioPutChar endp

if PAUSEKEY
checkpause proc
	in al,64h		;key from keyboard arrived?
	test al,1
	jz no
	in al,60h
	cmp al,45h		;PAUSE key?
	jnz no
@@:
	in al,64h
	test al,1
	jz @B
	in al,60h
	test al,80h
	jnz @B
no:
	ret
checkpause endp
endif


VioGetCsrPos proc uses ebx
	@getcursorpos
	mov dx, bx
	ret
VioGetCsrPos endp

