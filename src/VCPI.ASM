
;--- VCPI implementation
;--- Public Domain
;--- to be assembled with JWasm or Masm v6.1+
;--- originally written by Michael Devore
;--- extended and modified for Jemm by Japheth 


    .486P
    .model FLAT
    option proc:private
    option dotname

    include jemm.inc        ;common declarations
    include jemm32.inc      ;declarations for Jemm32
    include ems.inc         ;EMS definitions
    include vcpi.inc        ;VCPI definitions
    include debug.inc

?CLEARTB    equ 1   ;std 1, 1=clear "busy" flag in client's TSS descriptor
?VCPITMPSS  equ 1   ;std 1, 1=use a tmp SS sel to avoid hiword(ESP) to be <> 0
?SAFEMODE   EQU 0   ;std 0, 1=additionally switch GDTR and IDTR
?SAFETSS    equ 0   ;std 0, 1=additionally switch TR (clear "busy" flags!)
?SPSYSTEM   equ 1   ;std 1, 1=set shared page at 110000 to "system" instead of r/o

    include external.inc

if ?VCPI

if ?VCPIXDBG
.text$01 segment
dbgv IRETDV86 <>
.text$01 ends
endif

if ?CODEIN2PAGE
    @seg .text$02,<PAGE>
else
    @seg .text$02,<PARA>
endif
.text$02 ENDS

;   assume SS:FLAT,DS:FLAT,ES:FLAT

.text$03 segment

;--- the interface is simple:
;--- inp: EBP -> client_reg_struc
;--- all registers except EBP and ECX still contain the client values.
;--- out: ah and edx will be copied to client_reg_struc,
;--- other client registers must be changed there directly

    align 4

VCPI_Call_Table label dword
    Dd VCPI_Presence    ; 0
    Dd VCPI_GetInterface
    Dd VCPI_GetMax      ; 2
    Dd VCPI_GetFreePages
    Dd VCPI_Allocate4K  ; 4
    Dd VCPI_Free4K
    Dd VCPI_GetAddress  ; 6
    Dd VCPI_GetCR0
    Dd VCPI_ReadDR      ; 8
    Dd VCPI_WriteDR
    Dd VCPI_GetMappings ; 0ah
    Dd VCPI_SetMappings

;--- v5.85: VCPI_V86toPM wasn't activated in this table, because the label
;--- is used directly (see EMS.ASM). Now it's part of the table, so JLoad knows
;--- the label and JLMs may callout to a VCPI client. 
    Dd VCPI_V86toPM     ; 0ch
;VCPI_MAX equ ($ - VCPI_Call_Table) / 4

;
; AX=DE00: VCPI presence detection
;  return BH = 1 (major version), BL = 0 (minor version)
;
VCPI_Presence   PROC
    mov word ptr [ebp].Client_Reg_Struc.Client_EBX,100h
    mov ah,EMSS_OK
    ret
VCPI_Presence   ENDP

;
; AX=DE01: VCPI get protected mode interface
;  inp: es:di -> client zero page table (to fill)
;       ds:si -> three descriptor table entries in client's GDT (to fill)
;  out: [es:di] page table filled
;       di: first uninitialized page table entry (advanced by 4K)
;      ebx: offset to server's protect mode code segment
; The VCPI docs tell that the physical page that receives this
; zero page table must NOT be altered after this call, to allow
; the server to modify PTEs. However, this seems an error in the
; documentation, since the host does not "manage" VCPI clients,
; hence has no idea what "interface" is the current one.

VCPI_GetInterface   PROC
    movzx edi,WORD PTR [ebp].Client_Reg_Struc.Client_DS
    shl edi,4
    movzx esi,si
    add edi,esi         ; esi -> client GDT entries
    mov esi, offset V86GDT + FLAT_CODE_SEL
    movsd
    movsd
    movsd
    movsd

    movzx esi,WORD PTR [ebp].Client_Reg_Struc.Client_ES
    movzx edi,WORD PTR [ebp].Client_Reg_Struc.Client_EDI
    shl esi,4
    add edi,esi             ; edi -> client zero page table
    @GETPTEPTR  esi,?PAGETAB0,1 ; esi -> page table for first 1M

