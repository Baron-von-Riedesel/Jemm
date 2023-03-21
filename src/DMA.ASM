
;--- DMA port trapping code
;--- originally written by Harald Albrecht
;--- modified for Jemm by Japheth
;--- copyright (c) 1990 c't/Harald Albrecht

;--- to be assembled with JWasm or Masm v6.1+

;--- IN, although trapped, returns the true value of the port.
;--- OUT stores the values to be written, and also does an OUT with unmodified ax/al reg.
;--- only if the DMA op is fully initialized, Dma_CheckChannel()
;--- is called and will do a translation, if required.


    .486P
    .model FLAT
    option proc:private
    option dotname

    include jemm.inc        ;common declarations
    include jemm32.inc      ;declarations for Jemm32
    include debug.inc

;--- publics/externals

    include external.inc

;   assume SS:FLAT,DS:FLAT,ES:FLAT

.text$01 SEGMENT

if ?DMA

DmaTargetAdr    DD  0   ; Original adress for DMA
DmaTargetLen    DD  0   ; Utilized part of the Buffer

DMAF_ENABLED    equ 1   ;1=channel is enabled/unmasked

DmaChn          DMAREQ 8 dup (<0,0,0,0,0,0>)	; also accessed by VDS code
DmaGblFlags     DW 0    ; global flags
                align 4

endif

.text$01 ends

.text$03 segment

if ?DMA

;--- table to translate page ports (80-8F) to channel no
PageLookUp DB 0,2,3,1,0,0,0,0, 0,6,7,5,0,0,0,0

;--- page translation table
;--- channels   0,  1,  2,  3, -, 5,  6,  7
PageXLat DB    87H,83H,81H,82H,0,8BH,89H,8AH

;--- Access to a DMA page register (80-8F)
;--- v5.84: now Simulate_IO_trap is called if access isn't "byte"
; DX : port
; AL : value
; CL : type
;--- modifies EDI, BX

Dma_HandlePagePorts PROC public

    test cl,OUTPUT
    jz Simulate_IO   ;is input, just translate to byte accesses
    test cl,STRING_IO or DWORD_IO or WORD_IO
    jnz Simulate_IO_trap	; split access to bytes

    @dprintf ?DMADBG, <"Dma_HandlePagePorts: OUT, dx=%X al=%X",10>, dx, al

    OUT DX,AL
    MOVZX EBX,DL                  ; store page value in cache
    MOVZX EDI,BYTE PTR PageLookUp[EBX-80H]
    MOV [DmaChn+EDI*sizeof DMAREQ].PageReg,AL
    jmp Dma_IsReady
    align 4

Dma_HandlePagePorts ENDP

;--- handle 8-bit DMA ports 00-0F
;--- ports 00-07: addr/count for channels 0-3
;--- port 08: R=status 0-3, W=cmd register 0-3
;--- port 09: W=write req 0-3
;--- port 0A: RW=channel mask register 0-3
;--- port 0B: W=mode 0-3
;--- port 0C: W=clear flipflop 0-3 for addr/count
;--- port 0D: R=temp reg, W=reset DMA
;--- port 0E: W=clear mask reg 0-3
;--- port 0F: W=write mask register
;--- channel 2 is used by floppy controller

;--- v5.84: now Simulate_IO_trap is called if access isn't "byte"

; DX = port
; AL = value
; CL = type
;--- modifies EDI, BX

Dma_HandleDmaPorts8 proc public

    test cl,OUTPUT
    jz Simulate_IO
    test cl,STRING_IO or WORD_IO or DWORD_IO ;not byte access?
    jnz Simulate_IO_trap

if ?DMADBG
    push eax
    @dprintf ?DMADBG, <"Dma_HandleDmaPorts8: OUT, dx=%X al=%X ">, dx, al
    in al, 8
    @dprintf ?DMADBG, <"08=%X",10>, al
    pop eax
endif

    CMP DL,8                    ; Program addresses and/or length of the blocks
    JB @@BlockSet8
    CMP DL,0AH                  ; single mask?
    JZ @@SMask8
    CMP DL,0BH                  ; "Mode Register" responded ?
    JZ @@Mode8                 ; DMA-Controller #1 ?
    CMP DL,0CH
    JZ @@Clear8                ; clear flip-flop?
