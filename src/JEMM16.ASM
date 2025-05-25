
;--- 16 bit part of Jemm;
;--- to be assembled with JWasm or Masm v6.1+

	.286
;	.model tiny		;NO model, _TEXT should be PARA aligned
	option proc:private

	include jemm.inc
	include jemm16.inc
	include debug16.inc
	include xms.inc
if ?KD
	include debugsys.inc
endif

GDT_SIZE equ 200h	; is defined in jemm32.inc

;--- interrupt hook list entry 

INTMOD struct
bInt	db ?
wNew	dw ?
wOld	dw ?
INTMOD ends

MCB struct
sig db ?
psp dw ?
blsiz dw ?
MCB ends

IRET16 struct
wIP dw ?
wCS dw ?
wFL dw ?
IRET16 ends

;--- @DefineBP: macro to define a v86-"breakpoint"

@DefineBP macro _name
_name&::
	@BPOPC
endm

CStr macro text:VARARG
local sym
CONST segment
sym db text,0
CONST ends
	exitm <offset sym>
endm

_TEXT segment para public 'CODE'
_TEXT ends

_TEXT32 segment para public 'CODE'
code32:
ifdef __JWASM__ ;JWasm allows to include binary data directly
	incbin <jemm32.bin>
;	align 16
else
	.nolist
	include _jemm32.inc
	.list
endif
_TEXT32 ends

_DATA segment word public 'DATA'

wLow    dw RSEG_END     ;resident low memory required by driver

;--- _brptab is the second of two parameters for Jemm32 init
;--- the entries are offsets in RSEG
;--- the most important one is the offset to the v86 breakpoint table

if ?HOOK13
_brptab RSOFS < RSEG_END, bptable, bRFlags >
else
_brptab RSOFS < RSEG_END, bptable >
endif

if 0;?A20PORTS
wBiosA20    DW 1+2  ;default: trap both kbdc + ps2 ports
endif

_DATA ends

CONST segment word public 'CONST'
intvecs label INTMOD
	INTMOD <15h,offset NEW15, offset OLDINT15>
if ?INTEGRATED
	INTMOD <2Fh,offset NEW2F, offset OLDINT2F>
endif
if ?HOOK13
	INTMOD <13h,offset NEW13, offset OLDINT13>
	INTMOD <40h,offset NEW40, offset OLDINT40>
endif
	INTMOD <67h,offset NEW67, -1>
	INTMOD <06h,offset NEW06, -1>
	INTMOD <19h,offset NEW19, -1>
	db -1

CONST ends

_BSS segment word public 'BSS'
_BSS ends

_STACK segment para STACK  'STACK'
	db 1024 dup(?)		; application stack
stacktop label byte
_STACK ends

DGROUP group _TEXT,_TEXT32,_DATA,CONST,_BSS,_STACK

	.386P	;privileged instructions are used

_TEXT SEGMENT

	ASSUME DS:NOTHING,ES:NOTHING,FS:ERROR,GS:ERROR

;*************************************************************************
; device driver header

device_header:
	dd -1				; last driver in list
	dw 0c000h			; driver flags :
						; 8000 - character device
						; 4000 - supports IOCTL - like EMM386
pStratOfs dw offset strategy	; offset to strategy routine
pIntOfs dw offset driver_entry	; offset to interrupt handler

device_name label byte
	db	'EMMXXXX0'		; device driver name

;--- start of real-mode resident data area

;--- v86 breakpoint table
;--- the order must match the one of bptable in Jemm32.asm !

bptable label byte
NEW06:					; entry invalid opcode exception (int 06)
	@DefineBP BP06
NEW19:
	@DefineBP BP19
NEW67:					; int 67h entry real-mode
	@DefineBP BP67
if ?VDS
NEW4B:					; int 4Bh entry v86-mode (VDS)
	@DefineBP BPVDS
endif
	@DefineBP BPBACK	; BP to return to v86 monitor from a v86 far proc
	@DefineBP BPI1587
if ?HOOK13
	@DefineBP BP1340	; copy out of DMA buffer
endif
	@DefineBP BPXMS 	; handle XMS A20+UMB
	@DefineBP BPSTRAT	; EMMXXXX0 device strategy call
	@DefineBP BPDRV 	; EMMXXXX0 device interrupt call
if ?UNLOAD
	@DefineBP BPRESET	; unload
endif

if ?HOOK13

bRFlags DB 0			; bit 0: 1=copy out of DMA buffer ; bit 1: 1=new DMA op started

;--- for DMA, hook int 40h (FD access)
;--- and int 13h (HD access)

NEW40 PROC FAR
	mov cs:[bRFlags],RFL_DMAOP	; tell the monitor that a new DMA op has started
	pushf
	db 09Ah
OLDINT40 dd 0
	jmp int1340common
NEW40 ENDP

	align 4

NEW13 PROC FAR
	mov cs:[bRFlags],RFL_DMAOP	; tell the monitor that a new DMA op has started
	pushf
	db 09Ah
OLDINT13 dd 0
NEW13 ENDP

int1340common:
	jc iret_with_new_CY
	test cs:[bRFlags],RFL_COPYBUFFER
	jnz BP1340			; breakpoint int 13/40h: copy out of DMA buffer
