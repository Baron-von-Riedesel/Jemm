
;*** get extended memory status using int 15h
;*** AH=88h
;*** AH=C7h if supported
;*** AX=E801h
;*** AX=E820h

	.286
	.model small
	.386

DGROUP group _TEXT
	.dosseg
	assume ds:dgroup

printf proto c :ptr byte, :VARARG

CStr macro text:VARARG
local sym
	.const
sym db text,0
	.code
	exitm <offset sym>
endm

I15C7S struct
wSize	dw ?
dwLBelow16 dd ?
dwLAbove16 dd ?
dwSBelow16 dd ?
dwSAbove16 dd ?
dwCBelow16 dd ?
dwCAbove16 dd ?
dwXBelow16 dd ?
dwXAbove16 dd ?
wUMB	dw ?
wFree	dw ?
		dd ?
I15C7S ends


	.data?

buffer	db 20h dup (?)
i15c7	I15C7S <?>

	.data
qSum	dq 0
qAvl	dq 0
qACPI	dq 0
qRsvd	dq 0

	.code

	include printf.inc

	.386

;--- display conventional memory size returned by INT 12h

conv_mem proc
	int 12h
	invoke printf, CStr("conventional memory (Int 12h): %u kB",10), ax
	ret
conv_mem endp

;--- call int 15h, ah=C7h (later PS/2 machines, usually fails on newer systems)

I15C0S struct
wBytes    dw ?	;+0
bModel    db ?	;+2
bSubModel db ?	;+3
bBiosRev  db ?	;+4
bFeature1 db ?	;+5
bFeature2 db ?	;+6
bFeature3 db ?
bFeature4 db ?
bFeature5 db ?
I15C0S ends

do_c0c7 proc
	stc
	mov ah,0C0h
	int 15h
	jnc @F
	invoke printf, CStr("Int 15h, ah=C0h failed",10)
	jmp no15c0
@@:
	cmp es:[bx].I15C0S.wBytes,7
	jb no15c0
	mov al,es:[bx].I15C0S.bFeature2
	test al,10h	;int 15h, ah=0C7h supported?
	jz no15c7
	mov ah,0C7h
	mov si,offset i15c7
	int 15h
	jc no15c7
	invoke printf, CStr("Int 15h, ah=C7h:",10)
	invoke printf, CStr("Local memory (1 MB-16 MB/16 MB-4 GB): %08lX/%08lX kB",10),\
		i15c7.dwLBelow16, i15c7.dwLAbove16
	invoke printf, CStr("System memory (1 MB-16 MB/16 MB-4 GB): %08lX/%08lX kB",10),\
		i15c7.dwSBelow16, i15c7.dwSAbove16
	invoke printf, CStr("Cacheable memory (1 MB-16 MB/16 MB-4 GB): %08lX/%08lX kB",10),\
		i15c7.dwCBelow16, i15c7.dwCAbove16
no15c7:
no15c0:
	ret
do_c0c7 endp

;--- print int 15h, ah=88h info

do_88 proc
	clc
	mov ax,8800h
	int 15h
	jnc @F
	invoke printf, CStr("Int 15h, ah=88h failed",10)
	jmp done_88
@@:
	invoke printf, CStr("Int 15h, ah=88h, extended memory: %u kB",10), ax
done_88:
	ret
do_88 endp

;--- print int 15h, ax=e801 info

do_e801 proc
	xor cx,cx
	xor dx,dx
	xor bx,bx
	mov ax,0E801h
	clc			;the carry flag is not reliably set/reset!
	int 15h
	jc error
	and bx, bx
	jnz @F
	and cx, cx
	jnz @F
error:
	invoke printf, CStr("Int 15h, ax=E801h failed",10)
	jmp done_e801
@@:
	.if (!ax)			;some bioses return values in CX:DX
		mov ax, cx
		mov bx, dx
	.endif

	push bx
	push ax
	invoke printf, CStr("Int 15h, ax=E801h:",10)
	pop ax
	.if (ax > 3C00h)
	   invoke printf, CStr("ext. memory below 16 MB: %u (0x%X) KB ???",10), ax, ax
	.else
	   invoke printf, CStr("ext. memory below 16 MB: %u (0x%X) KB",10), ax, ax
	.endif
	pop bx
	mov edx, 1000000h
	mov ax, bx
	movzx ecx, bx
	shl ecx, 16
	add ecx, edx
	dec ecx

	shr ax, 4
	invoke printf, CStr("ext. memory above 16 MB: %u 64 KB blocks = %u MB [%lX-%lX]",10), bx, ax, edx, ecx