if ?MMASK
    CMP DL,0DH
    JZ @@MMask8On
    CMP DL,0EH
    JZ @@MMask8Off
    CMP DL,0FH
    JZ @@MMask8                ; master mask?
endif
    @dprintf ?DMADBG, <"Dma_HandleDmaPorts8: unhandled OUT to port %X",10>, dx
    out dx, al
    ret
@@Clear8:
    out dx, al
    BTR [DmaGblFlags],HiLoFlag1
    ret
@@BlockSet8:                    ;--- I/O addresses 0-7 (DMA 8bit)
    MOV BX,HiLoFlag1
    MOVZX EDI,DL
    SHR EDI,1               ; get channel# into EDI
    jc Dma_SetLength
    JMP Dma_SetAddr
@@SMask8:
    mov edi, eax
    AND EDI,0011B
    jmp Dma_SetSMask
@@Mode8:
    MOV EDI,EAX
    AND EDI,011B
    jmp Dma_SetMode
if ?MMASK
@@MMask8On:             ;mask all 4 channels
    mov al,0Fh
    jmp @@MMask8
@@MMask8Off:            ;unmask all 4 channels
    mov al,0
@@MMask8:
    mov ah, al
    xor edi, edi
    jmp Dma_SetMMask
endif
    align 4

Dma_HandleDmaPorts8 endp

;--- handle 16-bit DMA ports C0-DF
;--- v5.84: now Simulate_IO_trap is called if access isn't "byte"
; DX = port
; AL = value
; CL = type
;--- modifies EDI, BX

Dma_HandleDmaPorts16 proc public

    test cl,OUTPUT
    jz Simulate_IO
    test cl,STRING_IO or WORD_IO or DWORD_IO ;not byte access?
    jnz Simulate_IO_trap

if ?DMADBG
    push eax
    @dprintf ?DMADBG, <"Dma_HandleDmaPorts16: OUT, dx=%X ax=%X ">, dx, ax
    in al, 0D0h
    @dprintf ?DMADBG, <"D0=%X",10>, al
    pop eax
endif

    CMP DL,0C0h+10h             ; dto. 2nd DMA-Controller ?
    JB @@BlockSet16
    CMP DL,0C0h+0AH*2           ; single mask?
    JZ @@SMask16
    CMP DL,0C0h+0BH*2           ; mode set?
    JZ @@Mode16
    CMP DL,0C0h+0Ch*2
    JZ @@Clear16
if ?MMASK
    CMP DL,0C0h+0Dh*2
    JZ @@MMask16On
    CMP DL,0C0h+0Eh*2
    JZ @@MMask16Off
    CMP DL,0C0h+0Fh*2           ; master mask?
    JZ @@MMask16
endif
    @dprintf ?DMADBG, <"Dma_HandleDmaPorts16: unhandled OUT to port %X",10>, dx
    out dx, al
    ret
@@Clear16:
    out dx, al
    BTR [DmaGblFlags],HiLoFlag2
    ret
@@BlockSet16:                   ;--- I/O addresses C0-CF (DMA 16bit)
    MOV BX,HiLoFlag2
    MOV EDI,EDX
    SHR EDI,2               ; get channel# into EDI
    AND EDI,3
    ADD EDI,4
    TEST DL,02H              ; block length or address?
    JNZ Dma_SetLength
    jmp Dma_SetAddr
@@SMask16:
    mov edi, eax
    AND EDI,0011B
    add edi,4
    jmp Dma_SetSMask
@@Mode16:
    MOV EDI,EAX
    AND EDI,011B            ; mask the DMA channel #
    ADD EDI,4               ; 16bit channels are 4-7
    JMP Dma_SetMode
if ?MMASK
@@MMask16On:            ;mask all 4 channels
    mov al,0Fh
    jmp @@MMask16
@@MMask16Off:           ;unmask all 4 channels
    mov al,0
@@MMask16:
    mov ah, al
    shl ah, 4
    mov edi, 4
    jmp Dma_SetMMask
endif
    align 4

Dma_HandleDmaPorts16 endp


