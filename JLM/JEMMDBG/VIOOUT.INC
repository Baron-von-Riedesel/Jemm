
;--- protected-mode code for vio output

cr equ 13
lf equ 10
bs equ 8	; backspace

@getcursorpos macro
	movzx ebx, byte ptr cs:[462h];page
	mov bx, cs:[EBX*2+450h]
endm

@setcursorpos macro
	movzx ebx, byte ptr cs:[462h];page
	mov ss:[EBX*2+450h], ax
endm

;--- print a char
;--- no registers modified

VioPutChar proc

local	wCols:word
local	bChar:byte
local	bRows:byte

	pushad

	mov bChar, al
	mov ch, cs:[0484h]			; rows-1
	mov cl, cs:[044Ah]			; cols
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
	mov si, cs:[044Eh]			; page offset
	cmp word ptr cs:[0463H],3B4h
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
	mov ss:[ebx+esi], al
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
;	call slowdown
	popad
	ret

if 0
slowdown:
	mov cx, 200
@@:
	in al, 61h
	and al, 10h
	cmp al, ah
	mov ah, al
	jz @B
	loopw @B
	retn
endif

cursorset:
	add ax, cs:[044EH]	;offset page
	mov dx, cs:[0463H]
	shr ax, 1			;the CRT offset is one plane only, no attribute bytes 
	mov cl, al			;first high byte
	mov al, 0eh
	out dx, ax
	mov ah, cl			;then low byte
	mov al, 0fh
	out dx, ax
	retn

scrollup:			;scroll up one line
	push es
	push ss
	pop es
	mov edi, esi
	push edi
	movzx esi, wCols
	lea esi, [esi*2+edi]
	mov cl, byte ptr wCols
	mov al, bRows
	mul cl
	movzx ecx, ax
	shr ecx,1
	rep movsd
	push edi
	movzx ecx, wCols
	mov eax,07200720h
	shr ecx, 1
	rep stosd
	pop eax
	pop edi
	sub eax, edi
	pop es
	retn

VioPutChar endp

VioGetCsrPos proc uses ebx
	@getcursorpos
	mov dx, bx
	ret
VioGetCsrPos endp