iret_with_new_CY:
	push bp
	mov bp,sp
	rcr byte ptr [bp+2].IRET16.wFL,1
	rol byte ptr [bp+2].IRET16.wFL,1
	pop bp
	iret

endif

;******************************************************************************
; INT15 handler:
;    handle AH=87h case (copy extended memory)
;
;        AH = 87h
;        CX = number of words to copy (max 8000h)
;        ES:SI -> GDT (4 descriptors)
;Return: CF set on error, else cleared
;        AH = status (00 == ok)
;
; For JemmEx, also handle ah=88h (get extended memory size)
; If XMS v3.5 is supported, ax=E820h must also be intercepted.
;******************************************************************************

	align 4

NEW15 PROC FAR

;--- int 15h handlers "should" preserve CF
;--- it's not done here, because CF will be set if ah=4Fh (keyboard)

	CMP AH,87H		; is it the blockmove?
	JZ BPI1587
if ?INTEGRATED
	CMP AH,88H		; ext memory size
	JZ getextmem
 if ?XMS35
	CMP AX,0E820h	; memmap
	JZ memmap
xms_smax_noe820 equ $ - 1
 endif
endif
	db 0EAh
OLDINT15 dd 0
if ?INTEGRATED
getextmem:
	xor ax,ax			; no memory available
exit_iret:
  ife ?HOOK13
	push bp
	mov bp,sp
	and byte ptr [bp+2].IRET16.wFL,not 1  ;clear CF
	pop bp
	iret
  else
	jmp iret_with_new_CY
  endif
 if ?XMS35
memmap:
	pushf
	call cs:[OLDINT15]
	jc iret_with_new_CY
	cmp eax,SMAP
	jnz exit_iret
	cmp es:[di].E820MAP.basehigh,0
	jz exit_iret
	cmp es:[di].E820MAP.type_,1		;"available" memory?
	clc
	jnz exit_iret
	mov byte ptr es:[di].E820MAP.type_,2		;change to "reserved"
	jmp exit_iret
 endif
endif
NEW15 ENDP

;*********************************************************
; XMS hook - required for UMBs and A20 emulation
;*********************************************************

	align 4

XMShandler proc

	jmp short @@XMSHandler	; standard XMS link chain
	nop 					; with 3 required NOPs
	nop
	nop
@@XMSHandler:
if ?INTEGRATED
	jmp BPXMS
else

;-- for A20 disable and enable emulation it is required to hook
;-- the XMS functions as well, even if the A20 ports (92, 60, 64)
;-- are trapped. That's because if certain conditions are true
;-- the XMS host will never access the ports and leave A20 unchanged.

if ?A20XMS
	cmp ah,3
	jb	@@noa20
	cmp ah,6
	jbe BPXMS
@@noa20:
endif

XMSUMB::
	cmp ah,10h			; 10h=alloc, 11h=free, 12=realloc
	jb	@@xms_prev
	cmp ah,12h
	jbe BPXMS
@@xms_prev:
	db 0eah 			; jmp far XMS prev handler
XMSoldhandler dd 0
endif

XMShandler endp

if ?INTEGRATED

NEW2F proc
	pushf
	cmp ah,43h
	jz is43
@@jmp_old2f:
	popf
	db 0EAh
OLDINT2F dd 0
is43:
	cmp al,00h			; is it "Installation Check"?
	je @@get_driver_installed
	cmp al,10h			; is it "Get Driver Address"?
	je @@get_xms_address
	cmp al,09h			; is it "get handle table"?
	je @@get_xms_handle_table
	cmp al,08h
	jne @@jmp_old2f
	mov al,ah		;al==43h if function supported
machine_type label byte    
	mov bx,0002 	; bh=switch time; 0=medium, 1=fast, 2=slow
					; bl=machine type; 1=std AT (KBC), 2=PS/2 (port 92) ?
	popf
	iret
@@get_driver_installed:
	mov al,80h		; yes, we are installed ;)
	popf
	iret
@@get_xms_address:
	mov bx,offset XMShandler
@@shared2f:
	push cs
	pop es
	popf
	iret
@@get_xms_handle_table:
	mov al,ah		;al==43h if function supported
	mov bx,OFFSET xms_handle_table
	jmp @@shared2f

NEW2F endp
endif

if ?RMDBG

	include dprntf16.inc

endif

if ?INTEGRATED

	align 2

?EXTRAHDL equ 0

xms_handle_table XMS_HANDLETABLE <01, size XMS_HANDLE, 0, xms_handle_array>
xms_handle_array XMS_HANDLE ?XMS_STATICHDLS+1+?EXTRAHDL dup (<XMSF_INPOOL,0,0,0>)
	db XMSF_INPOOL

endif
	align 16

RSEG_END equ $ - device_header

;
; installation part of the virtual Monitor
;

	assume DS:DGROUP;, ES:SEG0000

if ?UNLOAD

CheckIntHooks proc stdcall public uses es si di wResSeg:WORD

	mov ax, wResSeg
	shl eax, 16
	push 0
	pop es
	mov si,offset intvecs
@@nextvect:
	lodsb
	cmp al,-1
	jz @@ok
	movzx di,al
	shl di,2
	lodsw
	scasd
	stc
	jnz @@nouninst
	add si,2
	jmp @@nextvect
