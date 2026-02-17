
;--- printf for debug displays
;--- assume CS and SS flat;
;--- no assumptions about DS/ES

;--- i64toa(long long n, char * s, int base);
;--- convert 64-bit long long to string

i64toa proc stdcall uses edi number:qword, outb:ptr, base:dword

	mov ch,0
	mov edi, base
	mov eax, dword ptr number+0
	mov esi, dword ptr number+4
	cmp edi,-10
	jne @F
	neg edi
	and esi,esi
	jns @F
	neg esi
	neg eax
	sbb esi,0
	mov ch,'-'
@@:
	mov ebx,outb
	add ebx,22
	mov byte ptr ss:[ebx],0
@@nextdigit:
	dec ebx
	xor edx,edx
	xchg eax,esi
	div edi
	xchg eax,esi
	div edi
	add dl,'0'
	cmp dl,'9'
	jbe @F
	add dl,7+20h
@@:
	mov ss:[ebx],dl
	mov edx, eax
	or edx, esi
	jne @@nextdigit
	cmp ch,0
	je @F
	dec ebx
	mov ss:[ebx],ch
@@:
	mov eax,ebx
	ret

i64toa endp

dprintf proc c public fmt:ptr, args:vararg

local flag:byte
local longarg:byte
local size_:dword
local fillchr:dword
local szTmp[24]:byte

	pushad
	pushfd
	cld
	lea edi,args
@@L335:
	mov esi,fmt
nextchar:
	lodsb cs:[esi]
	or al,al
	je done
	cmp al,'%'
	je formatitem
	call VPUTCHR
	jmp nextchar
done:
	popfd
	popad
	ret

formatitem:
	push offset @@L335
	xor edx,edx
	mov [longarg],dl
	mov bl,1
	mov cl,' '
	cmp BYTE PTR cs:[esi],'-'
	jne @F
	dec bl
	inc esi
@@:
	mov [flag],bl
	cmp BYTE PTR cs:[esi],'0'
	jne @F
	mov cl,'0'
	inc esi
@@:
	mov [fillchr],ecx
	mov ebx,edx

	.while ( byte ptr cs:[esi] >= '0' && byte ptr cs:[esi] <= '9' )
		lodsb cs:[esi]
		sub al,'0'
		movzx eax,al
		imul ecx,ebx,10		;ecx = ebx * 10
		add eax,ecx
		mov ebx,eax
	.endw

	mov [size_],ebx
	cmp BYTE PTR cs:[esi],'l'
	jne @F
	mov [longarg],1
	inc esi
@@:
	lodsb cs:[esi]
	mov [fmt],esi
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
	pop eax
	jmp done
handle_c:
	mov eax,ss:[edi]
	add edi, 4
@@:
	call dochar
	retn

handle_s:
	mov esi,ss:[edi]
	add edi,4
	jmp print_string
handle_d:
handle_i:
	mov ebx,-10
	jmp @F
handle_u:
	mov ebx, 10
	jmp @F
handle_x:
	mov ebx, 16
@@:
	xor edx,edx
	mov eax,ss:[edi]
	add edi,4
	cmp longarg,1
	jnz @F
	mov edx,ss:[edi]
	add edi,4
	jmp printnum
@@:
	and ebx,ebx
	jns @F
	cdq
@@:
printnum:
	lea esi, szTmp
	invoke i64toa, edx::eax, esi, ebx
	mov esi, eax

print_string:		;print string ESI, size EAX
	mov eax, esi
	.while byte ptr cs:[esi]
		inc esi
	.endw
	sub esi, eax
	xchg eax, esi
	mov ebx,size_
	sub ebx,eax
	.if flag == 1
		.while sdword ptr ebx > 0
			mov eax, [fillchr]
			call dochar	;print leading filler chars
			dec ebx
		.endw
	.endif

	.while byte ptr cs:[esi]
		lodsb cs:[esi]
		call dochar		;print char of string
	.endw

	.while sdword ptr ebx > 0
		mov eax, [fillchr]
		call dochar		;print trailing spaces
		dec ebx
	.endw
	retn
dochar:
	cmp al,10
	jnz @F
	mov al,13
	call @F
	mov al,10
@@:
	jmp VPUTCHR

dprintf endp
