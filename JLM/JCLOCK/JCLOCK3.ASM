
;--- JCLOCK2 in Masm/JWasm syntax

	.386
	.model flat
	option casemap:none

	include jlm.inc

; Constants

DLL_PROCESS_ATTACH equ 1
DLL_PROCESS_DETACH equ 0

; 1. Addresses
DispMode equ 000449h ; BYTE  - display mode
ColNum   equ 00044Ah ; WORD  - number of columns 
Timer    equ 00046Ch ; DWORD - timer of BIOS
CoVideo  equ 0B8000h ; Video buffer offset for MODE CO80/CO40
MoVideo  equ 0B0000h ; Video buffer offset for MODE MONO

; 2. Text properties
attr  = 2Eh                       ; TEXT ATTRIBUTE
mask0 = attr*1000000h + attr*100h ; Masks for text field
mask1 = mask0 + ':'               ; initialization
mask2 = mask0 + ':' * 10000h      ;

	.data

	public export ddb

ddb VxD_Desc_Block <0,0,6655h,1,0,0,"JCLOCK3 ",80000000h>
oldvec dd 0

	option dotname

.drectve segment info
	db "-dll -fixed:no -subsystem:native "
.drectve ends

.hdr$2 segment dword
	db "PX"
.hdr$2 ends

	.code
;
; This procedure is a hook for INT 1Ch
;
HookProc hookproc, oldvec
	; Initialization
	; Timer check
	pushad
	mov eax, ds:[Timer] ; Get BIOS timer
	and eax, 7       ; eax % 8 == 0 
	test eax, eax    ; 
	jnz intexit      ; if not -- quit
                         ; (we don't have to do IN/OUT every 1/19 sec!)

	; Video mode check
	mov al, ds:[DispMode]
	cmp al, 07h      ; MODE MONO ?
	jne color        ; if not -- check color mode
	mov ebx, MoVideo ; Load video buffer offset
	jmp mono

color:
	cmp al, 03h      ; MODE CO80/CO40 ?
	ja intexit       ; if not -- quit
	mov ebx, CoVideo ; Load video buffer offset
mono:
	; Set up initial position
	movzx esi, word ptr ds:[ColNum] ; ESI = 2*ColNum - 16 + EBX
	shl esi, 1  
	sub esi, 16
	add esi, ebx ; EBX == 0B8000h or 0B0000h

	; Clock output
clkout: ; 1. Draw mask
	mov dword ptr [esi],    mask0
	mov dword ptr [esi+4],  mask1
	mov dword ptr [esi+8],  mask2
	mov dword ptr [esi+12], mask0
	; 2. Get current time
	mov al, 4 ; Hours
	call printBCDcell
	add  esi, 6
	mov al, 2 ; Minutes
	call printBCDcell
	add  esi, 6
	mov al, 0 ; Seconds
	call printBCDcell
intexit:
	popad
	stc		; signal this INT hasn't been handled yet
	ret
hookproc endp

; Procedure prints CMOS cell 
; cell must be in BCD format
;
; AL      - cell number
; EBX+ESI - video RAM address
;
printBCDcell proc
	; Get byte from CMOS RTC
	out 70h, al     ; Set cell number in CMOS RTC
	jmp $+2
	jmp $+2
	in  al,  71h    ; Get byte from cell
	; High half-byte of BCD
if 1
	db 0d4h,10h		;AAM 10h
	add ax,3030h
	mov [esi+0],ah
	mov [esi+2],al
else
	push ax 
	and  al, 0F0h
	shr  al, 4
	add  al, '0'
	mov  [esi], al
	pop  ax 
	; Low half-byte of BCD
	and  al, 00Fh
	add  al, '0'
	mov  [esi+2], al
endif
	ret
printBCDcell endp

; This procedure hooks INT 1Ch
;
intn = 1Ch                          ; INTERRUPT NUMBER

install proc

	mov eax,intn
	mov esi,hookproc
	@VMMCall Hook_V86_Int_Chain
	ret                         ; Exit 
install endp

deinstall proc

	mov eax,intn
	mov esi,hookproc
	@VMMCall Unhook_V86_Int_Chain
	ret                         ; Exit 
deinstall endp

;
; DLL entry point
;
DllEntryPoint proc stdcall hinstDLL:dword, fdwReason:dword, lpvReserved:dword

	cmp [fdwReason], DLL_PROCESS_ATTACH
	jne @F
	call install
	mov eax,1
	jmp @@exitDLL
@@:
	cmp [fdwReason], DLL_PROCESS_DETACH
	jne @@exitDLL
	call deinstall
	mov eax,1
@@exitDLL:
	ret
DllEntryPoint endp

	end DllEntryPoint