;--- Jemm must ensure that label VCPI_PM_Entry will be in shared memory.
;--- Since this label is located in .text$2, 1 page should suffice.

if ?CODEIN2PAGE
    mov ecx, (440h+2*4) ;this is offset in page table for 112000h
else
    mov ecx, (440h+1*4) ;this is offset in page table for 111000h
endif
if 0 ; not needed - the monitor code beyond the shared space isn't touched by SBEINIT
	test [bV86Flags], V86F_SB
	jz @F
	mov ecx, pPg0PartEnd     ;end address of monitor part in page table 0
	shr ecx, 10
@@:
endif
    add word ptr [ebp].Client_Reg_Struc.Client_EDI,cx
    shr ecx, 2
@@vgiloop:
    lods dword ptr [esi]
    and ah,0F1h     ; clear bits 9-11
    stos dword ptr [edi]
    loop @@vgiloop

if ?SPSYSTEM
    and byte ptr es:[edi-4], not 4  ;set shared page 111xxxh to system
else
    or byte ptr es:[edi-4], 4
    and byte ptr es:[edi-4], not 2  ;set shared page 111xxxh to r/o
endif

    mov [ebp].Client_Reg_Struc.Client_EBX,OFFSET VCPI_PM_Entry
    mov ah,EMSS_OK
    ret

VCPI_GetInterface   ENDP

; AX=DE02: VCPI get maximum physical memory address
;  return edx == physical address of highest 4K page available
;
VCPI_GetMax PROC
    mov edx,[dwMaxPhysMem]
if ?EMX
    test bV86Flags, V86F_EMX;the EMX DOS extender fails if too much memory
    jz @@noemx              ;is available!
    mov edx,[dwMaxMem4K]    ;mem in 4K pages
    shl edx, 12             ;convert to bytes
    add edx, [DMABuffStartPhys]
@@noemx:
endif
    dec edx
    and dx,NOT 0fffh

    mov ah,EMSS_OK
    ret
    align 4

VCPI_GetMax ENDP

; function 03,04 and 05 may also be called from protected-mode.
; then SS+DS+ES are flat, but they are NOT FLAT_DATA_SEL.
; A pop of segment registers would cause a GPF, since the
; client's GDT is active, but most likely is not mapped in
; current address context.

; AX=DE03: VCPI get number of free pages
;  out: edx == number of free pages

VCPI_GetFreePages PROC

    call Pool_GetFree4KPages    ; free 4k pool pages in eax
    mov edx, eax
    mov ah, EMSS_OK
    ret
    align 4

VCPI_GetFreePages ENDP

; AX=DE04: VCPI allocate a 4K page
;  out: edx == physical address of 4K page allocated

VCPI_Allocate4K PROC public

    mov eax,[dwMaxMem4K]
    sub eax,[dwUsedMem4K]
    jbe @@fail
    call Pool_Allocate4KPage    ; see if any pool block has 4K free
    jc @@fail
    mov edx, eax
    mov ah,EMSS_OK
    ret
@@fail:
    stc
    mov ah,EMSS_OUT_OF_FREE_PAGES
    ret
    align 4

VCPI_Allocate4K ENDP

; AX=DE05: VCPI free a 4K page
;  in: edx == physical address of 4K page to free

VCPI_Free4K PROC
    call Pool_Free4KPage
    jc @@bad
    mov ah,EMSS_OK
    ret
@@bad:
    mov ah,EMSS_LOG_PAGE_INVALID
    ret

VCPI_Free4K ENDP

;
; AX=DE06: VCPI get physical address of 4K page in first megabyte
;  entry cx = page number (cx destroyed, use stack copy)
;  return edx == physical address of 4K page
;
VCPI_GetAddress PROC
    movzx ecx, word ptr [ebp].Client_Reg_Struc.Client_ECX
    cmp cx,256
    jae @@vga_bad       ; page outside of first megabyte

    @GETPTE edx, ecx*4+?PAGETAB0
    and dx,0f000h       ; mask to page frame address
    mov ah,EMSS_OK
    ret

@@vga_bad:
    mov ah,EMSS_PHYS_PAGE_INVALID
    ret

VCPI_GetAddress ENDP

