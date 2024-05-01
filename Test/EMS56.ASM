
;*** test int 67h, ah=56h (alter map and call)

	.286
	.model small
	.stack 2048
	.dosseg
	option casemap:none
	.386

lf equ 10
;extern	__acrtused:abs

CStr macro text:vararg
local x
	.const
x	db text,0
	.code
	exitm <offset x>
endm

EMS56	struct
dwProc	 dd ?       ;far proc to call
bSizeNew db ?
pMapNew	 dd ?       ;new mapping
bSizeOld db ?
pMapOld	 dd ?       ;old mapping
EMS56	ends

log_phys_map struct
dwLogPage	dw ?	;logical page
dwPhysPage	dw ?	;segment or phys page
log_phys_map ends

	.data

ems56 	EMS56 <>

MapNew	log_phys_map <0,0>
		log_phys_map <1,1>

MapOld	log_phys_map <-1,0>
		log_phys_map <-1,1>

	.code

	include <printf.inc>

main proc c argc:word, argv:word

local handle:word
local wPages:word
local frame:word

	mov handle,-1
	mov ax,3567h
	int 21h
	mov ax,bx
	mov cx,es
	or ax,cx
	jz noemm

	mov bx,2
	mov ah,43h	   ;alloc 2 pages
	int 67h
	and ah,ah
	jnz error2
	mov handle,dx
	invoke printf, CStr("Int 67h, ah=43h, bx=2: Handle %X allocated",lf), handle

	mov bx,0
	mov dx,handle
	mov ax,4400h   ;map to phys page 0
	int 67h
	and ah,ah
	jnz error4
	invoke printf, CStr("Int 67h, ax=4400h, bx=0: log page 0 mapped to phys page 0",lf)

	mov bx,1
	mov dx,handle
	mov ax,4401h   ;map to phys page 1
	int 67h
	and ah,ah
	jnz error4
	invoke printf, CStr("Int 67h, ax=4401h, bx=1: log page 1 mapped to phys page 1",lf)

	mov ah,41h	   ;get page frame
	int 67h
	and ah,ah
	jnz error3
	mov frame,bx
	invoke printf, CStr("Int 67h, ah=41h: Page Frame is %X",lf), frame

;--- now copy a small test routine into page 0 of page frame

	mov es,frame
	mov di,0
	mov si,offset testpr
	push ds
	push cs
	pop ds
	mov cx,sizeproc
	rep movsb
	pop ds

;--- unmap page 0

	mov bx,-1
	mov dx,handle
	mov ax,4400h   ;unmap page 0
	int 67h
	and ah,ah
	jnz error4
	invoke printf, CStr("Int 67h, ax=4400, bx=-1: phys page 0 unmapped",lf)

	mov dx,handle
	mov ax,5602h
	int 67h
	mov ax, sp
	invoke printf, CStr("Int 67h, ax=5602h: additional stack space for call: %X, SP=%X",lf), bx, ax

;--- prepare ax=5600h, DS:SI->EMS56

	mov si,offset ems56
	mov ax, frame
	mov word ptr [si].EMS56.dwProc+0, 0
	mov word ptr [si].EMS56.dwProc+2, ax
	mov [si].EMS56.bSizeNew,2
	mov word ptr [si].EMS56.pMapNew+0, offset MapNew
	mov word ptr [si].EMS56.pMapNew+2, ds
	mov [si].EMS56.bSizeOld,2
	mov word ptr [si].EMS56.pMapOld+0, offset MapOld
	mov word ptr [si].EMS56.pMapOld+2, ds
	mov dx,handle
	mov ax,5600h
	int 67h
	and ah,ah
	jnz error5

	mov ax,sp
	invoke printf, CStr("Int 67h, ax=5600h ok, SP after call=%X",lf), ax

exit2:
	invoke printf, CStr(lf)
exit:
	mov dx,handle
	cmp dx,-1
	jz @F
	mov ah,45h
	int 67h
@@:
	ret
noemm:
	invoke printf, CStr("EMM not found",lf)
	jmp exit
error2:
	mov al,ah
	mov ah,0
	invoke printf, CStr("int 67h, ah=43h, bx=%u failed, status=%02X",lf), bx, ax
	jmp exit
error3:
	mov al,ah
	mov ah,0
	invoke printf, CStr("int 67h, ah=41h failed, status=%02X",lf), ax
	jmp exit
error4:
	mov al,ah
	mov ah,0
	invoke printf, CStr("int 67h, ah=44h failed, status=%02X",lf), ax
	jmp exit
error5:
	mov al,ah
	mov ah,0
	invoke printf, CStr("int 67h, ax=5600h failed, status=%02X",lf), ax
	jmp exit
main endp

;--- this small routine is copied into page 0 of page frame

testpr proc far
	mov ah,02
	mov dl,'*'
	int 21h
	ret
testpr endp

sizeproc equ $ - testpr

start:
	mov ax,@data
	mov ds,ax
	mov bx,ss
	mov cx,ds
	sub bx,cx
	shl bx,4
	add bx,sp
	mov ss,ax
	mov sp,bx
	call main
	mov ah,4Ch
	int 21h

	END start
