
;--- the purpose of the test is to see if page table 0, returned by int 67h, ax=DE01h
;--- is updated by the VCPI host. That's claimed by the VCPI docs, but of course it isn't.
;--- It's simply not feasible, because the host doesn't know if the table is still "valid".


;--- if segments are defined BEFORE .model,
;--- the alignment can be set differently (JWasm only).

_DATA segment para public 'DATA'
_DATA ends
_BSS segment para public 'BSS'
_BSS ends

	.286
	.model small
	.stack 2048
	.dosseg
	.386P
	option casemap:none

?DISPPTE equ 0		;1=display PTE entries before/after mapping change.
?ENTRIES equ 0F0h	;PTE entries to display
?DEB386  equ 1		;1=support (w)deb386 interface
?DISPEXC equ 0		;display exceptions in ring 0

;DPMI real mode call structure - int 31h, ax=300h is emulated.

RMCS    struct
union
rEDI    dd ?            ;+0
rDI		dw ?
ends
union
rESI    dd ?            ;+4
rSI		dw ?
ends
union
rEBP    dd ?            ;+8
rBP		dw ?
ends
RESERVE dd ?            ;+12
union
rEBX    dd ?            ;+16
rBX     dw ?
ends
union
rEDX    dd ?            ;+20
rDX     dw ?
ends
union
rECX    dd ?            ;+24
rCX		dw ?
ends
union
rEAX    dd ?            ;+28
rAX		dw ?
ends
rFlags  dw ?            ;+32
rES     dw ?            ;+34
rDS     dw ?            ;+36
rFS     dw ?            ;+38    
rGS     dw ?            ;+40  
union
rCSIP	dd ?            ;+42
struct
rIP     dw ?
rCS     dw ?
ends
ends
union
rSSSP	dd ?            ;+46
struct
rSP     dw ?
rSS     dw ?
ends
ends
RMCS    ends

	include vcpi.inc

CStr macro text:vararg
local sym
	.const
sym db text,0
	.code
	exitm <offset sym>
endm

if ?DEB386
D386_Identify       equ 43h	; returns debugger identification
D386_Prepare_PMode  equ 44h	; partially prepare for protected mode operation
D386_Real_Mode_Init equ 45h	; tell kd we're done
PMINIT_INIT_IDT     equ 0	; (ES:EDI) = pointer to PM IDT
D386_Id             equ 0F386h ; debugger identification code
endif

lf	equ 10
cr	equ 13

	.data

mygdt label byte                ;GDT
        db 1*8 dup (0)          ;+00h null descriptor
restab  db 3*8 dup (0)          ;+08h descriptors reserved for vcpi host
pmcs    desc <0ffffh,0,0,9Ah,0,0>	;+20h
pmds    desc <0ffffh,0,0,92h,0,0>	;+28h
pmtr    desc <068h-1,0,0,89h,0,0> ;selector for TR	;+38h
pmflat  desc <0ffffh,0,0,92h,8fh,0>	;+30h
if ?DEB386
kddesc label dword			;+48
		db 3*8 dup (0)
KDSEL   equ kddesc - mygdt
endif
SIZGDT	equ $      - mygdt

CSR0	equ pmcs   - mygdt
DSR0	equ pmds   - mygdt
TRSEL 	equ pmtr   - mygdt
FLATSEL	equ pmflat - mygdt
HOSTCS	equ restab - mygdt

pdgdt    label fword
         dw SIZGDT-1            ;limit GDTR
basegdt  dd offset mygdt        ;base  GDTR

pdidt    label fword
         dw sizeof myidt-1      ;limit IDTR
baseidt  dd offset myidt        ;base  IDTR

;--- far32 address of VCPI protected-mode API

vcpiv   label fword
vcpiofs dd 0
		dw HOSTCS		;selector for VCPI host code segment
		dw 0

msw V86toPM <0, offset pdgdt, offset pdidt, 0, TRSEL, offset pmentry, CSR0>

