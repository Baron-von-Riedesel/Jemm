
;--- MZ stub to run jload.exe
;--- to be assembled with Masm or JWasm
;--- it's a derivate of dpmildxx... 

?MINMEM	 = 600h		;min free paragraphs for JLOAD.EXE
MAXDIR   = 64+4		;max length of a directory path (including 00h)
MAXPATH  = MAXDIR+12
?BESAFE  = 1		;1=check if JLoad.exe looks ok.
?DOSMEMCHK = 1		;0=check for sufficient DOS memory

	.286

ifdef __JWASM__
	option MZ:40h
endif

cr		equ 13
lf		equ 10

mzhdr struct
  e_magic           WORD      ?		;+0
  e_cblp            WORD      ?		;+2
  e_cp              WORD      ?		;+4
  e_crlc            WORD      ?		;+6		number of relocation records
  e_cparhdr         WORD      ?		;+8
  e_minalloc        WORD      ?		;+10
  e_maxalloc        WORD      ?		;+12
  e_ss              WORD      ?		;+14
  e_sp              WORD      ?		;+16
  e_csum            WORD      ?		;+18
  e_ip              WORD      ?		;+20
  e_cs              WORD      ?		;+22
  e_lfarlc          WORD      ?		;+24	begin relocation records
mzhdr ends


_TEXT   segment public 'CODE'

szPgm   equ [bp+00h]     ;execute program name ("JLOAD.EXE")
szParm  equ [bp-MAXPATH] ;application name (from environment)

launch proc

	xor DX,DX
	mov cl,20h
	mov ah,3Fh		;read the MZ header
	int 21h
	jc readerror

if ?BESAFE

;--- additional tests

	xor si,si
	mov ax, [si].mzhdr.e_magic
	cmp ax,"ZM"
	jnz formerror
	mov ax, [si].mzhdr.e_crlc	; no of relocation entries
	mov di,ax
	and ax,ax
	jz norelocs
	push ax
	xor cx,cx
	mov dx,[si].mzhdr.e_lfarlc	; begin relocations
	mov ax,4200h
	int 21h
	pop cx
	shl cx,2					; 4 byte each reloc
	sub sp,cx
	mov dx,sp
	push ds
	push ss
	pop ds
	mov ah,3Fh					; read relocs at SS:SP
	int 21h
	pop ds
	jc formerror
norelocs:
	mov ax,[si].mzhdr.e_cparhdr	; size of header in paragraphs
	push [si].mzhdr.e_ss
	push [si].mzhdr.e_sp
	mov si, [si].mzhdr.e_ip
	shl ax,4
	mov dx,ax
	xor cx,cx
	mov ax,4200h
	int 21h
	xor dx,dx
endif

;--- read JLoad.exe binary

	MOV AH,3Fh
	mov cx,?MINMEM shl 4
	INT 21h
	JC readerror	;---> error "read error"
if ?BESAFE        
	cmp ax,cx		;JLOAD binary must be < 24 kB
	jnc formerror
endif
	mov ah,3Eh
	int 21h

	pop dx
	pop bp

if ?BESAFE
	mov cx,di		;some relocs to resolve?
	jcxz norelocs2
	mov di,sp
	mov ax,ds
@@:
	mov bx,ss:[di+2]
	shl bx,4		;size of loader is <= 24 kB, so no overflow possible
	add bx,ss:[di+0]
	add [bx],ax
	add di,4
	loop @B
	mov sp,di
norelocs2:
endif

;--- fill JLoad's PSP

	mov ah,51h
	int 21h
	push si
	mov si, sp
	add si, 2
	mov di, 81h
	mov al,' '
	stosb
@@:
	lodsb ss:[si]
	stosb
	and al, al
	jnz @B
	dec di
	mov byte ptr es:[di],13
	mov ax, di
	sub ax, 80h
	mov es:[80h],al

	pop si

;--- setup SS:SP

	mov ax, es
	add ax, bp
	add ax, 10h
	mov ss, ax
	mov sp, dx

	push ds
	push si

	push es
	pop ds
	retf
launch endp

if ?BESAFE
formerror:
	mov dx,offset dFormError
	jmp error1
endif

readerror:
	mov dx,offset dReadError
error1:
if 0
;--- close file? Will be done by DOS.
	mov ah,3Eh
	int 21h
endif
errorX: 				;<--- errors
	push cs
	pop ds
	call DispError
	MOV DX,offset dFatal
	call DispError
	mov ax,4CF0h	;error code F0h
	int 21h
DispError:				;display error msg in DX
	MOV AH,09h
	INT 21h
	ret

