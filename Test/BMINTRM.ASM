
;--- benchmark
;*** call int 69h a number of times and count timer ticks

	.286
	.MODEL SMALL
	.stack 2048
	.dosseg
	.586

cr	equ 13
lf	equ 10

	include macros.inc

?USERDTSC equ 0

	.CODE

	include printf.inc

main proc c

local	dwStart:dword
local	rmvec:dword
local	dwStartTSC:qword


	push 0
	pop es
	mov ebx,es:[69h*4]
	mov rmvec,ebx

	mov es:[69h*4+0],offset intproc
	mov es:[69h*4+2],cs

	mov eax,es:[46ch]
	mov dwStart,eax

if ?USERDTSC
	rdtsc
	mov dword ptr dwStartTSC+0,eax
	mov dword ptr dwStartTSC+4,edx
endif
	xor esi,esi
@@:
	int 69h
	cmp esi,1000000
	jnz @B


	mov eax,es:[46ch]
	sub eax,dwStart
	invoke printf, CStr(<"time is %lu, counter is %lu",cr,lf>),eax,esi

if ?USERDTSC
	rdtsc
	sub eax,dword ptr dwStartTSC+0
	sbb edx,dword ptr dwStartTSC+4
	mov dword ptr dwStartTSC+0,eax
	mov dword ptr dwStartTSC+4,edx
	invoke printf, CStr(<"TSC diff=%lX%08lX",cr,lf>),edx,eax
endif

	push 0
	pop es
	mov ebx,rmvec
	mov es:[69h*4],ebx

	ret

main endp

intproc::
	inc esi
	iret

start:
	mov ax, @data
	mov ds, ax
	mov bx, ss
	sub bx, ax
	shl bx, 4
	mov ss, ax
	add sp, bx
	call main
	mov ah, 4Ch
	int 21h

	end start