@@ok:
if ?VDS
	test byte ptr es:[47Bh],20h
	jz @F
	mov ax,offset NEW4B
	cmp eax,es:[4Bh*4]
	stc
	jnz @@nouninst
	@dprintf ?UNLRMDBG, <"CheckIntHooks: int 4Bh is ok",10>
@@:
endif
	clc
@@nouninst:
	ret
CheckIntHooks endp

;--- Jemm can be unloaded. Do it!
;--- in: AX=segment of resident part of installed Jemm
;--- out: C=error, NC=ok. 
;--- may change all GPRs except BP/SP.

UnloadJemm proc c public

	mov di,ax

	@dprintf ?UNLRMDBG, <"UnloadJemm enter, res. segm=%X CS=%X SS:SP=%X:%X",10>, di, cs, ss, sp

;--- remove EMMXXXX0 from driver chain

	mov ah,52h			;get start of driver chain
	int 21h
	add bx,22h
@@nextdev:
	cmp di, es:[bx+2]
	jz @@found
	les bx, es:[bx]
	cmp bx,-1
	jnz @@nextdev
	stc
	ret
@@found:
	mov ds,di
	mov ecx, ds:[0]    ;remove driver from chain
	mov es:[bx], ecx

	@dprintf ?UNLRMDBG, <"UnloadJemm: driver removed from chain",10>

;--- reset IVT vectors

	mov es,di
	push 0
	pop ds
	mov si, offset intvecs
@@nextvec:
	lodsb cs:[si]
	cmp al,-1
	jz @@ok
	movzx bx,al
	shl bx, 2
	mov di,cs:[si+2]
	cmp di,-1
	jz @@skipvec
	mov ecx, es:[di]
	mov [bx],ecx
@@skipvec:
	add si,4
	jmp @@nextvec
@@ok:
	@dprintf ?UNLRMDBG, <"UnloadJemm: IVT vectors restored",10>

;--- reset XMS hook

ife ?INTEGRATED
	mov bx,offset XMSoldhandler
	mov ecx, es:[bx]
	and ecx, ecx
	jz @@noxms

	push es
	push es
	pop ds
	mov si,offset XMShandler
	push ecx
	pop di
	pop es
	mov cx,5
	sub di,cx
	rep movsb
	pop es
@@noxms:
	@dprintf ?UNLRMDBG, <"UnloadJemm: XMS hook removed",10>

endif

if ?KD
;--- call int 68h if kernel debugger installed.
;--- if the installed instance didn't initialize the kd, nothing is to be done here!
	mov ax,es
	sub ax,10h
	mov ds,ax
	test byte ptr ds:[7fh], 1
	jz @F
	mov ah, D386_Real_Mode_Init
	int D386_RM_Int
@@:
endif

;--- make sure jemm386's resident memory block is freed
;--- this is to be improved yet

	mov ax,es
	sub ax,10h+1	;size PSP + 10h (to get MCB)
	mov ds,ax
	mov cx,ax
	inc cx
	mov al,ds:[0]
	cmp al,'M'
	jz @@ismcb
	cmp al,'Z'
	jnz @@nopsp
@@ismcb:
	cmp cx,ds:[1]
	jnz @@nopsp
ife ?INTEGRATED
	cmp word ptr ds:[3],10h + RSEG_END/10h
	jnz @@nopsp
else
	cmp word ptr ds:[10h+18h],-1	;check if files 0+1 are closed
	jnz @@nopsp
endif
	cmp word ptr ds:[10h],20CDh
	jnz @@nopsp
	mov ax,cs
	sub ax,10h
	mov ds:[1],ax
@@nopsp:
	@dprintf ?UNLRMDBG, <"UnloadJemm: resident segment prepared to be released",10>

;--- now call the installed instance of Jemm386 to
;--- do the rest of the clean-up

	push bp
	mov bp,sp
	pushd 0
	push 3FFh
	push es
	push offset BPRESET
	call dword ptr [bp-(4+6)]

;--- Jemm386 has exited, but we are still in protected mode!
;--- GDTR no longer valid, IDTR reset to 3FF:00000000
;--- for Jemm386, BX contains XMS handle for Jemm386's memory block
;--- for JemmEx, BL contains A20 method index

	mov eax, cr0
	and eax, 7FFFFFFEh	;disable paging and protected-mode
	mov cr0, eax
;--- v5.86: for 80486 compatibility, use a JMP far16 instead of RETF
	db 0EAh				;jmp FAR16 opcode
	dw offset @F,seg @F
@@:
	LIDT FWORD ptr [bp-6]; reset IDT to 0:3ffh (v5.86: now done AFTER mode switch)
if 1
	xor eax,eax	;v5.86: clear TLB
	mov cr3,eax
endif
	mov sp,bp
	pop bp
	mov ax,cs	;v5.86: assume model TINY
	mov ss,ax
	mov ds,ax
	mov es,ax
	sti
	@dprintf ?UNLRMDBG, <"UnloadJemm: back from protected-mode",10>
	@dprintf ?UNLRMDBG, <"UnloadJemm exit",10>
	mov ax,bx
	clc
	ret
UnloadJemm endp

endif

; check, if this program runs after all on a 386-Computer (o.ae.)
; (... you never know)

