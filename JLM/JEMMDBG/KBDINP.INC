
;--- poll keyboard (US keys)

;*** keyboard BIOS variables

KBDSTAT  equ   417h
BUFSTA	 equ   41Ah
BUFEND	 equ   41Ch
EBUFSTA  equ   480h
EBUFEND  equ   482h

	.data

lastk db 0

normalk label byte
	db 0,1Bh				;00-01 NULL, escape
	db '1234567890-='		;02-0D
	db 8,9					;0E-0F backspace + tab
	db 'qwertyuiop[]'		;10-1B
	db 0Dh,0				;1C-1D return, ctrl-l 
	db "asdfghjkl;'`"		;1E-29
	db 0					;2A    shift-l
	db '\'					;2B
	db "zxcvbnm,./"			;2C-35
k56n db "\"        			;56

shiftk label byte
	db 0,1Bh				;00-01
	db '!@#$%^&*()_+'		;02-0D
	db 8,0Fh				;0E-0F backspace + tab
	db 'QWERTYUIOP{}'		;10-1B
	db 0Dh,0				;1C-1D return, ctrl-l 
	db 'ASDFGHJKL:"~'		;1E-29
	db 0					;2A    shift-l
	db '|'					;2B
	db 'ZXCVBNM<>?'			;2C-35
k56s db "|"        			;56

altgrk	db 36h+1 dup (0)		;00-35, 56
        
ctrlk label byte
	db 0,1Bh											;00-01
	db 0Ch dup (0)										;02-0D
	db 7Fh,0											;0E-0F
	db 11h,17h,05h,12h,14h,19h,15h,09h,0Fh,10h,1Bh,1Dh	;10-1B
	db 0Ah,00											;1C-1D
	db 01h,13h,04h,06h,07h,08h,0Ah,0Bh,0Ch				;1E-26
	db 0,0,0,0,0										;27-2B
	db 1Ah,18h,03h,16h,02h,0Eh,0Dh						;2C-32
	db 0,0,0											;33-35
	db 0												;56

cntlkeystab label byte
	db 36h		;R-SH		;codes ctrl keys
	db 2Ah		;L-SH		;order matches bits in 0040h:0017h
	db 1Dh		;CTRL
	db 38h		;ALT
	db 46h		;SCROLL lock;10
	db 45h		;NUM lock	;20
	db 3Ah		;CAPS		;40
	db 52h		;INS		;80
LCTLKEYS equ $ - offset cntlkeystab

	.CODE

;*** get kbd state
;*** ZERO? if no key available

GetKbdStatus proc
	pushfd
	pop eax
	test ah, 2			; IF set?
	jz @F
	in al, 21h
	test al, 2			; IRQ 1 enabled?
	jnz @F
	mov al, 0Bh
	out 20h, al
	in al, 20h
	test al, 03h		; irq 0 or irq 1 request?
	jz nopoll
@@:
	in al, 64h
	test al, 01h		; input buffer full?
	jz nokey
	mov ah, al
	in al, 60h
	test ah, 20h		; is it input from PS/2?
	jnz nokey
	call setkbdbiosvars	; set kbd BIOS variables
	mov [lastk], al
	jc nokey
	cmp al,80h
	jnc nokey
	ret
nokey:
	xor al,al
	ret
nopoll:
	push eax
	mov ax,ds:[BUFSTA]	; char in buffer?
	cmp ax,ds:[BUFEND]
	pop eax
	ret

GetKbdStatus endp

;--- set kbd status bios variable
;--- used only if interrupts disabled
;--- out: C=nokey ( just status changed)
;---     NC=key

setkbdbiosvars proc
	pushad
	mov bh,al 				;check if ctrl, shift, alt, ...
	and al,7fh
	mov edi, offset cntlkeystab
	mov bl,00
	mov ecx, LCTLKEYS
	repnz scasb
	jnz nostd				; no, std key
	mov bl,80h
	shr bl,cl
	mov ch,bh
;	and byte ptr ds:[KBDSTAT+1],not 4 ;reset Sys-Req
	mov ax, ds:[KBDSTAT]
	and ah, not 4			; reset sys-req
	test ch, 80h			; key released or pressed?
	jz @F
	xor bl,0FFh
	and al,bl				; reset flag
	and ah,bl
	jmp setflags
@@:
	or al,bl				; set flag
	or ah,bl				; set flag
setflags:        
	cmp cl,4				; RSHIFT,LSHIFT,CTRL,ALT?
	jnb @F
	mov ds:[KBDSTAT+1],ah
	xor ds:[KBDSTAT],ah
	jmp donestat
@@:
	mov ds:[KBDSTAT],al
donestat:
	and ch,7Fh
	cmp ch,38h				;Alt key?
	jnz @F
	cmp [lastk],0E0h		;last key 0E0? 
	jnz @F
	and byte ptr ds:[496h],not 8	;AltGr
	and ah,08
	or ds:[496h],ah
@@:  
	cmp ch,52h				;INSERT IS a key!
	jz nostd
	popad
	stc
	RET
nostd:
	popad
	clc
	ret
setkbdbiosvars endp

; *** get char from KBD without wait

GetKbdChar proc
	call GetKbdStatus
	jz nokey
	mov al,[lastk]
	test al,80h
	jnz nokey			;key released, no further processing
	cmp al,39h			;space?
	jz isspace
	cmp al,56h
	ja getkbdxchar
	jb @F
	mov al,36h
@@:
	cmp al,36h
	ja getkbdxchar
	mov ebx, offset normalk
	mov ah, ds:[KBDSTAT]
	test ah,3			;shift pressed
	jz @F
	mov ebx, offset shiftk
@@:
	test ah,4			;ctrl pressed?
	jz @F
	mov ebx, offset ctrlk
@@:
	test ah,8			;alt pressed?
	jz @F
	test byte ptr ds:[496h],8	;AltGr pressed?
	jz getkbdxchar2
	mov ebx, offset altgrk
@@:
	movzx eax,al
	add ebx, eax
	mov bl,byte ptr [ebx]
	and bl,bl
	jz getkbdxchar
	mov al,bl
	ret
isspace:
	mov ah,al
	mov al,' '
	ret
getkbdxchar2:
getkbdxchar:
	mov ah,al
	mov al,00
	ret

nokey:
	xor ax,ax
	ret
GetKbdChar endp

;--- loop to wait for a char

KbdGetChar proc uses ebx

@@:
	call GetKbdChar
	and ax,ax
	jz @B
	ret

KbdGetChar endp