;
; AX=DE07: VCPI read CR0
;  return EBX == CR0
;
VCPI_GetCR0 PROC
    mov ebx,cr0
    mov [ebp].Client_Reg_Struc.Client_EBX, ebx
    mov ah,EMSS_OK
    ret
VCPI_GetCR0 ENDP

;
; AX=DE08: VCPI read debug registers
;  call with ES:DI buffer pointer. Returns with buffer filled.
;  (8 dwords, dr0 first, dr4/5 undefined)
;
VCPI_ReadDR PROC
    movzx esi,WORD PTR [ebp].Client_Reg_Struc.Client_ES
    shl esi,4
    movzx edi,di
    add edi,esi
    mov eax,dr0
    stosd
    mov eax,dr1
    stosd
    mov eax,dr2
    stosd
    mov eax,dr3
    stosd
    mov eax,dr6
    mov [edi+8], eax
    stosd
    mov eax,dr7
    mov [edi+8], eax
    stosd
    mov ah,EMSS_OK
    ret
VCPI_ReadDR ENDP

;
; AX=DE09: VCPI write debug registers
;  call with ES:DI buffer pointer. Updates debug registers.
;  (8 dwords, dr0 first, dr4/5 ignored)
;
VCPI_WriteDR PROC
    movzx esi,WORD PTR [ebp].Client_Reg_Struc.Client_ES
    shl esi,4
    movzx edi,di
    add esi,edi
    lodsd
    mov dr0,eax
    lodsd
    mov dr1,eax
    lodsd
    mov dr2,eax
    lodsd
    mov dr3,eax
    add esi,8
    lodsd
    mov dr6,eax
    lodsd
    mov dr7,eax
    mov ah,EMSS_OK
    ret
VCPI_WriteDR ENDP

;
; AX=DE0A: VCPI get 8259A interrupt vector mappings
;  return bx == 1st vector mapping for master 8259A (IRQ0-IRQ7)
;    cx == 1st vector mapping for slave 8259A (IRQ8-IRQ15)
;
VCPI_GetMappings PROC
    mov bx, [wMasterPICBase]
    mov cx, [wSlavePICBase]
    mov word ptr [ebp].Client_Reg_Struc.Client_EBX,bx
    mov word ptr [ebp].Client_Reg_Struc.Client_ECX,cx
    mov ah,EMSS_OK
    ret
VCPI_GetMappings ENDP

; AX=DE0B: VCPI set 8259A interrupt vector mappings
;  entry bx == 1st vector mapping for master 8259A (IRQ0-IRQ7)
;    cx == 1st vector mapping for slave 8259A (IRQ8-IRQ15)
;-- this is meant just as info, the client has to program the PIC itself

VCPI_SetMappings PROC

    mov ecx, [ebp].Client_Reg_Struc.Client_ECX
    mov [wMasterPICBase],bx
    mov [wSlavePICBase],cx
    mov ah,EMSS_OK
    ret
VCPI_SetMappings ENDP

.text$03 ends

.text$02 segment

;--- the following 3 procs must be located in the first page.
;--- If this is no longer possible,
;--- the VCPI shared address space has to be increased.

; VCPI switch V86 mode to protected mode
; inp: AX=DE0C
;     ESI -> linear address of "v86 to protected-mode switch" data,
;            must be in first MB.
; out: GDTR, IDTR, LDTR, TR loaded for client
;     SS:ESP=?HLPSTKSIZE (must provide at least 16 byte space for client)
;     HIWORD(ESP) is cleared
; modifies EAX, SS:ESP (ESI may also be altered according to VCPI docs)
;


VCPI_V86toPM PROC public

    @dprintf ?VCPIXDBG, <"VCPI rm, ax=DE0C, esi=%X cr3=%X cs:eip=%X:%X",10>, esi, dword ptr [esi].V86TOPM.dwCR3,\
        word ptr [esi].V86TOPM.dfCSEIP+4, dword ptr [esi].V86TOPM.dfCSEIP
    mov ecx,[ebp].Client_Reg_Struc.Client_ECX   ;restore client value
    mov ebp,[ebp].Client_Reg_Struc.Client_EBP   ;restore client value

if ?VCPITMPSS
;--- some poorly written VCPI clients expect hiword(esp) to be zero!
;--- So we provide a small 128 byte stack.
;--- SS must be loaded BEFORE the address context is changed!
    mov ax, V86_STACK_SEL
    mov ss, eax
