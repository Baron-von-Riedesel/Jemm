
	.286

strlen proc c uses di string:ptr
	mov cx,-1
	mov di,string
	push ds
	pop es
	mov al,0
	cld
	repnz scasb
	mov ax,cx
	inc ax
	not ax
	ret
strlen endp

;--- convert long to string - always base 16
;--- stdcall ltoa(long n, char * s);

ltoa PROC c number:dword, tbuffer:ptr

	mov ch,0
	mov ax, word ptr number+0
	mov dx, word ptr number+2
	mov bx,tbuffer
	add bx,10
	mov BYTE PTR [bx],0
	dec bx

@@nextdigit:
	push ax
	and al,0Fh
	add al,'0'
	cmp al,'9'
	jbe @F
	add al,7+20h
@@:
	mov [bx],al
	dec bx
	pop ax
	mov cl,4
@@:
	shr dx,1
	rcr ax,1
	dec cl
	jnz @B
	mov cx,ax
	or cx,dx
	jne @@nextdigit
	inc bx
	mov ax,bx
	ret

ltoa ENDP

handle_char proc

	pop cx
	pop dx
	push cx
	cmp dl,10
	jnz @F
	push dx
	mov dl,13
	mov ah,2
	int 21h
	pop dx
@@:
	mov ah,2
	int 21h
	ret

handle_char endp

;--- simple printf() implementation

printf PROC c uses si di fmt:ptr byte, args:VARARG

local flag:byte
local longarg:byte
local size_:word
local fillchr:word
local szTmp[12]:byte

	push ds
	pop es
	lea di,args
@@L335:
	mov si,[fmt]
nextchar:
	lodsb
	or al,al
	je done
	cmp al,'%'
	je formatitem
	push ax
	call handle_char
	jmp nextchar
done:
	xor ax,ax
	ret 

formatitem:
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
	mov [fillchr],cx
	mov [size_],dx
	mov bx,dx

	.while ( byte ptr [si] >= '0' && byte ptr [si] <= '9' )
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
	or al,al
	je done
	cmp al,'x'
	je handle_x
	cmp al,'X'
	je handle_x
	cmp al,'s'
	je handle_s
handle_c:
	push WORD PTR [di]
	add di,2
	call handle_char
	jmp @@L335

handle_s:
	mov si,[di]
	add di,2
	jmp print_string

handle_x:
	cmp [longarg],0
	je @F
	mov ax,[di+0]
	mov dx,[di+2]
	add di,4
	jmp @@L341
@@:
	mov ax,[di]
	add di,2
	sub dx,dx		;unsigned integer
@@L341:
	lea cx,[szTmp]
	invoke ltoa, dx::ax, cx
	mov si,ax
print_string:		;print string SI
	push si
	call strlen
	pop bx
	sub [size_],ax
	cmp [flag],1
	jne print_string_chars

	mov bx,[size_]
	jmp @@L363
@@F270:
	push [fillchr]
	call handle_char	;print leading filler chars
	dec bx
@@L363:
	or bx,bx
	jg @@F270
	mov [size_],bx

print_string_chars:

	.while (byte ptr [si])
		lodsb
		push ax
		call handle_char	;print char of string
	.endw

	mov bx,[size_]
@@:
	or bx,bx
	jle @@L335
	push [fillchr]
	call handle_char	;print trailing spaces
	dec bx
	jmp @B

printf ENDP