segcs   dw 0		;segment CS
segds   dw 0		;segment DS
ptadr   dw 0		;segment page table 0
vcpiend dw 0		;offset in pagetab 0 where free space begins

if ?DEB386
KD_DEB386  equ 2
bKrnlDbg db 0
dfDbgEntry df 0
endif

	.data?

myidt   db 100h*8 dup (?)
ptab    db 1000h dup (?)
taskseg TSSSEG <>   ;task state segment
rmcs RMCS <>

	.code

	include printf.inc

println proc
	invoke printf, CStr(10)
	ret
println endp

if ?DISPEXC

;------ FEDCBA9876543210   FEDCBA9876543210
excv dw 0111110100000000b, 0000000000000110b

?EXC = 0

@defexc macro
	push ?EXC
	jmp defexc
?EXC = ?EXC + 1
endm

exceptions:
	rept 32
	@defexc
	endm

EXCFRAME1 struct
dwEbp dd ?
wExc  dw ?,?
dwErr dd ?
dwEip dd ?
wCs   dw ?,?
dwEfl dd ?
EXCFRAME1 ends

EXCFRAME2 struct
dwEbp dd ?
wExc  dw ?,?
dwEip dd ?
wCs   dw ?,?
dwEfl dd ?
EXCFRAME2 ends

defexc:
	push ebp
	mov ebp,esp
	mov ax, [ebp].EXCFRAME1.wExc
	bt cs:[excv], ax
	jnc @F
	invoke printf, CStr("exc %X at %X:%lX, errc=%lX",lf), [ebp].EXCFRAME1.wExc, [ebp].EXCFRAME1.wCs, [ebp].EXCFRAME1.dwEip, [ebp].EXCFRAME1.dwErr
	jmp de2
@@:
	invoke printf, CStr("exc %X at %X:%lX",lf), [ebp].EXCFRAME2.wExc, [ebp].EXCFRAME2.wCs, [ebp].EXCFRAME2.dwEip
de2:
	jmp $	; just stop, we cannot continue

endif

defint proc near
	push eax
	mov al,0Bh
	out 0A0h,al
	in al,0A0h
	and al,al
	jz @F
	mov al,20h
	out 0a0h,al
@@:
	mov al,0Bh
	out 20h,al
	in al,20h
	and al,al
	jz @F
	mov al,20h
	out 20h,al
@@:
	pop eax
	iretd
defint endp

int31 proc
	cmp ax,300h
	jz is300
	jmp exit
is300:
	pushad
	push di
	call pm2rm
	mov [intno],bl
	pop di
	push di
	mov esi,es:[di].RMCS.rESI
	mov ebp,es:[di].RMCS.rEBP
	mov ebx,es:[di].RMCS.rEBX
	mov ecx,es:[di].RMCS.rECX
	mov edx,es:[di].RMCS.rEDX
	mov eax,es:[di].RMCS.rEAX
	mov ds,es:[di].RMCS.rDS
	mov edi,es:[di].RMCS.rEDI
	db 0CDh
intno db 0
	push esi
	push eax
	push ebx
	call rm2pm
	pop ebx
	pop eax
	pop esi
	pop di
	mov es:[di].RMCS.rESI, esi
	mov es:[di].RMCS.rEBP, ebp
	mov es:[di].RMCS.rEDX, edx
	mov es:[di].RMCS.rECX, ecx
	mov es:[di].RMCS.rEBX, ebx
	mov es:[di].RMCS.rEAX, eax
	popad
	push ax
	lahf
	mov [esp+2*4+2],ah
	pop ax
exit:
	iretd
int31 endp

int21 proc

    push es
    push di
    mov rmcs.rEAX, eax
    mov rmcs.rEBX, ebx
    mov rmcs.rECX, ecx
    mov rmcs.rEDX, edx
    mov ax,[segds]
    mov rmcs.RMCS.rDS, ax
    mov di, offset rmcs
    push ds
    pop es
    mov bl,21h
    mov ax,300h
    int 31h
    pop di
    pop es

    push ax
    lahf
    mov [esp+2*4+2],ah
    pop ax
    iretd
