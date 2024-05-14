
;--- input/output COMx
;--- very simple implementation.
;--- ds/es=flat, cs=flat, ss=unknown

_XONXOFF_	= 1
XON 		= 11h
XOFF		= 13h
EOT 		= 03H

	.data

wComNo  dw -1	; 0=COM1, 1=COM2, ...
wCsrPos dw 0

	.code


;--- display a char in AL

AuxPutChar proc

	pushad
	movzx ebx, [wComNo]
	mov bx, [ebx*2+400h]
	lea dx, [bx+5]		;LSR - Line Status Register
	mov cx, -1
	xchg al, ah
@@:
	in al, dx
	test al, 40h		;TEMT - transmitter empty?
	loopzw @B
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

AuxGetCsrPos proc
	mov dx, [wCsrPos]
	ret
AuxGetCsrPos endp

;--- get a char in AL

AuxGetChar proc

	push ebx
	push ecx
	push edx

	movzx ebx, [wComNo]
	mov bx, [ebx*2+400h]
	lea dx, [bx+6]		;MSR - modem status register
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
	xor ax, ax
exit:
	pop edx
	pop ecx
	pop ebx
	ret
AuxGetChar endp