endif

    mov eax,[esi].V86TOPM.dwCR3     ; set client's context *first*
    mov cr3,eax
    mov eax,[esi].V86TOPM.dwIDTOFFS ; set up client's IDT
    lidt fword ptr [eax]
    mov eax,[esi].V86TOPM.dwGDTOFFS ; set up client's GDT
    lgdt fword ptr [eax]
    lldt [esi].V86TOPM.wLDTR        ; set up client's LDT
if ?CLEARTB    

;--- the "busy" flag of the TSS must be cleared, according to VCPI docs, and
;--- this must be done BEFORE the TR register is loaded!

    movzx esp,[esi].V86TOPM.wTR
    and esp,not 111b                ; v5.85: don't assume bits 0+1 of new value for TR are 0!

    mov eax,[eax+2]                 ; EAX == linear address of client's GDT
    and ds:[esp+eax].DESCRIPTOR.bAttr,NOT 2; clear task busy bit in TSS descriptor
endif
    ltr [esi].V86TOPM.wTR           ; set up client's TSS

if ?VCPITMPSS
    mov esp,?HLPSTKSIZE
else
    mov esp,?BASE+?HLPSTKSIZE
endif
    jmp [esi].V86TOPM.dfCSEIP       ; jump to client's entry point


VCPI_V86toPM ENDP

    align 4

; VCPI switch protected mode to v86 mode
;  inp: SS:ESP set for IRETD to V86, PM far call return address to discard;
;       stack must be in shared address space.
;       AX=DE0C
;       DS -> selector containing full shared address space 0-11xxxx
;  out: CR3, GDTR, IDTR, LDTR, TR loaded for server,
;    IRETD will load SS:ESP and all segment registers, then enable v86 mode.
;  modifies: EAX
;
;-- what has to be done is simple:
;-- 1. switch to host context (SS:ESP will stay valid, stack is in 1. MB)
;-- 2. load IDTR, GDTR, LDTR, TR for VCPI host
;-- 3. clear task busy bit in host's TSS descriptor
;-- 4. clear task switch flag in CR0
;-- 5. IRETD will switch to v86 mode, interrupts disabled

VCPI_PMtoV86 PROC

ife ?SHAREDGDT
    mov eax,cs          ; if GDT is in nonshared space, the current
    add eax,8           ; DS cannot be used to access it (TNT DOS extender!)
    mov ds,eax          ; load DS with a copy of FLAT_DATA_SEL
endif
    cli                 ; client should have disabled interrupts, but not all do
    mov eax,[V86CR3]
;--- don't use [ESP+x], because SS may be 16-bit
    add esp,5*4         ; position ESP to EFL+4 on stack
    push 20002h or (V86IOPL shl 12)  ; set flags VM=1, NT=0, IOPL=3, IF=0, TF=0
    sub esp,2*4
    mov cr3,eax
if ?VCPIXDBG
	mov eax,[esp].IRETDV86._Eip
	mov [dbgv.vEIP],eax
	mov eax,[esp].IRETDV86._Cs
	mov [dbgv.vCS],eax
	mov eax,[esp].IRETDV86._Efl
	mov [dbgv.vEFL],eax
	mov eax,[esp].IRETDV86._Esp
	mov [dbgv.vESP],eax
	mov eax,[esp].IRETDV86._Ss
	mov [dbgv.vSS],eax
	mov eax,[esp].IRETDV86._Es
	mov [dbgv.vES],eax
	mov eax,[esp].IRETDV86._Ds
	mov [dbgv.vDS],eax
	mov eax,[esp].IRETDV86._Fs
	mov [dbgv.vFS],eax
	mov eax,[esp].IRETDV86._Gs
	mov [dbgv.vGS],eax
endif
    lgdt fword ptr [GDT_PTR]
    xor eax,eax
    and byte ptr [V86GDT+V86_TSS_SEL+5], NOT 2
    lidt fword ptr [IDT_PTR]
    lldt ax
    mov al,V86_TSS_SEL
    clts
    ltr ax
