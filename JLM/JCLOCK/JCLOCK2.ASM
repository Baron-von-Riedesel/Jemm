
; this is a modified JCLOCK version which uses the Jemm API to hook int 1Ch.
; Thus, it can be unloaded.
;
; (C) 2007 Alexey Voskov
;
; Compile with FASM for WIN32
; and change PE signature into PX

format PE CONSOLE 4.0 DLL
entry DllEntryPoint

include '%FASMINC%\win32a.inc'
include '%JLMINC%\jlmfasm.inc'

; Constants
; 1. Addresses
DispMode = 000449h ; BYTE  - display mode
ColNum   = 00044Ah ; WORD  - number of columns 
Timer    = 00046Ch ; DWORD - timer of BIOS
CoVideo  = 0B8000h ; Video buffer offset for MODE CO80/CO40
MoVideo  = 0B0000h ; Video buffer offset for MODE MONO
; 2. Text properties
attr  = 2Eh                       ; TEXT ATTRIBUTE
mask0 = attr*1000000h + attr*100h ; Masks for text field
mask1 = mask0 + ':'               ; initialization
mask2 = mask0 + ':' * 10000h      ;
;*********************************************************************
section '.code' code readable executable
;
; This procedure is a hook for INT 1Ch
;
oldvec dd 0

	dd oldvec        ; a hook procedure must be preceeded by a dword
                     ; which contains the address where the old vector
                     ; will be stored.
proc hookproc
	; Initialization
	; Timer check
	pushad
	mov eax, [Timer] ; Get BIOS timer
	and eax, 7       ; eax % 8 == 0 
	test eax, eax    ; 
	jnz intexit      ; if not -- quit
                         ; (we don't have to do IN/OUT every 1/19 sec!)

	; Video mode check
	mov al, [DispMode]
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
	movzx esi, word [ColNum] ; ESI = 2*ColNum - 16 + EBX
	shl esi, 1  
	sub esi, 16
	add esi, ebx ; EBX == 0B8000h or 0B0000h

	; Clock output
clkout: ; 1. Draw mask
	mov dword [esi],    mask0
	mov dword [esi+4],  mask1
	mov dword [esi+8],  mask2
	mov dword [esi+12], mask0
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
endp

; Procedure prints CMOS cell 
; cell must be in BCD format
;
; AL      - cell number
; EBX+ESI - video RAM address
;
proc printBCDcell
	; Get byte from CMOS RTC
	out 70h, al     ; Set cell number in CMOS RTC
	mov ecx, 02000h ; A short delay
@@dl:   inc ecx     ; CMOS RTC memory is slow
	dec ecx         ;
	loop @@dl       ;
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
end if
	ret
endp

; This procedure hooks INT 1Ch
;
intn = 1Ch                          ; INTERRUPT NUMBER

proc install

	mov eax,intn
	mov esi,hookproc
	VMMCall Hook_V86_Int_Chain
	ret                         ; Exit 
endp

proc deinstall

	mov eax,intn
	mov esi,hookproc
	VMMCall Unhook_V86_Int_Chain
	ret                         ; Exit 
endp

;
; DLL entry point
;
proc DllEntryPoint hinstDLL,fdwReason,lpvReserved
	cmp [fdwReason], DLL_PROCESS_ATTACH
	jne @F
	call install
	mov eax,TRUE
	jmp @@exitDLL
@@:
	cmp [fdwReason], DLL_PROCESS_DETACH
	jne @@exitDLL
	call deinstall
	mov eax,TRUE
@@exitDLL:
	ret
endp

section '.data' data readable writeable

;--- Sorry, no idea how to create an instance of a structure in fasm ...

;ddb VxD_Desc_Block 0,0,6655h,1,0,0,0,0,0, 0, 0, 0, 0
ddb dd 0
	dw 0
	dw 6655h
	db 1
	db 0
	db 0
	db "JCLOCK2 "
	dd 80000000h
	dd 0
	dd 0
	dd 0
	dd 0
	rd 10

;--- to make the JLM unloadable, it must have a "device id". A "device id"
;--- is obtained by exporting a DDB

section '.edata' export data readable

	export 'JCLOCK2.DLL',\
	ddb,1

;*********************************************************************
;
; * DON'T STRIP RELOCATIONS ! JLM MUST HAVE THEM ! *
;
section '.reloc' fixups data discardable
