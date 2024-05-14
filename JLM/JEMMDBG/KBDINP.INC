
;--- poll keyboard (US/GR keys)
;--- ds/es=flat, cs=flat

ifndef KEYS
KEYS textequ <KBD_US>
endif

;*** keyboard BIOS variables

KBDSTAT  equ   417h
BUFSTA	 equ   41Ah
BUFEND	 equ   41Ch
EBUFSTA  equ   480h
EBUFEND  equ   482h

	.data

lastk db 0

%	include KEYS.inc

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
	cmp ds:[lastk],0E0h		;last key 0E0? 
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
	mov al,ds:[lastk]
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
	mov bl,byte ptr ds:[ebx]
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