Is386 PROC NEAR
	PUSHF
	mov AX,7000h
	PUSH AX
	POPF				; on a 80386 in real-mode, bits 15..12
	PUSHF				; should be 7, on a 8086 they are F,
	POP AX				; on a 80286 they are 0
	POPF
	and ah,0F0h
	cmp AH,70H
	stc
	JNZ @F
	clc
@@:
	RET
Is386 ENDP

;--- test if CPU is 386, display error if not
;--- returns C and modifies DS in case of error
;--- other registers preserved

TestCPU proc near
	push ax
	call Is386
	jnc @F
	push dx
	push cs
	pop ds
	mov ah,9
	mov dx,offset dErrCpu
	int 21h
	pop dx
	stc
@@:
	pop ax
	ret
TestCPU endp

dErrCpu  db NAMEMOD,": at least a 80386 cpu is required",13,10,'$'

request_ptr dd 0

;--- the original strategy proc, must be 8086 compatible
;--- will be replaced by a v86 BP once Jemm386 is installed

strategy:
	mov word ptr cs:[request_ptr+0],bx
	mov word ptr cs:[request_ptr+2],es
	retf

;**********************************************
; driver init part
; this code is only necessary on init and
; will not go resident. It must however be
; in the same physical segment as the
; resident part. The proc must be declared far.
;**********************************************

req_hdr struct
req_size db ?	;+0 number of bytes stored
unit_id  db ?	;+1 unit ID code
cmd 	 db ?	;+2 command code
status	 dw ?	;+3 status word
rsvd     db 8 dup(?);+5 reserved
req_hdr ends

init_req struct
	req_hdr <>
units	 db ?	;+13 number of supported units
endaddr  dd ?	;+14 end address of resident part
cmdline  dd ?	;+18 address of command line
init_req ends

driver_entry proc far

	push ds
	push di
	lds di, cs:[request_ptr]	; load address of request header
	mov [di].req_hdr.status,8103h
	cmp [di].req_hdr.cmd,0		; init cmd?
	jne @@noinit
	call TestCPU
	jnc @@cpuok
@@noinit:
	pop di
	pop ds
	ret
@@cpuok:
	mov [di].req_hdr.status,0100h	; set STATUS_OK
	pushad
	mov cx,ss
	mov bx,sp
	mov ax, cs
	mov ss, ax
	mov sp, offset stacktop
	push cx
	push bx
	push es
	push ds
	push di
	les si, [di].init_req.cmdline
	mov ds, ax
	call EmmInstallcheck
	jnc @F
	xor ax,ax
	jmp @@driver_exit
@@:
	add sp,-128
	mov di,sp
	push ds
	push es
	pop ds
	push ss
	pop es

	cld
if 0
	push si
nextchar:
	lodsb
	cmp al,0
	jz donex
	cmp al,13
	jz donex
	cmp al,10
	jz donex
	mov dl,al
	mov ah,2
	int 21h
	jmp nextchar
donex:
	mov dl,13
	mov ah,2
	int 21h
	mov dl,10
	mov ah,2
	int 21h
	pop si
endif

@@nxtchar1: 			;skip program name
	lodsb
	and al,al
	jz done
	cmp al,13
	jz done
	cmp al,10
	jz done
	cmp al,20h
	ja @@nxtchar1
@@nxtchar2:
	lodsb
	and al,al
	jz done
	cmp al,13
	jz done
	cmp al,10
	jz done
	stosb
	jmp @@nxtchar2
done:
	mov al,0
	stosb
	pop ds
	push sp
	push EXECMODE_SYS
	call mainex
	add sp,128+2+2
;	MOV DX,OFFSET dFailed
	or ax,ax			; error occured?
	mov ax,0
	jnz @@driver_exit
	mov ax, [wLow]
@@driver_exit:
	pop di
	pop ds
	pop es
	mov word ptr [di].init_req.endaddr+0,ax	; if ax == 0, driver won't be installed
	mov word ptr [di].init_req.endaddr+2,cs	; set end address
	pop bx
	pop ss
	mov sp,bx
	popad
	pop di
	pop ds
	ret

driver_entry ENDP

if ?LOAD

;--- check if there is already an EMM installed
;--- DS=DGROUP
;--- out: NC=no Emm found

EmmInstallcheck proc c public
	push es
	pusha
	MOV AX,3567H		; get INT 67h
	INT 21H
	MOV AX,ES			; EMM already installed ?
	OR AX,BX
	JZ @@ok
	MOV DI,10
	MOV SI,OFFSET sig1
	CLD
	MOV CX,8
	REPZ CMPSB
	je @@error			; matched 1st ID string
	mov di, 10			; didn't match, check 2nd ID (NOEMS version)
	mov si, OFFSET sig2
	mov cl, 8
	repz cmpsb
	clc
	jne @@ok			; did match 2nd ID string?
@@error:
	mov dx, CStr('An EMM is already installed',CR,LF,07,'$')
	mov ah, 9
	int 21h
	stc
@@ok:
	popa
	pop es
	ret
EmmInstallcheck endp

endif

;*********************************************
; startpoint when executing as EXE
;*********************************************

