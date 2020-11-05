
;--- simple printf() implementation

strlen proc c uses di string:ptr BYTE

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

handle_char proc

	mov dl,al
	cmp al,10
	jnz @F
	mov dl,13
	call @F
	mov dl,10
@@:
	mov ah,2
	int 21h
	ret

handle_char endp

;--- ltob(long n, char * s, int base);
;--- convert long to string

ltob PROC stdcall uses edi number:dword, outb:word, base:word

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
	mov BYTE PTR [bx],0
	dec bx
@@nextdigit:
	xor edx, edx
	div edi
	add dl,'0'
	cmp dl,'9'
	jbe @F
	add dl,7+20h
@@:
	mov [bx],dl
	dec bx
	and eax, eax
	jne @@nextdigit
	cmp ch,0
	je @F
	mov [bx],ch
	dec bx
@@:
	inc bx
	mov ax,bx
	ret

ltob ENDP

printf PROC c uses es si di bx fmt:ptr byte, args:VARARG

local size_:word
local flag:byte
local longarg:byte
local fill:byte
local szTmp[12]:byte

	push ds
	pop es
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
	mov [fill],cl
	mov [size_],dx
	mov bx,dx
	jmp @@L358
@@FC250:
	cmp BYTE PTR [si],'9'
	jg	@@L362
	lodsb
	sub al,'0'
	cbw
	imul cx,bx,10		;cx = bx * 10
	add ax,cx
	mov bx,ax
@@L358:
	cmp BYTE PTR [si],'0'
	jge @@FC250
@@L362:
	mov [size_],bx
	cmp BYTE PTR [si],'l'
	jne @F
	mov [longarg],1
	inc si
@@:
	lodsb
	mov [fmt],si
	cbw
	cmp al,'x'
	je handle_x
	ja @@L359
	or al,al
	je done 	;\0?
	sub al,'X'
	je handle_x
	sub al,11
	je handle_c	;'c'
	dec al
	je handle_d	;'d'
	sub al,5
	je handle_i	;'i'
	sub al,10
	je handle_s	;'s'
	sub al,2
	je handle_u	;'u'
	jmp @@L359
handle_c:				;'c'
	mov ax,[di]
	add di,2
@@L359:
	call handle_char
	jmp @@L335

handle_s:				;'s'
	mov si,[di]
	add di,2
	jmp @@do_outputstring260

handle_x:				;'X' + 'x'
	mov bx,16
	jmp @@lprt262
handle_d:				;'d'
handle_i:				;'i'
	mov bx,-10
	jmp @@lprt262
handle_u:				;'u'
	mov bx,10
@@lprt262:
	mov ax,[di]
	add di,2
	sub dx,dx
	cmp bx,0		;signed or unsigned?
	jge @F
	cwd
@@:
	cmp [longarg],0
	je @F
	mov dx,[di]
	add di,2
@@:
	lea cx,[szTmp]
	invoke ltob, dx::ax, cx, bx
	mov si,ax
@@do_outputstring260:
	invoke strlen, si
	sub [size_],ax
	cmp BYTE PTR [flag],1
	jne @@L360
	mov bx,[size_]
	jmp @@L363
@@F270:
	mov al,[fill]
	call handle_char
	dec bx
@@L363:
	or bx,bx
	jg @@F270
	mov [size_],bx
	jmp @@L360

@@F273:
	mov al,[si]
	call handle_char
	inc si
@@L360:
	cmp BYTE PTR [si],0
	jne @@F273
	mov bx,[size_]
@@:
	or bx,bx
	jle @@L335
	mov al,[fill]
	call handle_char
	dec bx
	jmp @B

printf ENDP