Dma_SetAddr:
    mov ecx,offset DmaChn.BaseAdr
    jmp Dma_SetLenOrAdr
Dma_SetLength:
    mov ecx,offset DmaChn.BlockLen
Dma_SetLenOrAdr:
    OUT DX,AL
    BTC [DmaGblFlags],BX        ; toggle the Hi/Lo-Flag
    adc ecx,0
    MOV BYTE PTR [ECX+EDI*sizeof DMAREQ],AL
    test cl,1
    jnz Dma_IsReady
    ret
;
; Monitor "Mode Register" for the Transferdirection DMA <--> I/O
;
Dma_SetMode:
    out dx, al
    mov [DmaChn+EDI*sizeof DMAREQ].ChanMode,al

Dma_IsReady proc
if 0
    mov ecx,[dwRFlags]
    test byte ptr [ecx],2    ;new Int 13h/40h DMA op?
    jz @@nonewreq
    and byte ptr [ecx],not 2
    and [DmaChn+EDI*sizeof DMAREQ].bFlags,not DMAF_ENABLED  ;wait until channel is enabled
@@nonewreq:
endif
    test [DmaChn+EDI*sizeof DMAREQ].bFlags,DMAF_ENABLED
    jz @@Bye
    CALL Dma_CheckChannel    ; Then check value
@@Bye:
    RET
Dma_IsReady endp

;--- Single mask port (000A, 00D4)
;--- bits 0-1 select channel
;--- bit 2=1 -> enable channel mask (=channel inactive)

Dma_SetSMask proc
    and [DmaChn+EDI*sizeof DMAREQ].bFlags,not DMAF_ENABLED
    test al,4
    jnz @@isdisable
    or [DmaChn+EDI*sizeof DMAREQ].bFlags,DMAF_ENABLED
if 0
    mov ecx,[dwRFlags]
    and byte ptr [ecx],not 2
endif
    push eax
    call Dma_CheckChannel
    pop eax
@@isdisable:
    out dx, al
    ret
Dma_SetSMask endp

if ?MMASK
;--- Master mask port (000F, 00DE)
;--- bit 0 -> 1=channel 0 inactive, 0=channel 0 active
;--- bit 1 -> ... chn 1
;--- bit 2 -> ... chn 2
;--- bit 3 -> ... chn 3

;--- this port cannot be read reliably !!!!!

Dma_SetMMask proc
    mov cl,4
    xchg al,ah   ;value to write to port now in AH, in AL transformed mask
@@nextcnl:
;   test [DmaChn+EDI*sizeof DMAREQ].bFlags,DMAF_ENABLED
;   jnz @@skipchannel       ;channel is already active
    and [DmaChn+EDI*sizeof DMAREQ].bFlags,not DMAF_ENABLED
    bt eax, edi
    jc @@skipchannel       ;channel will become/stay inactive
    or [DmaChn+EDI*sizeof DMAREQ].bFlags,DMAF_ENABLED
    push eax
    push ecx
    call Dma_CheckChannel
    pop ecx
    pop eax
@@skipchannel:
    inc edi
    dec cl
    jnz @@nextcnl
    mov al, ah
    out dx, al
    ret

Dma_SetMMask ENDP

endif

;
; A DMA-Channel is completely supplied with data about beginning and length,
; so a check can (and has to) take place.
;
; In: EDI: Channelnumber 0..7
; modifies ECX, ESI, EBX
;
Dma_CheckChannel PROC

    @dprintf ?DMADBG, <"Dma_CheckChannel enter, edi=%u",10>, edi

    cmp [DmaChn+EDI*sizeof DMAREQ].cDisable,0   ;translation disabled by VDS?
    jnz @@Bye
    test [DmaChn+EDI*sizeof DMAREQ].ChanMode,1100B  ; If a verify is wanted
    JZ @@Bye                          ; nothing is to be done

if 1
    and [DmaChn+EDI*sizeof DMAREQ].bFlags,not DMAF_ENABLED