start proc

	mov ax,cs
	mov ss,ax
	mov sp, offset stacktop - 128
	call TestCPU
	jc @@exit
	@dprintf ?INITRMDBG, <"Jemm386 enter",10>

	mov di,sp
	mov si,0080h
	lodsb
	movzx cx,al
	push ss
	pop es
	rep movsb
	mov al,0
	stosb
	push ss
	pop ds

	push sp
	push EXECMODE_EXE
	call mainex		;returns 0 if everything ok
	add sp,128+2+2

if ?LOAD
	and ax,ax		;error occured?
	jnz @@exit
	cmp [wLow],0	;did we move high?
	jz @@exit
	call LinkChain	;link driver in chain for .EXE
	mov ah,51h
	int 21h
	mov es,bx
	mov es,es:[002Ch]
	mov ah,49h
	int 21h
	mov bx,0
@@nextfile:
	mov ah,3Eh
	int 21h
	inc bx
	cmp bx,5
	jb @@nextfile
	mov dx,[wLow]
	shr dx, 4
	add dx, 10h
	mov ax,3100h
	int 21h
endif

@@exit:
	@dprintf ?INITRMDBG, <"Jemm386 exit",10>
	mov ah,04ch 		; that was all
	int 21h
start endp

;--- monitor installation
;--- in: CS=SS=DS=DGROUP
;--- si=mode
;--- out: EAX=first page used for EMS/VCPI

InitJemm PROC c public

	push si
	push di
	push bp
	mov bp, sp		;mode is at [bp+4]

if 0; ?A20PORTS 	;this info is unreliable, don't activate!
	mov ax,2403h	;get A20 gate support
	int 15h
	cmp ah,00		;ignore carry flag, it is not reliable
	jnz @F
	mov wBIOSA20,bx
@@:
endif

if ?INTEGRATED

;--- the xms handle table must be located in the resident conventional memory
;--- part of jemmex

	mov cx, xms_num_handles		;is at least 8
	mov [xms_handle_table.xht_numhandles], cx
	mov ax,size XMS_HANDLE
	mul cx
	add ax,offset xms_handle_array + 15	;adjust to paragraph
	and al,0F0h
	mov [_brptab.wSizeRes],ax
endif

;--- store interrupt vectors in resident memory

	mov si,offset intvecs
@@nextint:
	mov al,[si].INTMOD.bInt
	cmp al,-1
	jz @@intmoddone
	mov di,[si].INTMOD.wOld
	cmp di,-1
	jz @@nooldsave
	mov ah,35h
	int 21h
	mov cs:[di+0],bx
	mov cs:[di+2],es
@@nooldsave:
	add si,size INTMOD
	jmp @@nextint
@@intmoddone:

;-- set new interrupt routine offset in the driver header, so any further
;-- access to device EMMXXXX0 is handled by the monitor

	mov [pIntOfs],offset BPDRV
	mov [pStratOfs],offset BPSTRAT

if ?KD