done_e801:
	ret
do_e801 endp

SMAP equ 534d4150h

E820MAP struct
baselow  dd ?
basehigh dd ?
lenlow   dd ?
lenhigh  dd ?
type_    dd ?
E820MAP ends

;--- print int 15h, ax=e820 info

do_e820 proc
	push ds
	pop es
	mov si,0
	mov ebx,0
	mov di, offset buffer
	.while (1)
		mov ecx, sizeof E820MAP
		mov edx,"SMAP"
		mov eax,0E820h
		clc
		int 15h
		.break .if CARRY?
		.break .if (eax != "SMAP")
		push ebx
		.if (!si)
			invoke printf, CStr("Int 15h, eax=E820h:",10)
			invoke printf, CStr(" address range          size       type ",10)
			invoke printf, CStr("----------------------------------------------------",10)
			inc si
		.endif
;--- get size in EDX:EAX
		mov eax,[di].E820MAP.lenlow
		mov edx,[di].E820MAP.lenhigh
		mov ecx, [di].E820MAP.type_
		.if (ecx == 1)
			mov cx, CStr("available")
			add dword ptr qAvl+0, eax
			adc dword ptr qAvl+4, edx
		.elseif (ecx == 2)
			mov cx, CStr("reserved")
			add dword ptr qRsvd+0, eax
			adc dword ptr qRsvd+4, edx
		.elseif (ecx == 3)
			mov cx, CStr("ACPI reclaimable")
			add dword ptr qACPI+0, eax
			adc dword ptr qACPI+4, edx
		.elseif (ecx == 4)
			mov cx, CStr("ACPI NVS")
			add dword ptr qACPI+0, eax
			adc dword ptr qACPI+4, edx
		.elseif (ecx == 5)
			mov cx, CStr("bad memory")
		.else
			mov cx, CStr("unknown")
		.endif
		add dword ptr qSum+0, eax
		adc dword ptr qSum+4, edx
		add eax, [di].E820MAP.baselow
		adc edx, [di].E820MAP.basehigh
		sub eax,1
		sbb edx,0
		.if (dword ptr [di].E820MAP.lenhigh)
			invoke printf, CStr("%lX%08lX-%lX%08lX  %lX%08lX  %lX (%s)",10),
				[di].E820MAP.basehigh, [di].E820MAP.baselow, edx, eax,
				[di].E820MAP.lenhigh, [di].E820MAP.lenlow,
				[di].E820MAP.type_, cx
		.else
			invoke printf, CStr("%lX%08lX-%lX%08lX  %9lX  %lX (%s)",10),
				[di].E820MAP.basehigh, [di].E820MAP.baselow, edx, eax,
				[di].E820MAP.lenlow,
				[di].E820MAP.type_, cx
		.endif
		pop ebx
		.break .if (ebx == 0)
	.endw
	.if (!si)
		invoke printf, CStr("Int 15h, eax=E820h failed",10)
	.else
		invoke printf, CStr("----------------------------------------------------",10)
		mov eax,dword ptr qSum+0
		mov edx,dword ptr qSum+4
		mov ecx,100000h
		div ecx
		mov esi, eax
		mov ebx, eax
		mov eax,dword ptr qACPI+0
		mov edx,dword ptr qACPI+4
		mov ecx,400h
		div ecx
		mov ebx, eax
		mov eax,dword ptr qRsvd+0
		mov edx,dword ptr qRsvd+4
		mov ecx,100000h
		div ecx
		mov ebp, eax
		mov eax,dword ptr qAvl+0
		mov edx,dword ptr qAvl+4
		mov ecx,100000h
		div ecx
		invoke printf, CStr("available: %lu MB, ACPI: %lu kB, rsvd: %lu MB, total: %lu MB",10),
			eax, ebx, ebp, esi
	.endif
	ret
do_e820 endp

;--- display location and size of XBDA

xbda proc
	push 40h
	pop es
	mov ax,es:[000Eh]
	and ax,ax
	jz noxbda
	mov es,ax
	mov bl,es:[0]
	mov bh,0
	invoke printf, CStr("XBDA at segment %X, size %u kB",10), ax, bx
	ret
noxbda:
	invoke printf, CStr("no XBDA on this system",10)
	ret
xbda endp

;*** main()

main proc c

	call conv_mem
	call xbda
	call do_c0c7
	call do_88
	call do_e801
	call do_e820
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
	mov sp,bx
	call main
	mov ah,4Ch
	int 21h

	.stack 400h

	END start
