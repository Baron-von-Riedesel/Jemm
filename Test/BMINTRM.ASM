
;--- benchmark
;*** call int 69h a number of times and count timer ticks
;--- jwasm -mz bmintrm.asm

	.286
	.MODEL tiny
	.stack 2048
	.dosseg

cr	equ 13
lf	equ 10

?USERDTSC equ 0

	include macros.inc

	.CODE

	.386
	include printf.inc
ife ?USERDTSC
	.586
	include timerms.inc
endif

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

if ?USERDTSC
	rdtsc
	mov dword ptr dwStartTSC+0,eax
	mov dword ptr dwStartTSC+4,edx
else
	call gettimer
	mov dwStart,eax
endif

	xor esi,esi
@@:
	int 69h
	cmp esi,1000000
	jnz @B

if ?USERDTSC
	rdtsc
	sub eax,dword ptr dwStartTSC+0
	sbb edx,dword ptr dwStartTSC+4
	invoke printf, CStr("TSC diff=%lX%08lX",lf), edx, eax
else
	call gettimer
	sub eax,dwStart
	invoke printf, CStr("time for %lu INTs: %lu ms",lf), esi, eax
endif
	push 0
	pop es
	mov ebx,rmvec
	mov es:[69h*4],ebx
	ret

main endp

intproc:
	inc esi
	iret

start:
	mov ax, cs
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