;--- check for kernel debugger presence.
;--- issue INT 68h, ah=43h and if debugger responds,
;--- tell it about certain GDT selectors and get the
;--- protected-mode entry.

	mov ax,3500h or D386_RM_Int
	int 21
	mov ax, es		; int 68h vector 0000:0000?
	or ax, bx
	jz @F
	mov si, word ptr [code32+5]	; DS:SI=GDT
	mov eax, ds
	shl eax, 4
	movzx esi, si
	add eax, esi
	mov [si+GDT_SEL+2], ax
	shr eax, 16
	mov [si+GDT_SEL+4], al
	mov [si+GDT_SEL+7], ah

	mov ah, D386_Identify
	int D386_RM_Int
	cmp ax, D386_Id
	jnz @F
	@dprintf ?INITRMDBG, <"InitJemm: kernel debugger detected",10>
	mov ah, D386_Prepare_PMode
	mov al, 0
	mov cx, GDT_SEL+8
	mov bx, FLAT_DATA_SEL
	mov dx, GDT_SEL
	mov di, -1 					; ES:DI=IDT ( there's no IDT yet in Jemm! )
	int D386_RM_Int
	mov jemmini.kdofs, edi
	mov jemmini.kdseg, es
	@dprintf ?INITRMDBG, <"InitJemm: kernel debugger pm entry: %X:%lX",10>, es, edi
	cmp word ptr [bp+4], EXECMODE_EXE
	jnz @F
	mov ah, 51h
	int 21h
	mov es, bx
	or byte ptr es:[7fh], 1		; use PSP:7Fh as "kd flag" (if jemm is loaded as .EXE)
@@:
endif

;--- prepare running Jemm32.
;--- build an IRETDV86 struct on the stack.

	mov dx,sp
	and sp,not 3	; ensure the 32-bit stack is dword aligned
	xor ax,ax
	push ax
	push gs	; IRETDV86._Gs
	push ax
	push fs	; IRETDV86._Fs
	push ax
	push ds	; IRETDV86._Ds
	push ax
	push es	; IRETDV86._Es
	push ax
	push ss	; IRETDV86._Ss
	push ax
	push dx	; IRETDV86._Esp
	pushd 20002h or ( V86IOPL shl 12 ) ;IRETDV86.vEFL (VM=1, NT=0, IF=0) IOPL=3
	push ax
	push cs	; IRETDV86._Cs
	push ax
	push offset backinv86	; IRETDV86._Eip
	movzx ebp,sp

;--- set a GDTR on the stack

	mov dx,ds
	movzx edx,dx
	shl edx,4
	movzx eax, word ptr [code32+5]	; get offset GDT from jemm32.bin
;--- set register parameters for 32-bit monitor init
	lea edi, [edx+offset jemmini]
	lea ebx, [edx+offset _brptab]
	lea esi, [edx+offset code32]
	add eax, esi

	push eax
	push GDT_SIZE-1
	CLI
	LGDT FWORD PTR [bp-6]
	add sp, 2+4

FLAT_CODE_SEL equ 1*8
FLAT_DATA_SEL equ 2*8

	MOV EAX,CR0 			; Set PE-Bit in CR0
	OR AL,1
	MOV CR0,EAX

	add EBP, EDX			; EBP = flat address of SS:SP

	XOR AX,AX
	LLDT AX 				; initialise LDT (it is not used)
	mov FS,AX
	mov GS,AX
	MOV AL,FLAT_DATA_SEL	; Addressing everything
	MOV DS,AX
	MOV ES,AX
	mov SS,AX
	mov ESP,EBP 	;--- SS:ESP -> IRETDV86 struct
	pushd FLAT_CODE_SEL
	push esi
	retd

backinv86:

;--- the remaining commands are executed in v86-mode
;--- the virtual monitor init code has returned with
;--- CS, DS, ES, SS, FS, GS = unchanged
;--- SP -> "behind" IRETDV86
;--- EAX = physical address of start of EMS/VCPI memory
;--- interrupts are still disabled

	push eax				; FIRSTPAGE value

	@dprintf ?INITRMDBG, <"InitJemm: V86 mode entered",10>

	call GetRes		;get Jemm resident part
	mov bx,ax
	push es
if ?INTEGRATED
	mov es,bx
	mov word ptr es:[xms_handle_table.xht_pArray+2],bx
	mov word ptr [XMSdriverAddress+2],bx	;v5.80 adjust XMS address
endif
if ?VDS
	push 0
	pop es
	mov ax,cs
	cmp ax,word ptr es:[4Bh*4+2]
	jnz @@novds
	mov es:[4Bh*4+2],bx
@@novds:
endif
	pop es

	sti

	@dprintf ?INITRMDBG, <"InitJemm: ints enabled, hooking int 15h, 2Fh, ...",10>
	mov si,offset intvecs
@@nextint2:
	mov al,[si].INTMOD.bInt
	cmp al,-1
	jz @@intmoddone2
	mov ah,25h
	mov dx,[si].INTMOD.wNew
	push ds
	mov ds,bx
	int 21h
	pop ds
	add si,size INTMOD
	jmp @@nextint2

@@intmoddone2:

	call endinit

ife ?INTEGRATED
	@dprintf ?INITRMDBG, <"InitJemm: calling InstallXMSHandler",10>
	call InstallXMSHandler
 if ?MOVEXBDA and not ?MOVEXBDAPM
	call move_xbda ;must be called after InstallXMSHandler
 endif
endif

	pop eax  ;load FIRSTPAGE value in EAX

	pop bp
	pop di
	pop si
	ret

InitJemm ENDP

;--- get Jemm resident segment address
;--- may not be CS if Jemm has been moved in an UMB

GetRes proc
	mov ax,jemmini.ResUMB
	and ax,ax
	jz @F
	ret
@@:
	mov ax,cs
	stc
	ret
GetRes endp

;--- end of initialization
;--- 1. init XMS handle table for integrated version
;--- 2. link resident part in driver chain if moved high

endinit proc

if ?INTEGRATED

;--- initialize XMS handles which haven't been set yet

	call GetRes	;get Jemm resident segment address
	mov es,ax
	mov di, offset xms_handle_array
	mov cx, xms_num_handles
	mov ax, sizeof XMS_HANDLE
	mul cx
	add ax,di
	mov cx,ax
	.while es:[di].XMS_HANDLE.xh_flags != XMSF_INPOOL 
		add di, sizeof XMS_HANDLE
	.endw
	.while di < cx
		mov ax, XMSF_INPOOL
		stosw
		xor eax, eax
		stosd
		stosd
	.endw
	mov ax, di
	add ax, 16-1
	and al, 0F0h
	mov [wLow], ax
endif

if ?INTEGRATED
 if ?MOVEXBDA and not ?MOVEXBDAPM
	call move_xbda
 endif
endif

if ?ADDCONV

;--- if conventional memory has been increased (i.e. by I=A000-B7FF),
;--- increase last DOS MCB
	mov ah,52h		;get LoL
	int 21h
	mov si, es:[bx-2]
nextitem:
	mov es, si
	mov dx, es:[MCB.blsiz]	;get size of MCB
	inc dx
	add dx, si		;dx = next block
	cmp byte ptr es:[MCB.sig], 'M'
	jnz @F
	mov si, dx
	jmp nextitem
@@:
	push ds
	push 0
	pop ds
	mov ax,ds:[@MEM_SIZE]
	pop ds
	shl ax,6	;kB to paragraphs

;--- v5.80: do jmp even if ax = dx+1
;--- this might be the case if UMBs are already included?
;--- if UMBs are already included, the last low-mem DOS MCB
;--- should NOT be increased!
	inc dx

	cmp ax,dx
	jbe noconv_increased	;do nothing if BIOS mem is lower or equal
	sub ax, si
	dec ax
	mov es:[MCB.blsiz],ax
noconv_increased:
endif

if ?MOVEHIGH
	call GetRes
	jc @F               ;if carry set, we didn't move high
	mov [wLow],0		;add the EMMXXXX0 driver to the driver chain
	call LinkChain		;if we moved high
@@:
endif
	ret
endinit endp

if ?MOVEXBDA and not ?MOVEXBDAPM
move_xbda proc
	test jemmini.V86Flags,V86F_MOVEXBDA
	jz nomovexbda
	push 0
	pop es
	mov ax,es:[@XBDA]
	mov dx,es:[@MEM_SIZE]
	@dprintf ?INITRMDBG, <"move_xbda: xbda seg=%X, convmem=%X kb",10>, ax, dx
	shl dx,6
	cmp ax,dx		;XBDA must be just above conventional memory
	jnz nomovexbda	;else it a) has been moved already b) doesn't exist
	mov es,ax
	movzx si,byte ptr es:[0]	;byte 0 of XBDA contains size in kB
	shl si,6		;convert kb to para
	mov dx,si
	mov ah,XMS_ALLOCUMB	;alloc UMB
	call [XMSdriverAddress]
	cmp ax,1
	jnz nomovexbda
	@dprintf ?INITRMDBG,<"move_xbda: alloc umb ok, seg=%X",10>, bx