dFatal		db ' - loading aborted',cr,lf,'$'
dReadError	db "read error",'$'
if ?BESAFE
dFormError	db "invalid JLoad.exe",'$'
endif

endcopy label byte

start proc

;--- setup stack at end of memory block

	cld
	mov ax,ds:[0002]
ife ?DOSMEMCHK        
	mov bp,es
	push ax
	sub ax,bp
	cmp ax,?MINMEM+30h	;enough free memory in this block?
	pop ax
	mov dx,offset dMemory
	jc errorX
endif
	sub ax,30h
	mov ss,ax
	mov sp,300h-MAXPATH

;--- setup BP stack frame

	mov BP,SP
	sub SP,MAXPATH

;--- fill szParm with application name

	mov SI,SP    		;SI=szParm
	push es				;save PSP
	mov es,es:[002Ch]	;ES=environment
	CALL GetAppName		;get name to SS:SI ( SI modified! )

	push cs
	pop ds

;--- search "PATH=", DI=NULL if it doesn't exist

	CALL SearchPath
	MOV SI,DI			;set SI to start of PATH= value

;--- fill szPgm (search JLOAD)

	push SS
	pop DS
	CALL SearchJLoad
	MOV DX,offset dNotFnd
	JB errorX  			;---> error "not found"

;--- copy the final code to end of memory block

	mov cx,offset endcopy
	push ss
	pop es
	xor di,di
	xor si,si
	db 2Eh			;CS prefix
	rep movsb

	pop es			;restore PSP

	push ds
	push cx			;CX is 0

	push cs
	pop ds
	retf

start endp

;--- search name of app in environment
;--- the name may be a full path or not
;--- depending on caller
;--- in: ES=environment, SS:SI=dest
;--- modifies AX,CX,SI,DI

GetAppName proc
	SUB DI,DI
	mov al,00
	mov cx,-1
@@:
	repnz scasb		;search end of environ (00,00)
	scasb
	jnz @B
	inc di			;skip 0001
	inc di

@@:
	mov al,es:[di]
	mov ss:[si],al
	inc si
	inc di
	and al,al
	jnz @B
	RET
GetAppName endp

;--- search PATH= in Environment
;--- In: ES=environment
;--- Out: DI-> behind "PATH=" or NULL
;--- modifies AX,CX,SI,DI

SearchPath proc
	SUB DI,DI
nextitem:
	MOV SI,offset szPath
	MOV CX,SIZPATH
	REPZ CMPSB
	JZ found
	mov al,00
	mov ch,7Fh
	repnz scasb
	cmp al,es:[di]
	JNZ nextitem
	sub di,di
found:
	RET
SearchPath endp

;--- search JLOAD, first in current Dir, then scan PATH
;--- Input: ES=environ, SI=address PATH variable or 0000 (no PATH exists)
;--- Output: NC if found, C if error
;--- full loader path in szPgm
;--- modifies AX,BX,CX,DX,SI,DI

SearchJLoad proc
	lea DI,szPgm
	mov dx,di
nextentry:					;<----
	PUSH SI
	mov si,offset ldrname	;Name "JLOAD.EXE"
	mov cx,SIZLDRNAME
@@:
	db 2Eh		;CS prefix
	lodsb
	mov [di],al
	inc di
	loop @B
	mov [di],cl

	MOV AX,3D00h			;open JLOAD.EXE
	INT 21h
	POP SI
	JNB ldrfound			;jmp if found!
	AND SI,SI
	stc
	JZ notfound				;PATH not defined, so we are done
	MOV DI,DX
	mov cx,MAXDIR
@@:
	mov al,es:[si]
	mov [di],al
	inc si
	inc di
	CMP AL,';'
	JZ @F
	CMP AL,00
	LOOPNZ @B				;PATH done
	XOR SI,SI
@@:
	DEC DI
	CMP Byte Ptr [DI-01],'\'
	JZ nextentry
	MOV Byte Ptr [DI],'\'
	INC DI
	JMP nextentry
ldrfound:
	XCHG ax,bx				;=MOV BX,AX
;	MOV AH,3Eh				;close file
;	INT 21h
;	CLC
notfound:
	RET
SearchJLoad endp

szPath  db   'PATH='
SIZPATH equ $ - szPath

dNotFnd db "Can't find "
ldrname	label byte
	db 'JLOAD.EXE'
SIZLDRNAME equ $ - ldrname
	db '$'

ife ?DOSMEMCHK
dMemory	db "Insufficient memory",'$'
endif

_TEXT ends

if ?DOSMEMCHK
_BSS segment public 'DATA'
	db (?MINMEM+14h) * 16 dup (?)
_BSS ends
endif

STACK segment stack 'STACK'
STACK ends

	end start