int21 endp

;--- display PTEs of 1. MB

DispPTEs proc uses es si

	invoke printf, CStr("Paging Table",lf)
	mov es,[ptadr]
	mov si,0000
	mov cx,?ENTRIES
nextitem:
	push cx
	test si,01Fh
	jnz @F
	mov ax,si
	shr ax,2
	invoke printf, CStr("%04X: "), ax
@@:
	mov eax,es:[si+0]
	push ax
	invoke printf,CStr("%8lX "),eax
	pop ax
	add si,4
	test si,1Fh
	jnz @F
	invoke println
@@:
	pop cx
	loop nextitem
	ret
DispPTEs endp

;--- fill VCPI comm structure
;--- set descriptors and IDT

setdescriptors proc
	mov ax,cs
	movzx eax,ax
	shl eax, 4
	mov pmcs.A0015,ax
	shr eax,16
	mov pmcs.A1623,al

	mov ax,ds
	movzx eax,ax
	shl eax, 4
	add basegdt, eax
	add baseidt, eax
	add msw._Gdtr, eax
	add msw._Idtr, eax

	mov pmds.A0015,ax
	shr eax,16
	mov pmds.A1623,al

	mov ax,ds
	movzx eax,ax
	shl eax, 4
	add eax, offset taskseg
	mov pmtr.A0015,ax
	shr eax,16
	mov pmtr.A1623,al
	mov dword ptr taskseg.dfStk0, esp
	mov word ptr taskseg.dfStk0+4, DSR0

	mov bx,0
	mov di,offset myidt
if ?DISPEXC
	mov ax,offset exceptions
nextitem:
	mov word ptr [di+0],ax
	mov word ptr [di+2],CSR0
	mov word ptr [di+4],0EE00h
	mov word ptr [di+6],0
	add di,8
	add ax,4
	inc bl
	cmp bl,20h
	jnz nextitem
endif
nextitem2:
	mov word ptr [di+0],offset defint
	mov word ptr [di+2],CSR0
	mov word ptr [di+4],0EE00h
	mov word ptr [di+6],0
	add di,8
	inc bl
	jnz nextitem2

	mov word ptr myidt+21h*8,offset int21
	mov word ptr myidt+31h*8,offset int31

	ret
setdescriptors endp

;--- jump to pm

rm2pm proc
	mov pmtr.attrib,89h
	cli
	pushf
	pop ax
	and ah,03Fh  ;clear NT
	push ax
	popf
	pushf
	mov ax, ds
	movzx eax, ax
	shl eax, 4
	lea esi, [eax + offset msw]
	movzx ebx,sp
	mov ax,0DE0Ch
	int 67h
pmentry::						;now in protected mode
	mov ax,DSR0
	mov ss,ax
	mov esp,ebx
	mov ds,ax
	mov es,ax
	popf
	ret
rm2pm endp

;--- jump to v86

pm2rm proc

	movzx edx,sp
	movzx eax, [segds]
	pushd 0		;gs
	pushd 0		;fs
	push eax	;ds
	push eax	;es
	push eax	;ss
	push edx	;esp
	pushd 2		;efl
	movzx eax, [segcs]
	push eax
	pushd offset rmentr
	clts						;clear task switched flag
	mov ax, FLATSEL
	mov ds,ax					;DS must be FLAT
	mov ax,0DE0Ch
	call fword ptr ss:[vcpiv]
rmentr: 						;back in v86-mode
	sti
	ret
pm2rm endp

;--- switch to protected-mode
;--- call a real-mode int
;--- finally, switch back to v86-mode

pmgo proc

	cli

	mov [segcs],cs
	mov [segds],ds

	call rm2pm

	mov ax,FLATSEL		;4G selector -> ES
	mov es,ax

if ?DEB386
	cmp bKrnlDbg,KD_DEB386
	jnz @F
	push ds
	pop es
	mov edi, offset myidt	;es:edi=idt
	mov al, PMINIT_INIT_IDT
	call [dfDbgEntry]
	int 3
