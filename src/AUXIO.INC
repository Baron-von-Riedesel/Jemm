
;--- handle AUX I/O

ifndef COMNO
COMNO       equ 1
endif
_XONXOFF_   equ 1
XON         equ 11h
XOFF        equ 13h

.text$01w segment dword flat public 'CODE'
wCsrPos dw 0,0
.text$01w ends

;--- display a char in AL

AuxPutChar proc

	pushad
	movzx ebx, word ptr ds:[400h + (COMNO-1)*2]
	lea edx, [ebx+5]	;LSR - Line Status Register
	mov cx, -1
	movzx ecx, cx
	xchg al, ah
@@:
	in al, dx
	test al, 40h		;TEMT - transmitter empty?
	loopz @B
if _XONXOFF_
	test al, 1			;char received
	jz noxoff
	mov edx, ebx
	in al, dx
	cmp al, XOFF
	jnz noxoff
waitxon:
	add edx, 5
@@: 					;wait till new char arrived
	in al, dx
	test al, 1
	jz @B
	mov edx, ebx
	in al, dx
	cmp al, XON			;wait till XON received
	jnz waitxon
noxoff:
endif
	xchg al, ah
	mov edx, ebx
	out dx, al
	call setcsrpos
	popad
	ret

setcsrpos:
	cmp al, 13
	jz col00
	cmp al, 10
	jz nochg
	cmp al, 8
	jz back
	inc byte ptr [wCsrPos]
	retn
back:
	dec byte ptr [wCsrPos]
	retn
col00:
	mov byte ptr [wCsrPos], 0
nochg:
	retn

AuxPutChar endp

;--- get a char in AL

AuxGetChar proc

	push ebx
	push ecx
	push edx

	movzx ebx, word ptr ds:[400h + (COMNO-1)*2]
	lea edx, [ebx+6]	;MSR - modem status register
	in al, dx			;DSR - modem(=DCE) ready?
	and al, 20h
	jz error
	dec edx				;LSR - Line Status Register
@@:
	in al, dx
	test al, 01h		;DR - Data ready?
	jz @B
	mov edx, ebx
	in al, dx
	mov ah, 00
	jmp exit
error:
	xor eax, eax
exit:
	pop edx
	pop ecx
	pop ebx
	ret
AuxGetChar endp