endif

    MOVZX ECX,[DmaChn+EDI*sizeof DMAREQ].BlockLen ; get block length into ECX
    MOVZX ESI,[DmaChn+EDI*sizeof DMAREQ].PageReg  ; and base address into ESI
    INC ECX
    CMP EDI,4                       ; for 16bit DMA channels,
    JB @@Only8
    ADD ECX,ECX                     ; words are transferred
    SHL ESI,15                      ; and Bit 0 of the page register
    MOV SI,[DmaChn+EDI*sizeof DMAREQ].BaseAdr   ; will be ignored
    SHL ESI,1
    JMP @@Chk
@@Only8:
    SHL ESI,16                      ; for 8bit DMA, address calculation
    MOV SI,[DmaChn+EDI*sizeof DMAREQ].BaseAdr   ; is simple
@@Chk:

;--- now ESI holds the start address (linear!)

    BTR [DmaGblFlags],NeedBuffer    ; Initialise.

;--- Is the block occupying contiguous physical pages?
;--- Or does it cross a 64kB/128 kB boundary?
;--- after the call ESI will hold the physical address (if NC)

    push esi
    CALL Dma_IsContiguous
    pop ebx
    JNC @@Set   ;NC if buffer *is* contiguous               

;   test [DmaChn+EDI*sizeof DMAREQ].ChanMode,10h ;auto-init? Then a buffer is useless
;   jnz @@Set

    @dprintf ?DMADBG, <"block not contiguous or crosses 64k border, DMA buffer needed!",10>

    MOV ESI,[DMABuffStartPhys]      ; get DMA Buffer physical address
    BTS [DmaGblFlags], NeedBuffer
    cmp ecx, [DMABuffSize]
    jbe @@blocksizeok
    mov ecx, [DMABuffSize]          ; error: DMA buffer overflow    
@@blocksizeok:
    call @@SetX
    MOV AL,[DmaChn+EDI*sizeof DMAREQ].ChanMode  ; copy data into buffer required?
    and al,1100b
    cmp al,1000b
    JNZ @@IsRead

    @dprintf ?DMADBG, <"Dma_CheckChannel: copy into DMA buffer",10>

    push edi
    MOV ESI,EBX
    MOV EDI,[DMABuffStart]
    CLD
    call MoveMemory
    pop edi
    RET
@@IsRead:
if ?HOOK13
    mov eax,[dwRFlags]
  if 1
    test byte ptr [eax],2            ; is a int 13h/40h read op pending?
    jz @@Bye
    mov byte ptr [eax],1
  else
    or byte ptr [eax],1
  endif
else
    or [bDiskIrq],1
endif
    MOV [DmaTargetLen],ECX
    MOV [DmaTargetAdr],EBX          ; save linear address of block
@@Bye:
    RET

;--- set DMA base address and page register
;--- modifies ESI, EAX

@@Set:

if ?DMADBG
    @DbgOutS <"target lin. start address=">,1
    @DbgOutD ebx,1
    @DbgOutS <" length=">,1
    @DbgOutD ecx,1
    @DbgOutS <" phys=">,1
    @DbgOutD esi,1
    @DbgOutS <" chn=">,1
    @DbgOutD edi,1
    cmp esi, ebx
    jz @@nothingtodo
    @DbgOutS <"*">,1
@@nothingtodo:    
    @DbgOutS <10>,1
    @WaitKey 1, 0
endif

    cmp esi, ebx                ; has address changed?
    jz @@Bye
@@SetX:
    push edx
    CMP EDI,4                   ; 8-bit or 16-bit channel ?
    JB @@Set8

;-- calc I/O-address from DMA channel: 4->C0, 5->C4, 6->C8, 7->CC

    lea edx, [edi-4]
    shl edx, 2                  ; edx=0,4,8,C
    or dl, 0C0h
    BTR [DmaGblFlags],HiLoFlag2 ; DMA #2, HiLo-FlipFlop-Flag
    OUT [0D8H],AL               ; clear Hi/Lo-FlipFlop
    JMP $+2
    SHR ESI,1
    MOV EAX,ESI                 ; reprogram base address
    SHR ESI,15
    JMP @@Cont

;-- calc I/O-address from DMA channel: 0->0, 1->2, 2->4, 3->6

@@Set8:
    LEA EDX,[EDI+EDI]
    BTR [DmaGblFlags],HiLoFlag1 ; DMA #1, HiLo-FlipFlop-Flag
    OUT [0CH],AL                ; clear Hi/Lo-FlipFlop
    JMP $+2
    MOV EAX,ESI                 ; reprogram base address
    SHR ESI,16                  ; get bits 16-23 into 0-7
