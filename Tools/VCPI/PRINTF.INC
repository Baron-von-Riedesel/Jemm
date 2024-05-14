
;--- ltob(long n, char * s, int base);
;--- convert long to string

ltob PROC stdcall uses edi edx number:dword, outb:ptr, base:word

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

ltob ENDP

;--- hiword(eax) is modified if numbers are rendered!

printf PROC c fmt:ptr, args:VARARG

local size_:word
local flag:byte
local longarg:byte
local fill:byte
local szTmp[12]:byte

	pusha
	lea di,[fmt+2]
@@L335:
	mov si,[fmt]
nextchar:
	lodsb
	or al,al
	je done
	cmp al,'%'
	je formatitem
	call handle_char
	jmp nextchar
done:
	popa
	ret

formatitem:
	push @@L335
	xor dx,dx
	mov [longarg],dl
	mov bl,1
	mov cl,' '
	cmp BYTE PTR [si],'-'
	jne @F
	dec bx
	inc si
@@:
	mov [flag],bl
	cmp BYTE PTR [si],'0'
	jne @F
	mov cl,'0'
	inc si
@@:
	mov [fill],cl
	mov bx,dx

	.while byte ptr [si] >= '0' && byte ptr [si] <= '9'
		lodsb
		sub al,'0'
		cbw
		imul cx,bx,10		;cx = bx * 10
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
	cmp al,'c'
	je handle_c
	cmp al,'d'
	je handle_d
	cmp al,'i'
	je handle_i
	cmp al,'s'
	je handle_s
	cmp al,'u'
	je handle_u
	cmp al,0
	jnz @@L359
	pop ax
	jmp done
handle_c:
	mov ax,ss:[di]
	add di,2
@@L359:
	call handle_char
	retn

handle_x:
	mov bx,16
	jmp @@lprt262
handle_d:
handle_i:
	mov bx,-10
	jmp @@lprt262
handle_u:
	mov bx,10
@@lprt262:
	mov ax,ss:[di]
	add di,2
	sub dx,dx
	cmp bx,0		;signed or unsigned?
	jge @F
	cwd
@@:
	cmp [longarg],0
	je @F
	mov dx,ss:[di]
	add di,2
@@:
	lea cx,[szTmp]
	invoke ltob, dx::ax, cx, bx
	mov si,ax
	push ds
	push ss
	pop ds
	call output_string
	pop ds
	retn

handle_s:
	mov si,ss:[di]
	add di,2

output_string:	;display string at ds:si
	mov ax,si
	mov bx,size_
	.while byte ptr [si]
		inc si
	.endw
	sub si,ax
	xchg ax,si
	sub bx,ax
	.if flag == 1
		.while sword ptr bx > 0
			mov al,[fill]
			call handle_char
			dec bx
		.endw
	.endif

	.while byte ptr [si]
		lodsb
		call handle_char
	.endw

	.while sword ptr bx > 0
		mov al,[fill]
		call handle_char
		dec bx
	.endw
	retn

handle_char:
	cmp al,lf
	jnz @F
	mov al,cr
	call @F
	mov al,lf
@@:
	mov dx, cs
	cmp dx, CSR0
	jnz @F
	call VioPutChar
	retn
@@:
	mov dl, al
	mov ah, 2
	int 21h
	retn

printf ENDP

