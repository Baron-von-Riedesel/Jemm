
;--- printf for debug displays, 16-bit

;--- itoa(long n, char * s, int base);
;--- convert 32-bit long to string
;--- v5.86: removed eax from uses clause (since AX is used to return string ptr)

ltoa PROC stdcall uses edx edi number:dword, outb:word, base:word

	mov ch,0
	movzx edi, base
	mov eax, number
	cmp di,-10
	jne @F
	mov di,10
	and eax,eax
	jns @F
	neg eax
	mov ch,'-'
@@:
	mov bx,outb
	add bx,10
	mov BYTE PTR ss:[bx],0
	dec bx
@@nextdigit:
	xor edx, edx
	div edi
	add dl,'0'
	cmp dl,'9'
	jbe @F
	add dl,7+20h
@@:
	mov ss:[bx],dl
	dec bx
	and eax, eax
	jne @@nextdigit
	cmp ch,0
	je @F
	mov ss:[bx],ch
	dec bx
@@:
	inc bx
	mov ax,bx
	ret

ltoa ENDP

dprintf proc c public fmt:ptr, args:vararg

local flag:byte
local longarg:byte
local size_:word
local fillchr:word
local szTmp[12]:byte

	pusha
	pushf
	cld
	lea di,args
@@L335:
	mov si,fmt
nextchar:
	lodsb [si]
	or al,al
	je done
	cmp al,'%'
	je formatitem
	call VPUTCHR
	jmp nextchar
done:
	popf
	popa
	ret

formatitem:
	push offset @@L335
	xor dx,dx
	mov [longarg],dl
	mov bl,1
	mov cl,' '
	cmp BYTE PTR [si],'-'
	jne @F
	dec bl
	inc si
@@:
	mov [flag],bl
	cmp BYTE PTR [si],'0'
	jne @F
	mov cl,'0'
	inc si
@@:
	mov [fillchr],cx
	mov bx,dx

	.while ( byte ptr [si] >= '0' && byte ptr [si] <= '9' )
		lodsb
		sub al,'0'
		cbw
		imul cx,bx,10		;ecx = ebx * 10
		add ax,cx
		mov bx,ax
	.endw

	mov [size_],bx
	cmp BYTE PTR [si],'l'
	jne @F
	mov [longarg],1
	inc si
@@:
	lodsb
	mov [fmt],si
	cmp al,'x'
	je handle_x
	cmp al,'X'
	je handle_x
	cmp al,'d'
	je handle_d
	cmp al,'u'
	je handle_u
	cmp al,'s'
	je handle_s
	cmp al,'c'
	je handle_c
	and al,al
	jnz @F
	pop ax
	jmp done
handle_c:
	mov ax,ss:[di]
	add di,2
@@:
	call VPUTCHR
	retn

handle_s:
	mov si,ss:[di]
	add di,2
	jmp print_string
handle_d:
handle_i:
	mov bx,-10
	jmp @F
handle_u:
	mov bx, 10
	jmp @F
handle_x:
	mov bx, 16
@@:
	xor dx,dx
	mov ax,ss:[di]
	add di,2
	cmp longarg,1
	jnz @F
	mov dx,ss:[di]
	add di,2
	jmp printnum
@@:
	and bx,bx
	jns @F
	cdq
@@:
printnum:
	lea si, szTmp
	push eax       ;v5.86: added
	invoke ltoa, dx::ax, si, bx
	mov si, ax
	pop eax        ;v5.86: added
	push ds
	push ss
	pop ds
	call print_string
	pop ds
	retn

print_string:		;print string SI
	mov ax, si
	.while byte ptr [si]
		inc si
	.endw
	sub si, ax
	xchg ax, si
	mov bx,size_
	sub bx, ax
	.if flag == 1
		.while sword ptr bx > 0
			mov ax, [fillchr]
			call VPUTCHR	;print leading filler chars
			dec bx
		.endw
	.endif

	.while byte ptr [si]
		lodsb
		call VPUTCHR		;print char of string
	.endw

	.while sword ptr bx > 0
		mov ax, [fillchr]
		call VPUTCHR		;print trailing spaces
		dec bx
	.endw
	retn

VPUTCHR:
	cmp al,10
	jnz @F
	mov al,13
	call @F
	mov al,10
@@:
	push bx
	xor bx, bx
	mov ah, 0Eh
	int 10h
	pop bx
	retn

dprintf endp