@@Cont:
    OUT DX,AL                   ;
    MOV AL,AH
    JMP $+2
    OUT DX,AL
    MOV DL,PageXLat[EDI]        ; get I/O-Adress of page-register
    MOV EAX,ESI                 ; set the page register
    OUT DX,AL
    pop edx
    ret
    align 4

Dma_CheckChannel ENDP

;
; Check a memory-area to be in physical contiguous memory.
; Furthermore, the physical region must not cross a 64 kB
; (or 128 kB for 16bit) boundary
;
; In:  ESI: linear start address (bits 0-23 only)
;      ECX: Length of the range (?DMABUFFMAX is max in kB)
;      EDI: channel
; Out: NC: contiguous, ESI = physical adress
;       C: not contiguous
; modifies: EAX, EBX, ESI 

Dma_IsContiguous PROC
    cmp ESI, 400000h-20000h     ; don't touch PTEs > 3E0000h
    jnc @@Ok2
    PUSH ECX

if 0    ;ecx cannot be 0 (is 1-20000h)
    cmp ecx,1                   ; make sure ecx is at least 1
    adc ecx,0
endif

    PUSH ESI
    lea ECX,[ecx+esi-1]         ; ecx -> last byte 

    SHR ESI,12                  ; linear start address -> PTE
    SHR ECX,12                  ; linear end   address -> PTE
    sub ecx, esi
    
    @GETPTEPTR ESI, ESI*4+?PAGETAB0 ; ESI -> PTE
    MOV EAX,[ESI]               ; get PTE

    @dprintf ?DMADBG, <"Dma_IsContiguous: PTE=%X ecx=%X",10>, eax, ecx

    shr eax, 12                 ; ignore bits 0-11 of PTE

;--- ESI -> PTE, EAX=1. PTE

    test eax, 0FF000h            ; if physical address is > 16 MB        
    jnz @@Fail                  ; a buffer is needed in any case

    JECXZ @@Ok                    ; exit if region fits in one page

    PUSH EAX                     ; save Bits 31-12
@@Loop:
    ADD ESI,4                   ; one entry further
    INC EAX                     ; Go one page and
    MOV EBX,[ESI]
    shr EBX, 12
    CMP EAX,EBX                 ; contiguous?
    loopz @@Loop
    POP EAX
    JNZ @@Fail
    mov esi,eax                 ; don't change eax for compare
    cmp edi,4                   ; DMA channel 0-3?
    setnc cl
    add cl,4
    shr esi, cl                 ; shift 4 or 5 bits
    shr ebx, cl
    cmp ebx,esi
    JNZ @@Fail                  ; a 64/128 kB Border has been crossed!!!
@@Ok:
    pop ESI
    shl eax,12
    AND ESI,0FFFh
    OR ESI,EAX
    pop ECX
@@Ok2:
    CLC
    RET
@@Fail:
    POP ESI
    POP ECX
    STC
    RET
    align 4

Dma_IsContiguous ENDP


; Copy the DMA-buffercontents after termination of the DISK-I/O to the
; wanted target/location.
; * This is triggered by an v86-breakpoint in the real-mode int 13
; * and int 40 handlers. First the original int 13 / 40 is done, and
; * then, if the DMA buffer was used, things are copied from this buffer
; * to the target linear address.

Dma_CopyBuffer PROC public

if ?HOOK13
    call Simulate_Iret
    and [ebp].Client_Reg_Struc.Client_EFlags, not 1 ;CF=0
endif

    MOV ESI,[DMABuffStart]
    MOV EDI,[DmaTargetAdr]
    mov ECX,[DmaTargetLen]

    @dprintf ?DMADBG, <"Dma_CopyBuffer: dst=%X src=%X siz=%X",10>, edi, esi, ecx

    CLD
    call MoveMemory
if ?HOOK13
    mov eax,[dwRFlags]
    mov byte ptr [eax],0
endif
    ret
    align 4

Dma_CopyBuffer ENDP

endif   ;?DMA

.text$03    ends

    END