if ?VCPIXDBG
    mov eax,FLAT_DATA_SEL
    mov ss,eax
    mov esp,dwStackCurr
    @dprintf ?VCPIXDBG, <"VCPI pm, ax=DE0C, rm cs:eip=%X:%X, rm ss:esp=%X:%X", 10>,
        word ptr dbgv.vCS, dbgv.vEIP, word ptr dbgv.vSS, dbgv.vESP
    mov esp, offset dbgv
endif
    iretd

VCPI_PMtoV86 ENDP

;-- put the VCPI PM entry at the very beginning. This entry
;-- must be in the shared address space, and just the first page
;-- is shared!
;-- entry for EMM routines called from protected mode

    align 4

VCPI_PM_Entry PROC

    cmp ax,0de0ch       ; see if switch from protected mode to V86 mode
    je VCPI_PMtoV86    ; yes, give it special handling

; other than de0ch, don't allow anything than de03h,de04h,de05h from PM

    cmp ax,0DE03h
    jb @@INV_CALL
    cmp ax,0DE05h
    ja @@INV_CALL

    pushfd
    push ds             ; have to save segments for p-mode entry
    push es

    pushad

    mov ecx,cs
    add ecx,8
    mov ds,ecx          ; load DS,ES with a copy of FLAT_DATA_SEL
    mov es,ecx

;--- segment registers should *all* be set *before* switching contexts!
;--- why? because GDT of client might be located in unreachable space.
;--- get client SS:ESP + CR3, switch to host stack and context

;--- only VCPI functions 03, 04 and 05 are allowed
;--- which use registers EAX (AH) and EDX only.
;--- NMIs are NOT supposed to occur - they will crash the monitor;
;--- the VCPI client is responsible for masking NMIs!

    cli                 ; don't allow interruptions
    mov ebp, ss
    mov esi, esp
    mov edi, cr3
    mov ebx, [V86CR3]
;--- this sequence cannot be traced, since the new stack is valid only
;--- after CR3 has been set - and the old stack isn't valid with the new CR3.
    mov ss, ecx         ;this move must be before CR3 is switched
    mov esp, [dwStackCurr]
    mov cr3, ebx

    push ebp            ;save client's SS
    push esi            ;save client's ESP
    push edi            ;save client's CR3

;--- SAFEMODE will fully switch to Jemm's context

if ?SAFEMODE
    sub esp,8+8
    sgdt [esp+0]
 if ?SAFETSS
    str [esp+6]
 endif
    sidt [esp+8]
    lgdt fword ptr [GDT_PTR]
    lidt fword ptr [IDT_PTR]
    mov cx, FLAT_DATA_SEL
    mov ss, ecx
    mov ds, ecx
    mov es, ecx
 if ?SAFETSS
    mov cx, TSS_SEL
    ltr cx
 endif
endif

    cld

if ?VCPIDBG
    push eax
    push edx
endif

    movzx ecx,al
    call [VCPI_Call_Table+ECX*4]
if ?VCPIDBG
    mov ebp,esp
    @dprintf ?VCPIDBG, <"VCPI pm, inp: ax=%X edx=%X, out: ax=%X edx=%X",10>, word ptr [ebp+4], dword ptr [ebp+0], ax, edx
    add esp,8
endif

if ?SAFEMODE
    lgdt fword ptr [esp+0]
    lidt fword ptr [esp+8]
 if ?SAFETSS
    mov cx,[esp+6]
    ltr cx
 endif
    add esp,8+8
endif
    pop ecx
if 1
    pop esi
    pop edi
    mov cr3, ecx    ; restore client context *first* and
    mov ss, edi     ; then restore client SS:ESP, thus client's GDT
    mov esp, esi    ; need not be located in shared address space
else
    lss esp,[esp]   ; problem with this code: LSS loads descriptor for SS from client GDT,
    mov cr3, ecx	; and that GDT might be accessible only AFTER CR3 is restored.
endif
    mov [esp].PUSHADS.rEDX,edx
    mov byte ptr [esp].PUSHADS.rEAX+1,ah
    popad
    pop es
    pop ds
    popfd
    retf

@@INV_CALL:
    @dprintf ?VCPIDBG, <"VCPI pm, invalid call ax=%X",10>, ax
    mov ah,EMSS_INVALID_SUBFUNC
    retf

VCPI_PM_Entry   ENDP

.text$02 ends

endif   ;?VCPI

    END
