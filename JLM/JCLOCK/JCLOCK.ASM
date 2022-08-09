;
; JCLOCK 1.1
;
; JLM example -- CLOCK for JEMM386/JEMMEX
; It is the first JLM with screen input/output  :-)
;
; (C) 2007 Alexey Voskov
;
; Compile with FASM for WIN32
; and change PE signature into PX
;

format PE CONSOLE 4.0 DLL
entry DllEntryPoint

include '%FASMINC%\win32a.inc'

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
; This procedure is a new INT 08h subroutine
;
proc newint08
	; Initialization
	pushad
	mov ebp, esp
	push ss
	pop  ds
	push ss
	pop  es
	; Timer check
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
	ja  intexit      ; if not -- quit
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
        ; Call the old INT 08h subroutine
intexit:
	  popad       ; Restore registers and stack
	  db 0EAh     ; ASM command:
oldint08: db 6 dup 0  ; jmp far 0000:00000000
                      ; (48-bit far call)
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
@@dl:   inc ecx         ; CMOS RTC memory is slow
	dec ecx         ;
	loop @@dl       ;
	in  al,  71h    ; Get byte from cell
	; High half-byte of BCD
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

	ret
endp

; This procedure hooks INT 08h
;
; WARNING -- it contains low-level work with IDT
; In newer versions of JEMM it probably 
; will be replaced with special API
;
intn = 08h                          ; INTERRUPT NUMBER
proc install
        ; Beginning
	sub esp,8                   ; Reserve memory in stack
	; Get pointer to IDT
        sidt [esp]                  ; Write register of interrupt 
                                    ; descriptor table to [ESP]
	mov esi,[esp+2]             ; Get IDT beginning address into ESI
	; Save old interrupt descriptor
        mov ax,[esi+6+intn*8]       ; Get bits 31-16
        shl eax,16                  ; of offset
        mov ax,[esi+0+intn*8]       ; Get bits 15-0 of offset
	mov dword ptr oldint08, eax ; Save offset
        mov ax,[esi+2+intn*8]       ; Get selector
        mov word ptr oldint08+4,ax  ; Save selector
	; Set up new interrupt descriptor
        mov eax, newint08           ; Get offset of new interrupt procedure
        mov [esi+0+intn*8],ax       ; And write it 
        shr eax, 16                 ; into IDT
        mov [esi+6+intn*8],ax       ; (SELECTOR UNCHANGED!)
        ; Final
        add esp,8                   ; Free memory in stack
	ret                         ; Exit 
endp
; NOTE:
;
; Interrupt descriptor format (gate):
; | OFFSET(bits 31-16) | FLAGS | SEG SELECTOR | OFFSET (bits 15-0)
;


;
; DLL entry point
;
proc DllEntryPoint hinstDLL,fdwReason,lpvReserved
	cmp	[fdwReason], DLL_PROCESS_ATTACH
	jne     @@exitDLL
	call    install
	mov	eax,TRUE
@@exitDLL:
	ret
endp

;*********************************************************************
;
; * DON'T STRIP RELOCATIONS ! JLM MUST HAVE THEM ! *
;
section '.reloc' fixups data discardable