@@:
endif

	invoke printf, CStr("hello from pm",10)

;--- now map another page into physical page 0

	mov rmcs.rDX,0		; system handle
	mov rmcs.rAX,4400h	; map page into physical page 0
	mov rmcs.rBX,0		; logical page 0
	mov di,offset rmcs
	mov bl,67h
	mov ax,300h
	int 31h

	call pm2rm
    
if ?DEB386
	cmp bKrnlDbg,KD_DEB386
	jnz @F
	mov ah, D386_Real_Mode_Init
	int 68h
@@:
endif
	ret
pmgo endp

;--- VCPI host was detected.
;--- switch to protected-mode and back

runvcpi proc near

	mov ax,0DE00h		;is vcpi supported?
	int 67h
	cmp ah,00
	jnz vcpi_err
pvcpi1:
	call setdescriptors
	push ds
	pop es

if ?DEB386
	mov ah,D386_Identify
	int 68h
	cmp ax, D386_Id
	jnz kd_done
	mov bKrnlDbg, KD_DEB386
	mov bx, FLATSEL
	mov cx, KDSEL
	mov dx, 0	; no GDT sel
	mov si, offset mygdt	; ds:si=gdt
	mov di, offset myidt	; es:di=idt
	mov ah, D386_Prepare_PMode
	int 68h
	mov dword ptr [dfDbgEntry+0], edi
	mov  word ptr [dfDbgEntry+4], es
	push ds
	pop es
endif
kd_done:

	mov es,[ptadr]
	xor di,di			;ES:DI -> page table 0
	mov si,offset restab;DS:SI -> 3 free GDT descriptors
	mov ax,0DE01h		;get protected mode interface
	int 67h
	cmp ah,00
	jnz vcpi_err1
	mov [vcpiofs],ebx
	mov vcpiend,di
if ?DISPPTE
	call DispPTEs
endif
	call pmgo
if ?DISPPTE
	call DispPTEs
endif
exit:
	ret

vcpi_err:
	invoke printf, CStr("no VCPI host found",lf)
	jmp exit
vcpi_err1:
	invoke printf, CStr("VCPI func DE01 failed",lf)
	jmp exit
runvcpi endp

;--- get cmdline parameters

getparm proc near
	ret
getparm endp

main proc c

	mov di, offset ptab
	mov cx, (sizeof ptab) / 4
	push ds
	pop es
	xor eax,eax
	rep stosd

	mov ax,3567h
	int 21h
	mov ax,es
	or ax,bx
	jnz main3
	invoke printf, CStr("int 67h is zero (no EMM)",lf)
	mov al,01
	jmp exit
main3:
						;get memory for page tables
	mov bx,400h
	mov ah,48h
	int 21h
	jc exit
	mov bx,ax
	movzx eax,ax
	shl eax, 4
	add eax,4096-1		;page directory must be page aligned
	and ax,0f000h		;clear bits 0-11 

	mov msw._CR3,eax
	mov edi,eax
	add edi,1000h
	shr eax,4
	mov es,ax
						;page directory 1. entry
	or di,1+2+4			;set present, r/w, user
	mov es:[0000],edi	;set PDE for 0-3FFFFFh
	mov ax,es
	add ax,100h
	mov [ptadr],ax

	call runvcpi

	mov al,00
exit:
	ret
main endp


start:
	mov ax,@data
	mov ds,ax
	mov bx,ss
	mov cx,ds
	sub bx,cx
	shl bx,4
	add bx,sp
	mov ss,ax
	mov sp,bx       ;make SS=DS

	mov ax,ds
	mov cx,cs
	sub ax,cx
	add ax,10h
	shr bx,4
	add bx,ax
	mov ah,4ah
	int 21h

	push es
	push ds
	pop es
	mov di, offset myidt
	mov cx, sp
	sub cx, di
	shr cx, 1
	xor ax, ax
	rep stosw
	pop es
	call main
	mov ax,4c00h
	int 21h

	END start
