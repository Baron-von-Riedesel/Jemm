
;--- Sample how to handle DEVICE_REBOOT_NOTIFY control message;
;--- handles fastboot only.
;--- Requires Jemm v5.86+.

	.386p
	.MODEL FLAT, stdcall
	option casemap:none

	include jlm.inc

DLL_PROCESS_ATTACH equ 1
DLL_PROCESS_DETACH equ 0   

DEVICE_ID equ 4435h

;--- equates from jemm32.inc
REAL_CODE_SEL   equ 4 * 8
REAL_DATA_SEL   equ 5 * 8

	.data

	public ddb

ddb VxD_Desc_Block <0,0,DEVICE_ID,1,0,0,"REBOOT",0, ctrlproc >

	.CODE

ctrlproc proc
	cmp eax, DEVICE_REBOOT_NOTIFY
	jz reboot_notify
@@:
	clc
	ret
reboot_notify:
	test bl,1      ;fastboot flag?
	jz @B

;--- If fastboot is on, one cannot call v86-mode.
;--- IVT vectors have been restored already, VDS bit has been cleared.
;--- So copy 16-bit code to address 07e00h, setup stack and registers
;--- EAX & ECX, finally jump to 7E00h ( still in protected-mode ).

ifdef BOOTDBG
	mov ecx,sizedbgcode
	add ecx,1024-1
	movzx edi,word ptr ds:[413h]
	shl edi,10        ;convert kB to bytes
;--- if already loaded, don't change ds:[413h]
	cmp byte ptr [edi],0E9h  ;jmp near16 opcode?
	jnz adjmem
	movzx eax,word ptr [edi+1]
	cmp dword ptr [edi+eax-1],0DEADBEEFh	;DebugB signature?
	jz @F
adjmem:
	shr ecx,10        ;convert bytes to kB
	sub ds:[413h],cx
	shl ecx,10
	sub edi,ecx
@@:
	mov esi,offset dbgcode
	cld
	rep movsb
endif

	mov edi, 7E00h
	mov esi, offset rmcode
	mov ecx, sizermcode
	cld
	rep movsb
	xor edx, edx
	push edx
	pushw -1
	LIDT FWORD ptr [esp]	; reset the IDT to 0:ffffh
	MOV AX,REAL_DATA_SEL	; before returning to real-mode set the
	MOV DS,EAX				; segment register caches
	MOV ES,EAX
	MOV FS,EAX
	MOV GS,EAX
	MOV SS,EAX				; set SS:ESP
	MOV ESP,7C00h
	MOV ECX,CR0 			; prepare to reset CR0 PE and PG bits
	AND ECX,7FFFFFFEH
	XOR EAX,EAX
	db 66h, 0eah			; jmp far16 20h:7E00h
	dw 7E00h, REAL_CODE_SEL

rmcode label byte
	incbin <fastbrm.bin>
sizermcode equ $ - rmcode

ifdef BOOTDBG
dbgcode label byte
	incbin <debugb.bin>
sizedbgcode equ $ - dbgcode
endif

ctrlproc endp

;--- check for cmdline option /1 /2 /3 /4

Init proc uses esi pParms:ptr JLCOMM
	mov esi,pParms
	mov esi,[esi].JLCOMM.lpCmdLine
	cld
	.while byte ptr [esi]
		lodsb
		.continue .if al == ' ' || al == 9
		.break .if al == 13
		.if al == '/' || al == '-'
			mov al,[esi]
			.if al >= '1' && al <= '4'
				sub al,'0'
				mov rmcode+8,al
				inc esi
			.endif
		.else
			xor eax,eax
			ret
		.endif
	.endw
	mov eax,1
	ret
Init endp

DllMain PROC stdcall hModule:dword, dwReason:dword, dwRes:dword

	mov eax,dwReason
	cmp eax, DLL_PROCESS_ATTACH
	jnz @F
	invoke Init, dwRes
	jmp exit
@@:
	cmp eax,DLL_PROCESS_DETACH
	jnz @F
	mov eax,1
@@:
exit:
	ret
DllMain endp

	END DllMain