;--- copy content of XBDA to new location
	mov es,bx
	pushf
	cli
	push ds
	push 0
	pop ds
	xchg bx,ds:[@XBDA]	;set new location of XBDA
	mov ax,si
	shr ax,6	;convert para to kb
	add word ptr ds:[@MEM_SIZE],ax
	mov ds,bx
	mov cx,si
	shl cx,3    ;convert para to word
	push si
	xor si,si
	xor di,di
	rep movsw
	pop si
	pop ds
	popf

;--- get last MCB and increase its size by size of XBDA
	mov ah,52h
	int 21h
	mov ax, es:[bx-2]
nxtitem:
	mov es, ax
	mov dx, es:[MCB.blsiz]	;get size of MCB
	inc dx
	add dx, ax		;dx = next block
	cmp es:[MCB.sig], 'M'
	jnz @F
	mov ax, dx
	jmp nxtitem
@@:
	add es:[MCB.blsiz],si

	cmp bVerbose,0
	jz @F
	invoke printf,CStr("XBDA moved to first UMB",10)
@@:
nomovexbda:
	ret
move_xbda endp
endif

LinkChain proc
	mov ah,52h
	int 21h
	push ds
	push 0
	pop ds
	mov ax,ds:[67h*4+2]
	mov ds,ax
	add bx,22h
	shl eax,16
	xchg eax,es:[bx]
	mov ds:[0],eax
	pop ds
	ret
LinkChain endp

ife ?INTEGRATED

;--- InstallXMSHandler

InstallXMSHandler proc
ife ?A20XMS 					;if there is no XMS A20 trapping
	cmp jemmini.NumUMBs,0		;XMS hook is needed *only* for UMBs.
	jz @@umbdone				;dont install if no UMBs are supplied
endif
	@dprintf ?INITRMDBG, <"InstallXMSHandler: getting XMS UMB status",10>
	mov dx, -1
	mov ah, XMS_ALLOCUMB
	call [XMSdriverAddress]
	and ax, ax
	jnz @@umbalreadythere
	@dprintf ?INITRMDBG, <"InstallXMSHandler: hooking into XMS driver chain",10>
	les bx,[XMSdriverAddress]
@@nexttest:
	mov al,es:[bx]
	cmp al,0EBh
	jz @@endofchain
	les bx,es:[bx+1]
	cmp al,0EAh
	jz @@nexttest
;--- unexpected pattern found in XMS hook chain
	@dprintf ?INITRMDBG, <"InstallXMSHandler: unexpected pattern found in XMS hook chain",10>
	jmp @@umbdone
@@endofchain:
	@dprintf ?INITRMDBG, <"InstallXMSHandler: end of chain found",10>
	cli
	mov byte ptr es:[bx+0],0EAh
	mov word ptr es:[bx+1],offset XMShandler
	mov cl,jemmini.NumUMBs
	push ds
if ?MOVEHIGH
	push 0
	pop ds
	mov ax,ds:[67h*4+2]
else
	mov ax, cs
endif
	mov es:[bx+3], ax
	add bx,5
	mov ds, ax
	assume DS:_TEXT
	mov word ptr ds:[XMSoldhandler+0],bx
	mov word ptr ds:[XMSoldhandler+2],es
if ?A20XMS
	cmp cl,0
	jnz @@xmswithumb
	mov byte ptr ds:[XMSUMB], 0EAh	;skip UMB code if no UMBs are supplied
	mov word ptr ds:[XMSUMB+1], bx
	mov word ptr ds:[XMSUMB+3], es
@@xmswithumb:
endif
	pop ds
	assume DS:DGROUP
	sti
	jmp @@umbdone
