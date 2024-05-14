
;*** display VCPI infomation
;*** and use VCPI to switch to protected mode and back

;--- if segments are defined BEFORE .model,
;--- the alignment can be set differently.
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

?ENTRIES equ 110h	;PTE entries to display with option -p
?386SWAT equ 0		;1=support 386SWAT interface (doesn't work!)
?DEB386  equ 1		;1=support (w)deb386 interface
?DISPEXC equ 0		;display exceptions in ring 0

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
if ?386SWAT or ?DEB386
kddesc label dword			;+48
 if ?386SWAT
		db 30*8 dup (0)			; 386SWAT needs 30 descriptors free!?
 else
		db 3*8 dup (0)
 endif
KDSEL   equ offset kddesc - offset mygdt
endif
SIZGDT	equ $             - offset mygdt

CSR0	equ offset pmcs   - offset mygdt
DSR0	equ offset pmds   - offset mygdt
TRSEL 	equ offset pmtr   - offset mygdt
FLATSEL	equ offset pmflat - offset mygdt
HOSTCS	equ offset restab - offset mygdt

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

dwPage	dd 0		;page to release / allocated
dwFreePages dd 0	;number free pages
dwNumPages dd 1		;no of pages to alloc / free
dwAlloced dd 0		;pages allocated
dwFreed dd 0		;pages freed

handle  dw 0		;handle EMS 
segcs   dw 0		;segment CS
segds   dw 0		;segment DS
ptadr   dw 0		;segment page table 0
vcpiend dw 0		;offset in pagetab 0 where free space begins

flags   db 00

UFLAG	equ 1	;option u - display PTEs for UMBs
NFLAG	equ 2	;option n - no switch to pmode
QFLAG	equ 4	;option q - query pages in protected-mode
PFLAG	equ 8	;option p - display PTEs for conv. memory
FFLAG	equ 16	;option f - free pages in pmode
AFLAG	equ 32	;option a - alloc pages in pmode
RFLAG	equ 64	;option r - free pages in rmode

bRet	db 00
bNoDisp	db 00

if ?386SWAT or ?DEB386
KD_386SWAT equ 1
KD_DEB386  equ 2
bKrnlDbg db 0
dfDbgEntry df 0
endif

	.data?

myidt   db 100h*8 dup (?)
ptab    db 1000h dup (?)
taskseg TSSSEG <>   ;task state segment
drtab	dd 8 dup (?)

	.code

	include vioout.inc
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

;--- get descriptor values in EAX (base), DX (limit), CX (attr)

getdesc proc near
	mov ah,[di+7]		;base bits 31..24
	mov al,[di+4]		;base bits 23..16
	shl eax,16
	mov ax,[di+2]		;base bits 15..0
	mov dx,[di+0]		;limit bits 15..0
	mov cx,[di+5]
	ret
getdesc endp

gethex proc
	xor edx, edx
	mov ch,0
nextitem:
	mov al,es:[si]
	cmp al,'0'
	jb done
	cmp al,'9'
	jbe @F
	or al,20h
	cmp al,'a'
	jb done
	cmp al,'f'
	ja done
	sub al,27h
@@:
	sub al,'0'
	movzx eax,al
	shl edx, 4
	add edx, eax
	inc ch
	inc si
	jmp nextitem
done:
	mov eax, edx
	cmp ch,1
	ret
gethex endp

getdec  proc
	xor edx, edx
	mov ch,0
nextitem:
	mov al,es:[si]
	cmp al,'0'
	jb done
	cmp al,'9'
	ja done
	sub al,'0'
	movzx eax,al
	shl edx, 1
	lea edx, [edx+edx*4]
	add edx, eax
	inc ch
	inc si
	jmp nextitem
done:
	mov eax, edx
	cmp ch,1
	ret
getdec  endp

EMScheck proc

	push ds
	push si
	push di

	mov ax,3567h
	int 21h
	push ds
	pop es

	mov di,000ah
	push cs
	pop ds
	mov si,offset emsstr
	mov cx,8
	repz cmpsb
	mov ax,1
	jz @F			   ;1 = EMS exists
	dec ax			   ;0 = EMS doesn't exist
@@:
	pop di
	pop si
	pop ds
	ret
EMScheck endp

emsstr  db 'EMMXXXX0'

;--- display UMBs

DispUMBs proc uses es si

	nop ;MASM bug
	invoke printf, CStr("Pages used for UMBs:",lf)
	mov es,[ptadr]
	mov si,0000
	mov cx,100h
	xor edx,edx
nextitem:
	push cx
	push edx
	mov eax,es:[si]
	and ax,0F000h
	cmp eax,edx
	jz @F
	mov eax, edx
	shr eax,4
	invoke printf,CStr("%04X "), ax
@@:
	pop edx
	add edx,1000h
	add si,4
	pop cx
	loop nextitem
	invoke println
	ret
DispUMBs endp        

;--- display PTEs of 1. MB

DispPTEs proc uses es si

	nop ;MASM bug
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
	and ax,0FFE7h		;???
	mov es:[si+0],ax	;???
	add si,4
	test si,1Fh
	jnz @F
	invoke println
@@:
	pop cx
if 1
	cmp si, vcpiend
	jb nextitem
else
	loop nextitem
endif
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
	ret
setdescriptors endp

;--- switch to protected-mode and back to v86-mode throu VCPI

pmgo proc

if ?386SWAT
	cmp bKrnlDbg, KD_386SWAT
	jnz no386swat2
	push ds
	pop es
	mov di, offset kddesc
	mov bx, KDSEL
	mov ax, 0DEF2h
	int 67h
	cmp ah,0
	jnz no386swat2
	mov dword ptr [dfDbgEntry+0], edx
	mov  word ptr [dfDbgEntry+4], bx

	mov cx, 10h
	mov bx, 0
	mov di, offset myidt
@@:
	mov ax, 0DEF3h
	int 67h
	inc bx
	add di, 8
	loop @B
no386swat2:
endif

	cli

	mov [segcs],cs
	mov [segds],ds

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
	mov ax,FLATSEL		;4G selector -> ES
	mov es,ax

if ?386SWAT
	cmp bKrnlDbg,KD_386SWAT
	jnz @F
	int 3
@@:
endif
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
	test flags, QFLAG
	jz @F
	call pmquery
@@:
	test flags, AFLAG
	jz @F
	call pmalloc
@@:
	test flags, FFLAG
	jz @F
	call pmfree
@@:

;--- jump back to v86

	sub sp, sizeof IRETV86
	mov bp, sp
	xor eax,eax
	mov [bp].IRETV86._Eip, offset rmentr
	mov ax, [segcs]
	mov [bp].IRETV86._Cs, eax
	mov [bp].IRETV86._Efl, 2
	mov [bp].IRETV86._Esp, ebx
	mov ax, [segds]
	mov [bp].IRETV86._Ss, eax
	mov [bp].IRETV86._Es, eax
	mov [bp].IRETV86._Ds, eax
	xor ax, ax
	mov [bp].IRETV86._Fs, eax
	mov [bp].IRETV86._Gs, eax

	clts						;clear task switched flag
	mov ax, FLATSEL
	mov ds,ax					;DS must be FLAT
	mov ax,0DE0Ch
	call fword ptr ss:[vcpiv]
rmentr: 						;back in v86-mode
	sti
if ?DEB386
	cmp bKrnlDbg,KD_DEB386
	jnz @F
	mov ah, D386_Real_Mode_Init
	int 68h
@@:
endif
	ret
pmgo endp

protocol proc
	.if (flags & AFLAG)
		invoke printf, CStr("alloced %lu"), dwAlloced
		movzx ax,bRet
		invoke printf, CStr(" page(s) in pm, last status ah=%02X"),ax
		.if (dwAlloced)
			invoke printf, CStr(", (first) page=%08lX"), dwPage
		.endif
		invoke println
	.elseif (flags & FFLAG)
		invoke printf, CStr("freed %lu"), dwFreed
		movzx ax,bRet
		invoke printf, CStr(" page(s) in pm, last status ah=%02X"),ax
		.if (dwFreed)
			invoke printf, CStr(", (last) page released=%08lX"), dwPage
		.endif
		invoke println
	.elseif (flags & RFLAG)
		invoke printf, CStr("freed %lu"), dwFreed
		movzx ax,bRet
		invoke printf, CStr(" page(s) in rm, last status ah=%02X"),ax
		.if (dwFreed)
			invoke printf, CStr(", (last) page released=%08lX"), dwPage
		.endif
		invoke println
	.elseif (flags & QFLAG)
		movzx ax,bRet
		invoke printf, CStr("%lu free pages in pm, status ah=%02X",lf), dwFreePages, ax
	.elseif (flags & (UFLAG or PFLAG))
	.elseif (!(flags & NFLAG))
		invoke printf, CStr('Protected Mode Switch ok',lf)
	.endif
	ret
protocol endp

;--- query free VCPI page(s) using protected-mode API

pmquery proc
	pushad
	mov ax,0DE03h
	call fword ptr ss:[vcpiv]
	mov bRet, ah
	mov dwFreePages, edx
	popad
	ret
pmquery endp

;--- allocate VCPI page(s) using protected-mode API

pmalloc proc
	pushad
	mov ecx, dwNumPages
nextitem:
	mov ax,0DE04h
	call fword ptr ss:[vcpiv]
	mov bRet, ah
	and ah,ah
	jnz allocerr
	inc dwAlloced
	cmp ecx,dwNumPages
	jnz @F
	mov dwPage, edx
@@:
	dec ecx
	jnz nextitem
allocerr:
	popad
	ret
pmalloc endp

;--- release VCPI page(s) with protected-mode VCPI API

pmfree proc
	mov edx, dwPage
	and edx, edx
	jz exit
	pushad
	mov ecx, dwNumPages
nextitem:
	mov ax,0DE05h
	call fword ptr ss:[vcpiv]
	and ah,ah
	jnz done
	mov dwPage, edx
	inc dwFreed
	add edx,1000h
	dec ecx
	jnz nextitem
done:
	mov bRet, ah
	popad
exit:
	ret
pmfree endp

;--- free VCPI pages with real-mode VCPI API

rmfree proc
	mov edx, dwPage
	and edx, edx
	jz exit
	mov ecx, dwNumPages
nextitem:
	mov ax,0DE05h
	int 67h
	and ah,ah
	jnz exit
	inc dwFreed
	mov dwPage, edx
	add edx,1000h
	dec ecx
	jnz nextitem
exit:
	mov bRet, ah
	ret
rmfree endp

;--- VCPI host was detected,
;--- now call vcpi functions

runvcpi proc near

	mov cl,2
@@:
	mov ax,0DE00h		;is vcpi supported?
	int 67h
	cmp ah,00
	jz pvcpi1
	push cx
	call EMScheck
	pop cx
	and ax,ax
	jz pvcpi1x
	mov ax,4300h
	mov bx,0001h		;get EMS page to ensure EMM is ON
	int 67h
	and ah,ah
	jnz pvcpi1x
	mov [handle],dx
	dec cl
	jnz @B
pvcpi1x:
	invoke printf, CStr("no VCPI host found",lf)
	jmp pvcpiex
pvcpi1:
	cmp bNoDisp, 0
	jnz @F
	movzx ax,bh
	movzx bx,bl
	invoke printf, CStr("VCPI version: %u.%u",lf),ax,bx
@@:

	call setdescriptors
	push ds
	pop es

if ?386SWAT
;--- the proper sequence of API calls for 386SWAT are
;--- DEF0, DE01 (VCPI get pm interface), DEF2, DEF3

	mov ax,0DEF0h	; returns debugger version in BX
	int 67h
	cmp ah,0
	jnz @F
	mov bKrnlDbg, KD_386SWAT
	jmp kd_done
@@:
endif
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
	jnz de01done
	mov [vcpiofs],ebx
	mov vcpiend,di
	cmp bNoDisp, 0
	jnz de01done
	invoke printf, CStr("Offset of VCPI entry in protected-mode: %08lX",lf),ebx
	movzx edi,di
	shl edi, 10
	invoke printf, CStr("Start free address space: %08lX",lf), edi
	mov di,offset restab
	call getdesc
	invoke printf, CStr("1. VCPI descriptor: %08lX:%04X,%04X",lf), eax, dx, cx
	add di,8
	call getdesc
	invoke printf, CStr("2. VCPI descriptor: %08lX:%04X,%04X",lf), eax, dx, cx
	add di,8
	call getdesc
	invoke printf, CStr("3. VCPI descriptor: %08lX:%04X,%04X",lf), eax, dx, cx
de01done:

	cmp bNoDisp, 0
	jnz noprot

	mov ax,0DE02h		;maxAddr 4K Page
	int 67h
	invoke printf, CStr("highest physical memory address: %08lX",lf),edx

	mov ax,0DE03h		;num free 4K Pages
	int 67h
	cmp ah,0
	jz @F
	movzx ax,ah
	invoke printf, CStr('int 67h, ax=DE03h failed, status AH=%02X',lf),ax
	jmp de03done
@@:
	mov eax,edx
	shl eax,2
	invoke printf, CStr('Free 4K pages: %lu ( %lu kB)',lf), edx, eax
de03done:
	mov ax,0DE07h		;get CR0
	int 67h
	cmp ah,0
	jnz de07done
	invoke printf, CStr("CR0: %08lX",lf),ebx
de07done:
	mov di,offset drtab
	push ds
	pop es
	mov cx,8
	mov eax,-1
	mov dx,di
	rep stosd
	mov di,dx

	mov ax,0DE08h		;get DRx
	int 67h
	cmp ah,0
	jnz de08done
	invoke printf, CStr("DR0-DR3: %08lX %08lX %08lX %08lX",lf), dword ptr es:[di+0],
		dword ptr es:[di+4], dword ptr es:[di+8], dword ptr es:[di+12]
	invoke printf, CStr("DR6+DR7: %08lX %08lX",lf), dword ptr es:[di+24], dword ptr es:[di+28]
de08done:
	mov ax,0DE0Ah		;get interrupt vector mappings
	int 67h
	cmp ah,0
	jnz de0adone
	invoke printf, CStr("Master/Slave PIC base: %X/%X",lf), bx, cx
de0adone:

noprot:
	test flags,PFLAG
	jz @F
	call DispPTEs
@@:
	test flags,UFLAG
	jz @F
	call DispUMBs
@@:
	test flags,PFLAG or RFLAG or NFLAG or UFLAG
	jnz @F
	call pmgo			;--- call protected mode
@@:
	test flags,RFLAG
	jz @F
	call rmfree
@@:
	call protocol
pvcpiex:
	mov dx,[handle]
	and dx,dx
	jz pvcpiex1
	mov ax,4500h		;release the EMS page again
	int 67h
pvcpiex1:
	ret
runvcpi endp

;--- get cmdline parameters

getparm proc near
	mov si,0080h
	mov bl,byte ptr es:[si]
	inc si
	mov bh,0
	mov byte ptr es:[si+bx],0
getp21:
	mov al,es:[si]
	inc si
	and al,al
	jz getp1
	cmp al,'/'
	jz isoption
	cmp al,'-'
	jz isoption
	cmp al,' '
	jbe getp21
	jmp parerr
getp1:
	clc
	ret
isoption:
	mov al,es:[si]
	and al,al
	jz parerr
	inc si
	or al,20h
	mov ah,al
	cmp al,'r'
	jnz @F
	or [flags],RFLAG
	jmp get_hex
@@:
	cmp al,'f'
	jnz @F
	or [flags],FFLAG
	jmp get_hex
@@:
	cmp al,'p'
	jnz @F
	or [flags],PFLAG
	jmp getp21
@@:
	cmp al,'q'
	jnz @F
	or [flags],QFLAG
	jmp getp21
@@:
	cmp al,'n'
	jnz @F
	or [flags],NFLAG
	jmp getp21
@@:
	cmp al,'u'
	jnz @F
	or [flags],UFLAG
	jmp getp21
@@:
	cmp al,'a'
	jnz parerr
	or [flags],AFLAG
	call skipws
	cmp al,'0'
	jb getp21
	jmp get_dec

;--- get a decimal number

get_dec:
	call skipws
	jz parerr
	call getdec
	jc parerr
	and eax, eax
	jz parerr
	mov dwNumPages, eax
	jmp getp21

;--- get a hex number, then a decimal number

get_hex:
	call skipws
	jz parerr
	call gethex
	jc parerr
	mov dwPage, eax
	call skipws
	jz getp21
	cmp al,','
	jnz getp21
	inc si
	call skipws
	jz parerr
	jmp get_dec
parerr:
	stc
	ret
skipws:
	mov al,es:[si]
	and al,al
	jz @F
	inc si
	cmp al,20h
	jbe skipws
	dec si
@@:
	ret
getparm endp

main proc c

	movzx esp,sp

	call getparm
	jnc main_1
	invoke printf, CStr('usage: vcpi [ options ]',lf)
	invoke printf, CStr('    -a <nn>: alloc <1|nn> page(s) in protected mode',lf)
	invoke printf, CStr('    -f page,<nn>: free <1|nn contiguous> page(s) in protected mode',lf)
	invoke printf, CStr('    -n: dont try to switch to protected mode (disables -q -f -a)',lf)
	invoke printf, CStr('    -p: display PTEs for conventional memory',lf)
	invoke printf, CStr('    -q: query num pages in protected mode',lf)
	invoke printf, CStr('    -r page,<nn>: free <1|nn contiguous> page(s) in real-mode',lf)
	invoke printf, CStr('    -u: display regions mapped as UMBs',lf)
	jmp exit
main_1:
	mov al,flags
	and al,AFLAG or FFLAG or RFLAG or UFLAG
	mov bNoDisp,al

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
