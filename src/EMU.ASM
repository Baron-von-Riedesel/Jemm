
;--- privileged opcode emulation
;--- copyright Tom Ehlert

;--- to be assembled with JWasm or Masm v6.1+

    .386
    .model FLAT
    option dotname

    include jemm.inc        ;common declarations
    include jemm32.inc      ;declarations for Jemm32
    include debug32.inc

?EMUCLTS equ 0	; 1=emulate CLTS ( resets TS bit in CR0 )

;--- publics/externals

    include extern32.inc

.text$01 SEGMENT

RunEmuInstr:
    DB 0Fh
EmuInstr DB 90h,90h  ; run self-modifying code here
    ret

.text$01 ends

.text$03 segment

@v86popregX macro
    mov esp,ebp
    POPAD
    endm

;--- emulate some privileged 0Fh opcodes (not HLT)
;--- EBP -> client struct
;--- ESP = dwStackCurr
;--- ESI -> linear address of v86 CS:IP
;--- AL = 0Fh
;--- this is not called, but jumped to by V86_Exception.

ExtendedOp proc public
    mov al,[esi+1]
if ?EMUCLTS
    cmp al,6
    je @@clts
endif
    cmp al,9
    je @@wbinvd
    cmp al,8
    je @@invd
    cmp al,30h
    je @@wrmsr
    cmp al,31h	; whether RDTSC is privileged depends on CR4, bit 2 (TSD)
    je @@rdtsc
    cmp al,32h
    je @@rdmsr
    cmp al,20h
    jb V86_Exc0D ; not an opcode we emulate
    cmp al,23h
    ja V86_Exc0D

; opcodes 0F 20 xx to 0F 23 xx emulated via self-modifying code

    mov ah,[esi+2]  ; get third byte of opcode
    mov WORD PTR [EmuInstr+0],ax
    add [ebp].Client_Reg_Struc.Client_EIP,3 ; jump over emulated instruction
    @v86popregX
    call RunEmuInstr
    add esp, CRS_SIZEX  ; skip error code & int#
    iretd
if ?EMUCLTS
@@clts:
    .386p
    clts
    .386
    jmp @@invdshare
endif
@@invd:
    .486p
    invd
    .386
    jmp @@invdshare
@@wbinvd:
    .486p
    wbinvd
    .386
@@invdshare:
    @v86popregX
    jmp @@twoeat

@@wrmsr:
    @v86popregX
    .586p
    wrmsr
    .386
    jmp @@twoeat

; early pentiums and such will throw an exception on rdtsc instruction in V86
;  regardless of CR4 setting, later CPU versions won't

@@rdtsc:
    @v86popregX
    .586
    rdtsc
    .386
    jmp @@twoeat

@@rdmsr:
    @v86popregX
    .586p
    rdmsr
    .386

@@twoeat:
    add esp, CRS_SIZEX          ; skip error code & int#
    add [esp].IRETDV86._Eip,2   ; jump over instruction
    iretd

    align 4

ExtendedOp endp

.text$03 ends

    END