@@umbalreadythere:
	mov dx, CStr("UMB handler already installed, not installing another one",CR,LF,'$')
	mov ah,9
	int 21h
@@noxms:
@@umbdone:
	ret
InstallXMSHandler endp

endif

;--- init XMS
;--- for the integrated version, init some variables
;--- for the EMM-only version, ensure that an XMS host is found

XMSinit proc c public uses es
	mov ax, 4300h
	int 2fh
	cmp al, 80h
	jne @@not_detected
	mov ax, 4310h
	int 2fh
	mov word ptr [XMSdriverAddress+0], bx
	mov word ptr [XMSdriverAddress+2], es

	mov ax, 4309h		;  XMS get xms handle table
	int 2fh
	cmp al,43h
	jne @@no_table
	mov word ptr jemmini.XMSHandleTable+0, bx
	mov word ptr jemmini.XMSHandleTable+2, es
@@no_table:
	mov ax,1
	ret
@@not_detected:
if ?INTEGRATED
	mov word ptr [XMSdriverAddress+0], offset XMShandler
	mov word ptr [XMSdriverAddress+2], cs
	mov word ptr jemmini.XMSHandleTable+0, offset xms_handle_table
	mov word ptr jemmini.XMSHandleTable+2, cs
endif
	xor ax,ax
	ret
XMSinit endp

if ?INTEGRATED

;--- set entry in XMS handle array, sizeK in ecx, baseK in edx

I15SetHandle proc c public uses ds bx

;--- first, do a few checks
	cmp edx, 1024		;does the block start at 0x100000?
	jnz @F
	add edx, 64			;then exclude the first 64 kB for HMA
	sub ecx, 64
	jc exit
@@:
if ?XMS35
	cmp edx, 400000h    ;beyond 4GB?
	jc @F
	sub xms_smax, ecx	;/MAXSEXT option set?
	jnc smax_ok
	add ecx, xms_smax	;limit to maximum
	mov xms_smax,0
	jecxz exit
smax_ok:
	mov xms_smem_used, 1
	jmp beyond4g
@@:
endif
	sub xms_max, ecx	;MAXEXT option set?
	jnc @F
	add ecx, xms_max	;limit to maximum
	mov xms_max,0
	jecxz exit
@@:
;--- adjust xms_mem_free and xms_mem_largest fields, if needed
	add xms_mem_free, ecx
	cmp ecx, xms_mem_largest
	jb @F
	mov xms_mem_largest, ecx
@@:
	mov eax, edx
	add eax, ecx
	shl eax, 10
	cmp eax, xms_mem_highest
	jb @F
	mov xms_mem_highest, eax
@@:
beyond4g:
	push cs
	pop ds
	mov bx, offset xms_handle_array
	.while [bx].XMS_HANDLE.xh_flags != XMSF_INPOOL
		add bx, sizeof XMS_HANDLE
	.endw
	mov [bx].XMS_HANDLE.xh_flags, XMSF_FREE
	mov [bx].XMS_HANDLE.xh_baseK, edx
	mov [bx].XMS_HANDLE.xh_sizeK, ecx
exit:
	ret
I15SetHandle endp

;--- I15AllocMemory(int dummy, long kbneeded);

I15AllocMemory proc stdcall public uses ds si dummy:WORD, kbneeded:DWORD

	push cs
	pop ds
	mov ecx, kbneeded
	xor si, si
	mov bx, offset xms_handle_array

;--- scan handle table for a free block that is large enough
	.while [bx].XMS_HANDLE.xh_flags != XMSF_INPOOL
		cmp si,0
		jnz @F
		cmp [bx].XMS_HANDLE.xh_flags, XMSF_FREE
		jnz @F
		cmp [bx].XMS_HANDLE.xh_sizeK, ecx
		jb @F
if ?XMS35
		test word ptr [bx].XMS_HANDLE.xh_baseK+2, 0FFC0h
		jnz @F
endif
		mov si,bx
@@:
		add bx,sizeof XMS_HANDLE
	.endw
	.if si
;--- a block with sufficient size has been found, and
;--- bx points to a free handle now, which will hold
;--- the remaining memory of the block
		mov eax, [si].XMS_HANDLE.xh_sizeK
		sub eax, ecx
		mov [si].XMS_HANDLE.xh_sizeK, ecx
;--- v5.80: don't lock block, so it can be "reallocated" in monitor
;		mov [si].XMS_HANDLE.xh_locks, 1
		mov [si].XMS_HANDLE.xh_flags, XMSF_USED
		add ecx, [si].XMS_HANDLE.xh_baseK
;--- if eax (=size) is zero, no new handle is needed
		and eax, eax
		jz @F
		mov [bx].XMS_HANDLE.xh_flags, XMSF_FREE
		mov [bx].XMS_HANDLE.xh_sizeK, eax
		mov [bx].XMS_HANDLE.xh_baseK, ecx
@@:
	.endif
	mov ax, si
	ret
I15AllocMemory endp

;--- get the base of a XMS handle

GetEMBBase proc stdcall public wHdl:word
;--- to be fixed: use the wHdl parameter
	mov eax, xms_handle_array.xh_baseK
	shl eax, 10
	ret
GetEMBBase endp

endif

_TEXT ENDS

	end start
