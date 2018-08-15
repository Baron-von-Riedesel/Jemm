
;--- EMS implementation
;--- EMS 4.0 is Public Domain, originally written by Michael Devore,
;--- extended and modified for Jemm by Japheth 
;--- the EMS 3.2 part is copyrighted and has therefore
;--- been moved into a separate include file (EMS32.INC)

;--- to be assembled with JWasm or Masm v6.1+

    .486P
    .model FLAT

    include jemm.inc        ;common declarations
    include jemm32.inc      ;declarations for Jemm32
    include debug.inc

;--- equates

DEVICE_NAME equ 000Ah   ; offset device name in RSEG

;--- assembly time constants

?MAXPHYSPG  equ 56      ; std=56, max physical pages (don't set below 4!)
?YIELDOPEN  equ 0       ; std=0, 1=yield on handle open
?LIM32      equ 0       ; std=0, 1=support LIM EMS 3.2 only
?SUPP5B     equ 1       ; std=1, 1=support int 67h, ax=5Bxxh

;--- EMS specific constants

    option proc:private
    option dotname

    include external.inc

if ?CODEIN2PAGE
    @seg .text$02,<PAGE>
else
    @seg .text$02,<PARA>
endif
.text$02 ENDS

;   assume SS:FLAT,DS:FLAT,ES:FLAT

@emmpushreg macro
    SUB ESP,4+4
    PUSHAD
    MOV EBP,ESP
    endm
@emmpopreg macro
    mov esp, ebp
    POPAD
    ADD ESP,4+4
    endm

;--- EMS page descriptor
;--- for 4 GB, there are 4096/1.5 = 2731 possible pool descriptor indices

EMSPD struct
wNext   dw ?        ;index next EMSPD
wIndex  dw ?        ;pool descriptor index for EMS page
EMSPD ends

;--- descriptor subindex

EMSPD2 struct
bSubIdx db ?        ;pool descriptor subindex for EMS page 
EMSPD2 ends

;--- alter page map and jump/call structures (55h and 56h)

log_phys_map struct
wLogPage       DW ? ; logical page (handle in DX)
wPhysPage      DW ? ; physical pages if AL=0, segments if AL=1
log_phys_map ends

map_and_jump struct
target_address      DD ? ; far16 jump address
new_page_map_len    DB ? ; items in new_page_map_ptr
new_page_map_ptr    DD ? ; far16 pointer to log_phys_map structure
map_and_jump ends

map_and_call struct
                    map_and_jump <?>
old_page_map_len    db ? ; items in old_page_map_ptr
old_page_map_ptr    dd ? ; far16 pointer to log_phys_map structure
map_and_call ends

;--- structure for EMS function 57h

EMM57 struct
e57_dwSize  DD ?    ; +0  size of region
e57_bSrcTyp DB ?    ; +4  src memory type
e57_wSrcHdl DW ?    ; +5  src handle
e57_wSrcOfs DW ?    ; +7  src ofs
e57_wSrcSeg DW ?    ; +9  src segm./log. page
e57_bDstTyp DB ?    ; +11 dst memory type
e57_wDstHdl DW ?    ; +12 dst handle
e57_wDstOfs DW ?    ; +14 dst ofs
e57_wDstSeg DW ?    ; +16 dst segm./log. page
EMM57 ends

;--- structure for EMS function 59h

EMM59 struct
e59_pgsize  dw ?    ;raw page size in paragraphs
e59_altsets dw ?    ;number of alternate register sets
e59_sizcont dw ?    ;size of mapping context save area in bytes
e59_dmasets dw ?    ;dma register sets
e59_dmaflgs dw ?    ;dma flags
EMM59 ends

.text$01 SEGMENT

;--- EMS variables

EMSHandleTable  DD  0   ; table of EMS handles (4 bytes/handle)
EMSNameTable    DD  0   ; table of EMS handle names (8 bytes/handle)
EMSStateTable   DD  0   ; table of EMS status saves (16 bytes/handle)
EMSPagesMax     DD  0   ; max EMS pages (default 2048)
EMSPagesUsed    DD  0   ; used EMS pages

EMSPage2Segm    DB  ?MAXPHYSPG DUP (0)  ; segments mapped to phys.pgs
;EMSMappedPages DW  ?MAXPHYSPG DUP (-1) ; log. EMS pgs mapped to phys. pgs

    align 4

;--- table of EMS page descriptors (EMSPD), one item for each EMS page
;--- initialized with -1

EMSPageAllocationStart DD   0
EMSPageAllocationEnd   DD   0

emm59_ EMM59 <1024,0,0,0,0>
if ?SUPP5B
mapptr          DD 0    ; pointer supplied by "OS"
endif

bEmsPhysPages   DB  0   ; current physical pages
bPagesConv      DB  0   ; physical pages in conv. memory
bNoEMS          DB  0   ; flags no EMS services
bNoFrame        DB  0   ; flags no page frame
bNoVCPI         DB  0   ; flags no VCPI services

;--- this is 16-bit code which is copied onto the client's stack
;--- to restore the page mapping in int 67h, ah=56h

clproc label byte
    db 1Eh          ; 0 push ds
    db 51h          ; 1 push cx
    db 52h          ; 2 push dx
    db 56h          ; 3 push si
    db 0B9h         ; 4 mov cx,zzzz
_clcx dw 0          ; 5
    db 0BAh         ; 7 mov dx,zzzz
_cldx dw 0          ; 8
    db 0BEh         ; A mov si,yyyy
_clsi dw 0          ; B
    db 068h         ; D push xxxx
_clds dw 0          ; E
    db 1Fh          ; 0 pop ds
    db 0B8h         ; 1 mov ax,50wwh
_clal db 00,50h     ; 2
    db 0CDh, 67h    ; 4 int 67h
    db 5Eh          ; 6 pop si
    db 5Ah          ; 7 pop dx
    db 59h          ; 8 pop cx
    db 1Fh          ; 9 pop ds
    db 0CAh         ; A retf sizeclproc
    dw sizeclproc   ; B
    db 0            ; D alignment byte
sizeclproc equ $ - offset clproc

.text$01 ends

.text$03 segment

    align 4

EMS_Call_Table label dword
    Dd EMS_GET_STATUS           ; 40h
    Dd EMS_GET_PAGE_FRAME_ADDRESS       ;41h
    Dd EMS_GET_UNALLOCATED_PAGE_COUNT   ;42h
    Dd EMS_ALLOCATE_PAGES       ; 43h
    Dd EMS_MAP_HANDLE_PAGE      ; 44h (map/unmap a page)
    Dd EMS_DEALLOCATE_PAGES     ; 45h
    Dd EMS_GET_VERSION          ; 46h
    Dd EMS_SAVE_PAGES           ; 47h
    Dd EMS_RESTORE_PAGES        ; 48h
    Dd EMS_NOT_IMPL             ; 49h (get io port addresses)
    Dd EMS_NOT_IMPL             ; 4ah (get translation array)
    Dd EMS_GET_OPEN_HANDLES_COUNT       ; 4bh
    Dd EMS_GET_PAGES_ONE_HANDLE ; 4ch
    Dd EMS_GET_PAGES_ALL_HANDLES; 4dh
    Dd EMS_GET_SET_PAGE_MAP     ; 4eh
ife ?LIM32
    Dd ems4_get_set_partial_page_map    ; 4fh
    Dd ems4_map_multiple        ; 50h
    Dd ems4_realloc             ; 51h
    Dd ems4_attribute           ; 52h
    Dd ems4_get_set_handle_name ; 53h
    Dd ems4_get_handle_info     ; 54h
    Dd ems4_alter_map_jump      ; 55h
    Dd ems4_alter_map_call      ; 56h
    Dd ems4_move_memory         ; 57h
    Dd ems4_get_mappable_info   ; 58h
    Dd ems4_get_config          ; 59h
    Dd ems4_allocate_pages      ; 5ah
    Dd ems4_alt_map_reg_set     ; 5bh
    Dd EMS_NOT_IMPL             ; 5ch (4: prepare EMS for warm boot)
    Dd EMS_NOT_IMPL             ; 5dh (4: enable/disable OS functions)
endif
EMS_MAX equ ($ - EMS_Call_Table) / 4

    align 4

;--- breakpoint: if int 67h vector is hooked in real-mode, the hooker code
;--- is called and will finally met a breakpoint which will get us here.

Int67_V86Entry proc public
    call Simulate_Iret
    add esp,4       ;skip return address
    mov esi,[ebp].Client_Reg_Struc.Client_ESI
    mov edx,[ebp].Client_Reg_Struc.Client_EDX
    mov eax,[ebp].Client_Reg_Struc.Client_EAX
    JMP EMM_ENTRY_2
Int67_V86Entry endp

Int67_Indirect:
    @emmpopreg
    push 67h
    jmp V86_Monitor

    align 4
;
; Here starts the Expanded Memory Manager (EMM) Version 4.0
;

Int67_Entry PROC public

    @emmpushreg

    MOV ECX,SS      ; address everything
    MOV DS,ECX
    MOV ES,ECX

if ?V86DBG
    @DbgOutS <"Int 67h in v86-mode, CS:EIP=">,1
    @DbgOutW <word ptr [ebp].V86FRAME.fCS>,1
    @DbgOutS <":">,1
    @DbgOutD [ebp].V86FRAME.fEIP,1
    @DbgOutS <" EBP=">,1
    @DbgOutD ebp,1
    @DbgOutS <" AX=">,1
    @DbgOutW ax,1
    @DbgOutS <10>,1
endif

    mov ecx,[dwRSeg]
    cmp cx,ds:[67h*4+2]     ;IVT vector 67h modified?
    jnz Int67_Indirect

    mov esp,[dwStackCurr]

EMM_ENTRY_2::

    CLD

if ?VCPI
    cmp ah,0deh         ; see if VCPI function
    jne @@not_vcpi_api
    cmp al,0Ch
    jz VCPI_V86toPM
    jnc @@vcpi_inv_call ; invalid VCPI call
    movzx ecx,al
    cmp [bNoVCPI],0     ; check if VCPI turned off
    jne @@vcpi_inv_call ; yes, return invalid code, flags VCPI not present for 0de00h
  if ?VCPIDBG
    @DbgOutS <"VCPI rm, in: ax=">,1
    @DbgOutW <word ptr [ebp].Client_Reg_Struc.Client_EAX>,1
    @DbgOutS <" edx=">,1
    @DbgOutD [ebp].Client_Reg_Struc.Client_EDX,1
  endif
    call [VCPI_Call_Table+ECX*4]
  if ?VCPIDBG
    @DbgOutS <", out: ax=">,1
    @DbgOutW ax,1
    @DbgOutS <" edx=">,1
    @DbgOutD edx,1
    @DbgOutS <10>,1
  endif
    mov [ebp].Client_Reg_Struc.Client_EDX, edx
    mov byte ptr [ebp].Client_Reg_Struc.Client_EAX+1,ah
    jmp @@byeemsx
    align 4
@@not_vcpi_api:
endif

    MOVZX ECX,AH              ; check permitted range
    SUB CL,40H
    JB @@emm_inv_call
    CMP CL,EMS_MAX
    JAE @@emm_inv_call
if ?EMSDBG
    @DbgOutS <"EMS in: ax=">,1
    @DbgOutW <word ptr [ebp].Client_Reg_Struc.Client_EAX>,1
    @DbgOutS <" bx=">,1
    @DbgOutW <word ptr [ebp].Client_Reg_Struc.Client_EBX>,1
    @DbgOutS <" dx=">,1
    @DbgOutW <word ptr [ebp].Client_Reg_Struc.Client_EDX>,1
endif
    CALL [EMS_Call_Table+ECX*4]
if ?EMSDBG
    @DbgOutS <", out: ax=">,1
    @DbgOutW ax,1
    @DbgOutS <" bx=">,1
    @DbgOutW bx,1
    @DbgOutS <" dx=">,1
    @DbgOutW dx,1
    @DbgOutS <10>,1
endif
    mov word ptr [ebp].Client_Reg_Struc.Client_EBX,bx
    mov word ptr [ebp].Client_Reg_Struc.Client_EDX,dx
@@byeems:
    mov byte ptr [ebp].Client_Reg_Struc.Client_EAX+1,ah
@@byeemsx:
    @emmpopreg
    IRETD

@@vcpi_inv_call:
if ?VCPIDBG
    @DbgOutS <"VCPI invalid function, ax=">,1
    @DbgOutW ax,1
    @DbgOutS <10>,1
    MOV ah,EMSS_INVALID_FUNCTION
    JMP @@byeems
endif

@@emm_inv_call:
if ?EMSDBG
    @DbgOutS <"EMS invalid function, ax=">,1
    @DbgOutW ax,1
    @DbgOutS <10>,1
endif
    MOV ah,EMSS_INVALID_FUNCTION
    JMP @@byeems
        
Int67_Entry ENDP

    include EMS32.INC   ;include the copyrighted part (EMS 3.2)

_ret:   ;this label belongs to EMS_MAP_REL_PAGE
    ret

; Map EMS page in DX:BX to physical page in AL
; called by EMS function 44h
; BX=-1 -> unmap page

EMS_MAP_REL_PAGE proc
    call EMS_get_abs_page ;get absolute page in BX
    jc _ret
EMS_MAP_REL_PAGE endp   ;fall thru!!!

; Map an EMS page to a physical page
; inp: AL = physical EMS page (0 - (bEmsPhysPages - 1))
;      BX = absolute EMS page (or -1 to unmap)
; modifies EDI, ECX, EAX
; the logical page in BX might belong to no handle!

EMS_MAP_ABS_PAGE PROC
    movzx   eax,al
    mov     al, [EMSPage2Segm+EAX]

    @GETPTEPTR EDI, EAX*4+?PAGETAB0 ; EDI -> PTE
    SHL     eax, 12             ; C0 -> C0000, C4-> C4000

EMS_MAP_ABS_PAGE ENDP   ;fall through!!!

; Map an (absolute) EMS page anywhere in address space
; BX = EMS abs. page
; EDI == ptr to PTE
; EAX == linear address
; modifies edi, ecx, eax

EMS_MAP_ABS_PAGE_EX proc

    AND BH,BH               ; unmap the page?
    JS @@SET

    MOVZX ECX,BX            ; get the EMSPD for the page in ECX
    shl ecx,2
    add ecx, [EMSPageAllocationStart]
    movzx ecx,[ecx].EMSPD.wIndex; get pool descriptor index

    cmp cx,-1   ;bad pointer?
    jz @@SET    ;then unmap this page

    movzx eax, bx
    add eax,[EMSPageAllocationEnd]
    movzx eax,[eax].EMSPD2.bSubIdx  ;pool descriptor subindex
    call Pool_GetPhysAddr           ;convert index+offset into phys addr

@@SET:
    OR EAX,7           ; Statusbits: R/W=1,U/S=1,P=1
if 0
    mov cl,4
@@LOOP:
    MOV [EDI],EAX       ; Register the new physical Address of
    ADD EDI,4           ; window
    ADD EAX,4096        ; Process next 4K-page
    DEC CL
    JNZ @@LOOP
else
    mov ecx,1000h
    stosd
    add eax,ecx
    stosd
    add eax,ecx
    stosd
    add eax,ecx
    stosd
endif
    RET
    align 4
    
EMS_MAP_ABS_PAGE_EX endp

FlushTLB proc
if 0
    cmp [bNoInvlPg],0
    jz @@noinvlpg
endif
    MOV EAX,CR3         ; flush TLB
    MOV CR3,EAX
@@noinvlpg:
    ret
    align 4
FlushTLB endp

;--- get EMS absolute page
;--- inp DL:BX = handle:logical page
;--- out NC ok, EBX = absolute page (index into EMSPD array)
;--- C if failure, then error code in AH
;--- modifies ECX, EDI

EMS_get_abs_page proc
    AND BH,BH                   ; bx < 0 means unmap this phys. page
    JS @@OK
    movzx ecx, bx
    movzx ebx, dl
    mov edi,[EMSHandleTable]
    mov bx,[edi+ebx*4].EMSHD.ehd_wIdx
    MOV EDI,[EMSPageAllocationStart]
    inc ecx
    jmp @@test
    align 4
@@nextitem:
    mov bx,[edi+ebx*4].EMSPD.wNext
@@test:
    cmp bx,-1
    loopnz @@nextitem
    jz @@fail
@@OK:
    clc
    ret
@@fail:
    MOV AH,EMSS_LOG_PAGE_INVALID    ; "logical page out of reserved area"
    stc
    ret
    align 4
EMS_get_abs_page endp

;--- check if segment in AX is a valid (physical) page
;--- if yes, return NC and convert segment to physical page in AL

EMS_Segm2Phys proc
    and al,al           ;must begin on a page boundary
    jnz @@notvalid
    mov al,ah
    push ecx
    push edi
    movzx ecx, [bEmsPhysPages]
    mov edi, offset EMSPage2Segm
    mov ah,cl
    repnz scasb
    pop edi
    jnz @@notvalid2
    mov al, ah
    dec al
    sub al, cl
    pop ecx
    ret
@@notvalid2:
    pop ecx
@@notvalid:
    mov ah,EMSS_PHYS_PAGE_INVALID
    stc
    ret
    align 4
EMS_Segm2Phys endp
    
;--- begin EMS 4.0 functions

ife ?LIM32

;
; 674F: AH = 4Fh: Get & Set partial Map
; AL = 0,1,2 
; AL = 0 (get map), DS:SI -> map to get, ES:DI -> status to receive
; AL = 1 (set map), DS:SI -> map to restore
; AL = 2 (get size), items in BX, returns size of map in AL
; the list for sub function 0 DS:SI points to has following structure:
; WORD   : items in list
; WORD[] ; segment! addresses for which to get the map info 
; the output list ES:DI points to (function 0) has following structure:
; WORD   : items in list
;  BYTE  : page no
;  WORD  ; abs EMS page mapped (or -1)

ems4_get_set_partial_page_map PROC

    cmp al,2
    ja bad_subfunc
    jz @@getsize
    movzx ecx,WORD PTR [ebp].Client_Reg_Struc.Client_DS
    shl ecx,4
    movzx esi, si
    add esi,ecx
    
    cmp al,1
    jz @@setmap

;--- ax=4F00h (get map)

    movzx ecx,WORD PTR [ebp].Client_Reg_Struc.Client_ES
    shl ecx,4
    movzx edi, di
    add edi,ecx

    lodsw
    movzx eax,ax
    movzx ecx, [bEmsPhysPages]
    cmp eax,ecx
    ja @@failA3
    mov ecx, eax
    stosw
    jecxz @@done00
@@nextsegm:
    lodsw
    call EMS_Segm2Phys  ;convert segment to phys page
    jc @@fail
    movzx eax,al
    push ecx
    movzx ecx, byte ptr [esi-1]
    @GETPTEPTR ecx,ECX*4+?PAGETAB0
    mov ecx,[ecx]
    mov cl,0
    or eax,ecx
    stosd
    pop ecx
    loop @@nextsegm
@@done00:
    mov ah,EMSS_OK
    ret
@@failA3:
@@failA3_1:
    mov ah,0A3h ;segment count exceeds mappable pages
@@fail:
    ret

;--- ax=4F01h (set map)

@@setmap:
    lodsw
    movzx eax,ax
    movzx ecx, [bEmsPhysPages]
    cmp eax,ecx
    ja @@failA3
    mov ecx, eax
    jmp EMS_RestorePagesFromEsi

;--- ax=4F02h (get size of save area)

@@getsize:
    cmp bh,0
    jnz @@failA3_1
    cmp bl,[bEmsPhysPages]
    ja @@failA3_1
    mov al, bl
    shl al,2        ;4 bytes (makes Kyrandia 3 work [better]!?)
    add al,2        ;2 extra bytes for size
    mov byte ptr [ebp].Client_Reg_Struc.Client_EAX, al
    mov ah, EMSS_OK
    ret
    align 4

ems4_get_set_partial_page_map ENDP

; 6750:
; AH = 50h: EMS 4.0 map multiple pages
; DX = handle
;  DS:SI -> mapping array
;  CX = items in array (ecx is destroyed, reload it from stack)
;  structure of mapping array:
;  WORD logical page (or -1 to unmap page)
;  WORD physical page (AL=0) or segment address (AL=1)

ems4_map_multiple PROC

    cmp al,1
    ja  bad_subfunc

    movzx ecx, word ptr [ebp].Client_Reg_Struc.Client_ECX   ; load EMM entry CX value
    movzx edi, word ptr [ebp].Client_Reg_Struc.Client_DS
    shl edi,4
    movzx esi,si
    add edi,esi     ; edi -> map address buffer

ems4_map_multiple_edi::

; perform handle check here so that stack return address isn't blown

    call EMS_TEST_HANDLE
    mov esi, edi

    push ebx
    push eax
    jecxz @@success
@@multi_loop:
    mov bx,[esi+0]
    mov ax,[esi+2]
    add esi,4
    cmp byte ptr [esp+0],1  ;subfunction 1?
    jne @@mappage
    call EMS_Segm2Phys      ;convert segment in AX to a page no in AL
    jc  @@multi_out
@@mappage:
    push ecx
    call EMS_MAP_REL_PAGE   ;map page in DX:BX to phys page in AL
    pop ecx
    jc @@multi_out
    loop @@multi_loop
    call FlushTLB
@@success:
    MOV ah,EMSS_OK
@@multi_out:
    mov [esp+1],ah
    pop eax
    pop ebx
    ret

ems4_map_multiple ENDP

; 6751:
; AH = 51h: EMS 4.0 reallocate pages for handle
; DX = handle
; BX = new page count for handle
; out: BX=pages assigned to handle
;
ems4_realloc PROC

    movzx ecx, bx           ; save new pages
    call EMS_GET_PAGES_ONE_HANDLE   ;get curr pages in EBX, ESI->EMSHD
    and ah,ah
    jnz exit

    mov edi,[EMSPageAllocationStart]

    cmp ecx, ebx            ; check new page count against original
    jb @@shrinkalloc
    je @@realloc_success    ; no change needed

    sub ecx, ebx            ; get no of additional pages

    call GetFreeEMSPages
    cmp ecx,eax
    ja @@toomany

    movzx eax,[esi].EMSHD.ehd_wIdx
    jmp @@test
@@nextitem:
    lea esi,[edi+eax*4]
    mov ax,[esi].EMSPD.wNext
@@test:
    cmp ax,-1
    jnz @@nextitem

    call AllocateEMSPages   ; allocate ECX pages
    jnc @@realloc_success
@@toomany:
    mov ah,EMSS_OUT_OF_FREE_PAGES
exit:
    ret

; trim off the trailing pages
; ECX=new page count, EBX=old page count

@@shrinkalloc:
    xor ebx, ebx
    mov eax, ebx
    jmp @@test2
@@nextitem2:    
    lea esi,[edi+eax*4]
    inc ebx
@@test2:    
    mov ax,[esi].EMSPD.wNext
    cmp ax,-1
    jz @@realloc_success
    cmp ebx, ecx
    jnz @@nextitem2
    jmp @@test3
@@freenext:
    lea esi,[edi+eax*4]
    call ReleaseEMSPage     ;preserves registers
@@test3:    
    mov ax,-1
    xchg ax,[esi].EMSPD.wNext
    cmp ax,-1
    jnz @@freenext

@@realloc_success:
    mov ebx,[ebp].Client_Reg_Struc.Client_EBX
    mov ah,EMSS_OK
    ret

ems4_realloc ENDP

; 6752
; AH = 52h: EMS 4.0 attribute related
; AL = 0/1/2, DX=handle, BL=0/1
; AL=2:
; out AL=attr

ems4_attribute PROC
    cmp al,2
    jb  @@get_set_attribute
    ja  bad_subfunc ; this is an invalid subfunction

;-- AL==2 and AL==0

@@is_volatile:
    mov byte ptr [ebp].Client_Reg_Struc.Client_EAX, 0   ; al == 0, volatile attribute only
    mov ah,EMSS_OK
    ret

;-- AL==1

@@get_set_attribute:
    call EMS_TEST_HANDLE; only valid handles please
    or al,al            ; 0 is get, 1 is set
    jz @@is_volatile    ; only volatile here (none survive warm reboot)
    or bl,bl            ; 0 is "make volatile" (true anyway)
    jnz @@cannot_make_nonvolatile
    mov ah,EMSS_OK
    ret
@@cannot_make_nonvolatile:
    mov ah,EMSS_FEATURE_UNSUPP  ; feature not supported
    ret
ems4_attribute ENDP

; 6753:
; AH = 53h: EMS 4.0 get/set handle name
; AL = 0: get handle name in ES:DI
; AL = 1: set handle name in DS:SI
; DX = handle
;
ems4_get_set_handle_name PROC
    cmp al,1
    ja  bad_subfunc ; this is an invalid subfunction
    jz  @@ems4_setname

    call EMS_TEST_HANDLE
    movzx esi,WORD PTR [ebp].Client_Reg_Struc.Client_ES
    shl esi,4
    movzx edi,di
    add edi,esi     ; edi -> handle name buffer address (dest)
    mov esi, [EMSNameTable]
    movzx ecx,dl    ; handle (index)
    lea esi, [esi+ecx*8]
    jmp @@ems4_getsetname

@@ems4_setname:
    movzx edi, si   ;ESI will be destroyed by next call
    call EMS_TEST_HANDLE
    movzx esi,WORD PTR [ebp].Client_Reg_Struc.Client_DS
    shl esi,4
    add esi,edi     ; esi -> handle name (source)

;--- resetting the name is always valid

    mov eax,[esi+0]
    or eax,[esi+4]
    jz @@reset_name

;--- check for a handle which already has this name    
;--- return status A1h if one exists
;--- don't care if the handle found is the same as the current one

    mov edi,esi
    push esi
    call find_handle_by_name_int
    pop esi
    and ah,ah   ;was a handle with this name found?
    mov ah,0A1h
    jz @@failed
@@reset_name:    

    mov edi, [EMSNameTable]
    movzx ecx,dl    ; handle (index)
    lea edi, [edi+ecx*8]

@@ems4_getsetname:
    movsd
    movsd
    mov ah,EMSS_OK
@@failed:    
    ret

ems4_get_set_handle_name ENDP

; 6754:
; AH = 54h: EMS 4.0 get various handle info
;
; AL = 0: get handle directory into ES:DI
; AL = 1: search handle by name in DS:SI, return handle in DX
; AL = 2: get total handles in BX

ems4_get_handle_info PROC
    cmp al,1
    jb getallhand
    je @@find_handle_by_name
    cmp al,2
    ja bad_subfunc ; this is an invalid subfunction

;-- AL=2

    mov bx,EMS_MAX_HANDLES
    mov ah,EMSS_OK
    ret

; AL=0, write handle directory to caller buffer
; return in AL number of open handles
; return in ES:DI array of:
;   WORD handle
;   QWORD name

getallhand:
    movzx   esi,WORD PTR [ebp].Client_Reg_Struc.Client_ES
    shl esi,4
    movzx edi,di
    add esi,edi
    mov edi, [EMSHandleTable]
    xor eax, eax        ; AL will be count of open handles
    xor ecx, ecx
    push edx
    mov edx, [EMSNameTable]
@@scan_handles:
    test [edi].EMSHD.ehd_bFlags, EMSH_USED
    jz @@free_handle
    inc eax

    mov [esi+0],cx
    push DWORD PTR [edx+ecx*8+0]    ; copy handle name
    pop DWORD PTR [esi+2]
    push DWORD PTR [edx+ecx*8+4]
    pop DWORD PTR [esi+6]
    add esi,10

@@free_handle:
    add edi,size EMSHD
    inc ecx
    cmp cl, EMS_MAX_HANDLES
    jb @@scan_handles
    pop edx
    mov byte ptr [ebp].Client_Reg_Struc.Client_EAX, al
    mov ah,EMSS_OK
    ret

;--- AL=1 search handle by name
;--- in: DS:SI->handle name
;--- out: DX=handle

@@find_handle_by_name:

    movzx edi,WORD PTR [ebp].Client_Reg_Struc.Client_DS
    shl edi,4
    movzx esi,si
    add edi,esi
find_handle_by_name_int::   ;find handle by name, edi=name
    push ebx
    mov eax,[edi+0]     ; fetch to-be-searched name
    mov ebx,[edi+4]     ; (8 byte binary string)
if 0 ;MS Emm386 allows to search a handle with no name!
    or eax,eax
    jnz @@valid_search_term
    or ebx,ebx
    jz @@invalid_search_term
@@valid_search_term:
endif
    xor ecx,ecx
    mov edi, [EMSNameTable]
    mov esi, [EMSHandleTable]
@@scan_for_name:
    test [esi].EMSHD.ehd_bFlags, EMSH_USED
    jz @@skipitem
    cmp [edi+0],eax
    jnz @@skipitem
    cmp [edi+4],ebx         ; Note that open handles do not have
    jz @@found_handle      ; to have a name.
@@skipitem:
    add esi,size EMSHD
    add edi,8
    inc ecx
    cmp cl,EMS_MAX_HANDLES
    jb @@scan_for_name
    pop ebx
    mov ah,0a0h             ; "no corresponding handle found"
    ret
@@found_handle:
    pop ebx
    mov edx,ecx
    mov ah,EMSS_OK
    ret
if 0
@@invalid_search_term:
    pop ebx
    mov ah,0a1h         ; "handle found had no name"
    ret
endif

ems4_get_handle_info ENDP

;--- client DS:SI -> map_and_jump
;--- AL=0 -> physical page numbers
;--- AL=1 -> segment addresses

ems4_map_new_pagemap proc
    movzx edi, word ptr [ebp].Client_Reg_Struc.Client_DS
    shl edi,4
    movzx esi,si
    add edi,esi     ; edi -> map address buffer
    movzx ecx, word ptr [edi].map_and_jump.new_page_map_ptr+0
    movzx esi, word ptr [edi].map_and_jump.new_page_map_ptr+2
    push edi
    shl esi, 4
    add esi, ecx
    movzx ecx, [edi].map_and_jump.new_page_map_len
    mov edi, esi
    call ems4_map_multiple_edi  ;map ECX pages from EDI, DX=handle, AL=type
    pop edi
    and ah,ah
    ret
ems4_map_new_pagemap endp

; 6755:
; AH = 55h: EMS 4.0 alter page map and jump
; AL = 0/1
; DX = handle
; DS:SI -> map_and_jump structure

ems4_alter_map_jump proc
    call ems4_map_new_pagemap
    jnz @@failed
    mov ecx,[edi].map_and_jump.target_address
    mov word ptr [ebp].Client_Reg_Struc.Client_EIP, cx
    shr ecx, 16
    mov [ebp].Client_Reg_Struc.Client_CS, ecx
@@failed:
    ret
ems4_alter_map_jump endp

; 6756:
; AH = 56h: EMS 4.0 alter page map and call
; AL = 0/1/2
; DX = handle
; if AL=0/1: [in] DS:SI -> map_and_call structure ()
; if AL=2: [out] BX = additional stack space required

ems4_alter_map_call proc
    cmp al,2
    jz @@getstackspace

    call ems4_map_new_pagemap
    jnz @@failed

if 0    ; nested execution consumes ring 0 stack, which is to avoid

;--- prepare nested execution
;--- and run the client proc

    push edx
    push eax
    call Begin_Nest_Exec
    movzx edx,word ptr [edi].map_and_call.target_address+0
    movzx ecx,word ptr [edi].map_and_call.target_address+2
    call Simulate_Far_Call
    call Resume_Exec
    call End_Nest_Exec
    pop eax
    pop edx

;--- set old state

    movzx ecx, [edi].map_and_call.old_page_map_len
    movzx esi, word ptr [edi].map_and_call.old_page_map_ptr+0
    movzx edi, word ptr [edi].map_and_call.old_page_map_ptr+2
    shl edi, 4
    add edi, esi
    call ems4_map_multiple_edi
@@failed:
    ret
@@getstackspace:
    mov bx, 4
    ret

else

;--- this implementation copies 16-bit code onto the client's stack.
;--- this code calls int 67h, ah=50h (map multiple pages).

    mov esi, offset clproc
    mov al, byte ptr [ebp].Client_Reg_Struc.Client_EAX
    mov [esi+(_clal-clproc)],al
    movzx eax,[edi].map_and_call.old_page_map_len
    mov [esi+(_clcx-clproc)],ax
    mov [esi+(_cldx-clproc)],dx
    mov eax,[edi].map_and_call.old_page_map_ptr
    mov [esi+(_clsi-clproc)],ax
    shr eax,16
    mov [esi+(_clds-clproc)],ax

    push edi
    movzx ecx,word ptr [ebp].Client_Reg_Struc.Client_ESP
    movzx edi,word ptr [ebp].Client_Reg_Struc.Client_SS
    push edi
    shl edi, 4
    sub ecx, sizeclproc
    push ecx
    mov word ptr [ebp].Client_Reg_Struc.Client_ESP,cx
    add edi, ecx
    mov ecx, sizeclproc
    rep movsb
    pop eax
    pop ecx
    pop edi
    push edx
    mov edx,eax
    call Simulate_Far_Call
    mov cx,word ptr [edi].map_and_jump.target_address+2
    movzx edx,word ptr [edi].map_and_jump.target_address+0
    call Simulate_Far_Call
    pop edx
    mov ah,EMSS_OK
@@failed:    
    ret

@@getstackspace:
    mov bx, sizeclproc+4
    ret

endif
    align 4

ems4_alter_map_call endp

;-------------------------------------------------------------
; 6757:
; AH = 57h: EMS 4.0 move/exchange memory region
; AL = 0: move memory region
; AL = 1: exchange memory region
; DS:SI -> EMM57

;-- this function must work even if no EMS page frame is defined!
;-- EMS regions may overlapp!

E57REG struct
e57_bTyp DB ?   ; +0  memory type
e57_wHdl DW ?   ; +1  handle
e57_wOfs DW ?   ; +3  ofs
e57_wSeg DW ?   ; +5  segm./log. page
E57REG ends

;--- memory type:
;--- 00: conv. memory
;--- 01: expanded memory
;--- handle:
;--- == NULL: conv. memory
;--- <> NULL: EMS handle

;--- locations ebp+xx are ok to store temp values
;--- but it isn't safe to store something there
;--- if interrupts are enabled!

RegionSrc   equ <ebp.Client_Reg_Struc.Client_Error>
pPTE        equ <ebp-4>
regSize     equ <ebp-8>
linAddr     equ <ebp-12>

ems4_move_memory PROC

    cmp al,1
    ja bad_subfunc ; this is an invalid subfunction
    movzx edi,WORD PTR [ebp].Client_Reg_Struc.Client_DS
    movzx esi,si
    shl edi,4
    add edi,esi     ; edi -> EMS region buffer address

if ?EMSDBG
    @DbgOutS <"EMM 57h: siz=">,1
    @DbgOutD [edi].EMM57.e57_dwSize,1
    @DbgOutS <", src=">,1
    @DbgOutB [edi].EMM57.e57_bSrcTyp,1
    @DbgOutS <"/">,1
    @DbgOutW [edi].EMM57.e57_wSrcHdl,1
    @DbgOutS <"/">,1
    @DbgOutW [edi].EMM57.e57_wSrcSeg,1
    @DbgOutS <"/">,1
    @DbgOutW [edi].EMM57.e57_wSrcOfs,1
    @DbgOutS <", dst=">,1
    @DbgOutB [edi].EMM57.e57_bDstTyp,1
    @DbgOutS <"/">,1
    @DbgOutW [edi].EMM57.e57_wDstHdl,1
    @DbgOutS <"/">,1
    @DbgOutW [edi].EMM57.e57_wDstSeg,1
    @DbgOutS <"/">,1
    @DbgOutW [edi].EMM57.e57_wDstOfs,1
endif

    mov ecx,[edi].EMM57.e57_dwSize
    test ecx,ecx
    je @@ok                        ; always succeeds if no bytes are moved
    mov ah,EMSS_REGLEN_EXCEEDS_1MB
    cmp ecx,65536*16                ; does region length exceed 1M?
    ja @@exit

    mov eax,[PageMapHeap]
    mov [regSize], ecx
    mov [pPTE], eax

; process region src + dst information

    lea edi,[edi+EMM57.e57_bSrcTyp]
    mov al,2    
@@nextreg:
    mov [RegionSrc],ebx
    movzx ecx,[edi].E57REG.e57_wOfs
    movzx ebx,[edi].E57REG.e57_wSeg
    cmp [edi].E57REG.e57_bTyp,1     ;0 = conv, 1 = expanded
    jb @@calc_conv
    mov ah,EMSS_TYPE_UNDEFINED
    jnz @@exit

; destination is EMS, test if handle is valid

    mov dx, [edi].E57REG.e57_wHdl
    call EMS_TEST_HANDLE

; check if specified offset is outside logical page (must be < 4000h)

    mov ah,EMSS_OFFS_EXCEEDS_PGSIZ  ; preload error code
    test ch,0C0h
    jnz @@exit

;--- map in EMS pages 
;--- ecx = "offset"
;--- DX:BX = EMS page start

    push eax             ;save AL counter
    add ecx,[regSize]
    mov esi,[pPTE]
    mov eax, esi
    sub eax, ?SYSLINEAR+?PAGETABSYS
    shl eax, 10
    add eax, ?SYSBASE
    add ecx, eax        ;let ecx point to end of region
    mov [linAddr],eax
@@nextpagetomap:
    pushad
    call EMS_get_abs_page;get abs page of DX:BX in BX
    jc @@map_failed
    mov edi, esi
    call EMS_MAP_ABS_PAGE_EX     ;requires EAX,BX,EDI to be set
    popad
    inc ebx             ;next EMS page
    add eax, 4000h      ;proceed with linear address
    add esi, 4*4        ;proceed with PTE pointer
    cmp eax,ecx
    jb @@nextpagetomap
    mov [pPTE],esi
    call FlushTLB
    mov ebx,[linAddr]
    movzx ecx, [edi].E57REG.e57_wOfs
    pop eax
    add ebx, ecx
    jmp @@regdone

@@map_failed:
    popad
    pop eax
    mov ah,EMSS_LENGTH_EXCEEDED
    jmp @@exit

@@calc_conv:
    shl ebx,4       ; convert seg to memory offset
    add ebx,ecx
    mov ah,EMSS_MBBOUNDARY_CROSSED  ; conv memory region must not exceed 1 MB boundary
    mov ecx, [regSize]
    add ecx, ebx
    cmp ecx, 100000h
    ja  @@exit
@@regdone:
    add edi,size E57REG
    dec al
    jnz @@nextreg
    lea edx, [edi-sizeof EMM57]

;--- both regions processed
;--- dest address in EBX, src in RegionSrc

    mov ecx, [regSize]
    mov esi, [RegionSrc]
    mov edi, ebx

; if src and dest are EMS, test if they overlapp

    cmp edi, 100000h       ; is dst expanded memory?
    jb @@nooverlapp
    cmp esi, 100000h       ; is src expanded memory?
    jb @@nooverlapp

    mov ax, [edx].EMM57.e57_wSrcHdl
    cmp ax, [edx].EMM57.e57_wDstHdl ; are handles equal?
    jnz @@nooverlapp

    movzx eax, [edx].EMM57.e57_wDstSeg
    movzx ebx, [edx].EMM57.e57_wSrcSeg
    shl eax, 14
    shl ebx, 14
    or ax, [edx].EMM57.e57_wDstOfs
    or bx, [edx].EMM57.e57_wSrcOfs

;--- the problem case is:
;--- source < destination AND source + size > destination

    cmp ebx, eax        ; source < destination?
    jnc @@nooverlapp    ; no, use std copy
    add ebx, ecx        ; ebx == source + size
    cmp eax, ebx        ; destination >= source + size?
    jc @@overlapped

@@nooverlapp:
    cmp byte ptr [ebp].Client_Reg_Struc.Client_EAX,0
    jne @@xchg
    call _MoveMemory
@@ok:
    mov ah,EMSS_OK  ; zero ah, no error return

; exit with code in AH

@@exit:
if ?EMSDBG
    @DbgOutS <"=">,1
    @DbgOutB ah,1
    @DbgOutS <10>,1
endif
    mov edx,[ebp].Client_Reg_Struc.Client_EDX
    mov ebx,[ebp].Client_Reg_Struc.Client_EBX
    ret

@@overlapped:
    mov ah,EMSS_REGIONS_OVERLAPP    ;for xchg, overlapp is invalid
    cmp byte ptr [ebp].Client_Reg_Struc.Client_EAX,0
    jne @@exit
    std
    lea esi,[esi+ecx-1]
    lea edi,[edi+ecx-1]
    mov eax,ecx
    and ecx,3
    REP MOVSB
    MOV ECX,EAX
    sub esi,3
    sub edi,3
    call _MoveMemory
    cld
    mov ah,EMSS_OVERLAP_OCCURED ;status "overlapp occured"
    jmp @@exit

;--- xchange memory regions
;--- esi=src, edi=dst, ecx=size

@@xchg:
    mov ebx, [ebp].Client_Reg_Struc.Client_EFlags
    test bh,2
    jz @@noenable
    call EnableInts
    sti
@@noenable:
    mov edx, ecx
    shr ecx,2
    jz @@xchgb
@@xdw:
    mov eax,[edi]
    movsd
    mov [esi-4],eax
    dec ecx
    jnz @@xdw
@@xchgb:
    mov ecx,edx
    and ecx,3
    je @@xchgdone
@@xb:
    mov al,[edi]
    movsb
    mov [esi-1],al
    dec ecx
    jnz @@xb
@@xchgdone:
    test bh,2
    jz @@ok
    cli
    call DisableInts
    jmp @@ok

    align 4

_MoveMemory:
    mov ebx,[PageMapHeap]
    mov eax,[pPTE]
    mov [PageMapHeap],eax
    call MoveMemory
    mov [PageMapHeap], ebx
    retn
    align 4

RegionSrc   equ <>
pPTE        equ <>
regSize     equ <>
linAddr     equ <>

ems4_move_memory ENDP

; 6758:
; AH = 58h: EMS 4.0 get addresses of mappable pages, number of mappable pages
; AL = 0: ES:DI -> buffer, returns no of pages in CX
; buffer item:
;  WORD segment
;  WORD physical page
; AL = 1: returns no of pages in CX
; the items in the buffer must be sorted in ascending segment order!

ems4_get_mappable_info PROC
    cmp al,1
    ja bad_subfunc ; only 0 and 1 allowed

    movzx ecx, [bEmsPhysPages]
    mov WORD PTR [ebp].Client_Reg_Struc.Client_ECX,cx   ; mappable pages in CX

    cmp al,1
    je @@nummap
    jecxz @@nummap
    
    movzx esi,WORD PTR [ebp].Client_Reg_Struc.Client_ES
    shl esi,4
    movzx edi,di
    add edi,esi     ; edi -> buffer address
    mov ah,0
@@mapinfo_loop:
    call @@getpage  ; get phys page in AL
    movzx edx,al
    mov ah,0
    shl eax,16
    mov ah,byte ptr [edx+EMSPage2Segm]
    mov al,0
    stosd
    loop @@mapinfo_loop
@@nummap:
    mov ah,EMSS_OK
    ret

;--- get the next segment address to AH    

@@getpage:
    push ecx
    mov esi, offset EMSPage2Segm
    mov dl,-1
    mov cl,[bEmsPhysPages]
@@nextitem:
    lodsb
    sub al,ah
    jbe @@skipitem
    cmp al,dl
    ja @@skipitem
    mov dl,al
    mov dh,cl
@@skipitem:
    loop @@nextitem
    mov al,[bEmsPhysPages]
    sub al,dh
    pop ecx
    ret
ems4_get_mappable_info ENDP

; 6759:
; AH = 59h: EMS 4.0 get hardware config/get number of raw pages
; AL = 1: return raw pages in DX and BX
; AL = 0: get hardware config in ES:DI

ems4_get_config PROC
    cmp al,1    ; only subfunctions 0+1 supported
    ja bad_subfunc
    je EMS_GET_UNALLOCATED_PAGE_COUNT

    movzx esi, WORD PTR [ebp].Client_Reg_Struc.Client_ES
    shl esi, 4
    movzx edi, di
    add edi, esi
    mov esi,offset emm59_
    mov ecx,size emm59_ shr 1
    rep movsw
    mov ah,EMSS_OK
    ret

ems4_get_config ENDP

; 675A:
; AH = 5ah: EMS 4.0 allocate handle and standard/raw pages
; in  AL = 0/1
; in  BX = pages to allocate (may be 0)
; out DX = handle
;
ems4_allocate_pages PROC

    cmp al,1    ; subfunction must be 0 or 1, we don't care if either
    ja bad_subfunc
    jmp allocate_pages_plus_zero

ems4_allocate_pages ENDP

; 675B: alternate map register sets
; AL=0/1/2/3/4/5/6/7/8

ems4_alt_map_reg_set PROC

if ?SUPP5B
    mov ah,EMSS_ALT_MAPS_UNSUPP ;alternate map register sets not supported
    cmp al,1
    jb @@is00
    jz @@is01
    cmp al,3
    jb @@is02
    jz @@is03
    cmp al,5
    jb @@is04
    jz @@is05
    cmp al,7
    jb @@is06
    jz @@is07
    cmp al,8
    jz @@is08
    jmp bad_subfunc
@@is00:
    mov bl,0
    mov eax,[mapptr]
    and eax, eax
    jz  @@noptr
    push eax
    movzx edi,ax
    shr eax,16
    shl eax,4
    add edi, eax
    mov al,0
    call save_page_map_int
    pop eax
@@noptr:    
    mov word ptr [ebp].Client_Reg_Struc.Client_EDI,ax
    shr eax,16
    mov word ptr [ebp].Client_Reg_Struc.Client_ES,ax
    jmp @@done
@@is01:
    cmp bl,0
    jnz @@exit
    mov ax,word ptr [ebp].Client_Reg_Struc.Client_ES
    shl eax,16
    mov ax,word ptr [ebp].Client_Reg_Struc.Client_EDI
    mov [mapptr],eax
    and eax, eax
    jz  @@done
    movzx esi,ax
    shr eax,16
    shl eax,4
    add esi, eax
    call restore_page_map_int
    jmp @@done
@@is02:
    mov dx,emm59_.e59_sizcont
    jmp @@done
@@is03:
@@is05:
    mov bl,0
    jmp @@done
@@is04:
@@is06:
@@is07:
@@is08:
    cmp bl,0
    jnz @@exit
@@done:
    mov ah,EMSS_OK
@@exit:
else
    mov ah,EMSS_ACCESS_DENIED   ;access denied by OS
endif
    ret

ems4_alt_map_reg_set ENDP

endif   ;?LIM32

; dynamically compute free EMS pages
; return free pages in EAX
; other registers preserved

GetFreeEMSPages PROC

    push edx
    call Pool_GetFree16KPages   ; free 16k pages in pool in EAX

    mov edx, [EMSPagesMax]
    sub edx, [EMSPagesUsed]     ; edx == free EMS pages numbers
    jbe @@nofree
    cmp edx, eax                ; if there is not enough free pages
    jnc @@eaxok                 ; to backup free EMS pages, then
    mov eax, edx                ; use the lower value
@@eaxok:

@@ret:
if ?POOLDBG
    @DbgOutS <"GetFreeEMSPages: eax=">,1
    @DbgOutD eax,1
    @DbgOutS <10>,1
endif
    pop edx
    ret

@@nofree:
    xor eax,eax
    jmp @@ret
    align 4

GetFreeEMSPages ENDP

; allocate an EMS page
; upon entry edi -> EMSPD for new page to allocate
; return carry if fail
; destroys EAX

AllocateEMSPage PROC

    push edi
    push edx

    call Pool_Allocate16KPage   ;return index in AX, subindex in DL
    jc @@exit

;  set EMSPD.wIndex  == descriptor index
;  set EMSPD.bSubIdx == descriptor subindex 

    mov [edi].EMSPD.wIndex,ax
    sub edi, [EMSPageAllocationStart]
    shr edi, 2

    @DbgOutS <"AllocateEMSPage ok, page=">,?POOLDBG
    @DbgOutW di,?POOLDBG
    @DbgOutS <10>,?POOLDBG

    add edi, [EMSPageAllocationEnd]
    mov [edi].EMSPD2.bSubIdx,dl
    inc [EMSPagesUsed]
    clc
@@exit:
    pop edx
    pop edi
    ret

AllocateEMSPage ENDP

;--- allocate ECX new pages for a handle
;--- inp: ESI=EMSPD
;--- modifies ECX, EDI, EAX, ESI

AllocateEMSPages proc

    push ebx
    mov ebx,ecx
    MOV EDI,[EMSPageAllocationStart]    ; mark the pages as used
    MOV ECX,[EMSPagesMax]
@@SEARCH_PAGES:
    or eax,-1
    REPNZ SCASD
    jnz @@nofind            ; out of free pages?
    sub edi,4
    call AllocateEMSPage     ; allocate the page
    jc @@nofind
    mov eax,edi
    sub eax,[EMSPageAllocationStart]
    shr eax,2
    mov [esi].EMSPD.wNext, ax
    mov esi, edi
    add edi,4
if ?YIELDOPEN
    call Yield
endif
    dec ebx
    JNZ @@SEARCH_PAGES
    pop ebx
    ret
@@nofind:
    pop ebx
    stc
    ret
AllocateEMSPages endp


; release EMS page in AX
; destroy no registers

ReleaseEMSPage  PROC
    push eax
    push ecx
    push edx
    mov edx, [EMSPageAllocationStart]
    mov ecx, [EMSPageAllocationEnd]
    movzx eax,ax
    lea edx, [edx+eax*4]
    cmp edx, ecx
    jae @@ret                           ; out of range
    movzx ecx,[ecx+eax].EMSPD2.bSubIdx  ; get sub index
    movzx eax,[edx].EMSPD.wIndex        ; pool descriptor index
    cmp ax,-1
    je  @@ret

    call Pool_Free16KPage
    jc @@ret
    mov [edx].EMSPD.wIndex,-1

    @DbgOutS <"ReleaseEMSPage ok, EMSPD=">,?POOLDBG
    @DbgOutD edx,?POOLDBG
    @DbgOutS <10>,?POOLDBG

    dec [EMSPagesUsed]
@@ret:
    pop edx
    pop ecx
    pop eax
    ret
ReleaseEMSPage  ENDP

.text$03 ends

.text$04 segment

;--- init EMS handle status table (255 handles * 8)
;--- inp: EDI -> free memory

SetEMSHandleTable proc public

    mov ecx, EMS_MAX_HANDLES * size EMSHD
    call HeapMalloc
    MOV [EMSHandleTable],EDI; set start of EMS handle table.
    MOV EAX,0FF01FFFFh      ; Handle 0 is reserved.
    STOSD
    mov eax,0FF00FFFFh
    MOV ECX, EMS_MAX_HANDLES-1  ; fill the rest
    REP STOSD
    ret
SetEMSHandleTable endp

SetEMSStateTable proc public
    mov ecx, EMS_MAXSTATE * size EMSSTAT
    call HeapMalloc
    mov [EMSStateTable],EDI
    mov eax, -1
    mov ecx, EMS_MAXSTATE*4
    rep stosd
    ret
SetEMSStateTable endp

SetEMSNameTable proc
    mov ecx,8*EMS_MAX_HANDLES
    call HeapMalloc
    mov [EMSNameTable],EDI
    mov eax,'TSYS'      ; store "SYSTEM" as first handle name
    stosd
    mov eax,'ME'
    stosd
    mov ecx,8*(EMS_MAX_HANDLES-1)/4
    xor eax,eax
    rep stosd
    ret
SetEMSNameTable endp

;--- init EMS variables
;--- ESI -> JEMMINIT

EMS_Init1 proc public
    movzx eax, [esi].JEMMINIT.MaxEMSPages
    mov dl, [esi].JEMMINIT.NoFrame
    mov [EMSPagesMax],eax
    mov al, [esi].JEMMINIT.NoEMS
    mov [bNoEMS],al
    cmp al,0
    jz @@emsactive
    mov dl,1
    mov eax,[dwRes]
    mov byte ptr [eax + DEVICE_NAME + 3],'Q' ;EMMXXXX0 -> EMMQXXX0
@@emsactive:
    mov [bNoFrame], dl
    cmp dl, 0
    jnz @@noframe
    mov [bEmsPhysPages], 4
    movzx eax, byte ptr [esi].JEMMINIT.Frame+1
    mov edx, eax
    mov dh,dl
    add dh,4
    mov word ptr [EMSPage2Segm+0], dx
    add dx,0808h
    mov word ptr [EMSPage2Segm+2], dx

if 0    ;not needed. Once the pages are remapped, the bits are cleared
;--- reset the "global page" attribute for the EMS frame PTEs

    @GETPTEPTR eax, eax*4+?PAGETAB0
    mov ecx,16
@@nextitem:
    and byte ptr [eax+1],not 1
    add eax,4
    loop @@nextitem
endif

@@noframe:

;--- calc mappable EMS pages
;--- if a frame is set, physical pages 0-3 have been reserved already.
;--- segments A000-FFFF will get the next page numbers if NORAM is set.

ife ?LIM32
    mov ebx,[esi].JEMMINIT.PageMap

if ?INITDBG
    xor ecx,ecx
    @DbgOutS <"SysMem table:",10>,1
@@nextitemx:
    @DbgOutC [ebx+ecx],1
    inc ecx
    test cl,0Fh
    jnz @@nextitemx
    test cl,30h
    jz @F
    @DbgOutC '-',1
    jmp @@nextitemx
@@:
    @DbgOutS <10>,1
    and cl,cl
    jnz @@nextitemx
endif

;--- if NORAM, include 'IIII', then 'RRRR'
;--- if RAM,   include 'RRRR' only

    push edi
    mov edi,'IIII'
    cmp [esi].JEMMINIT.NoRAM,1
    jz noram_isset
@@nextround:
    mov edi,'RRRR'
noram_isset:
    mov dh,0            ;DH=num mappable pages below A000
    movzx ecx,byte ptr [esi].JEMMINIT.Border+1
@@nextitem2:
    cmp edi,[ebx+ecx]
    jnz @@skipitem
    movzx eax,[bEmsPhysPages]
    cmp al,?MAXPHYSPG
    jnc @@skipitem
    mov [EMSPage2Segm+eax],cl
    inc eax
    inc dh
    mov [bEmsPhysPages],al
if 0        ;is not needed, since once the page is remapped, the bit is reset    
    @GETPTEPTR eax,?PAGETAB0+ecx*4
    and byte ptr [eax+00+1],not 1   ;reset "global" attribute
    and byte ptr [eax+04+1],not 1   ;reset "global" attribute
    and byte ptr [eax+08+1],not 1   ;reset "global" attribute
    and byte ptr [eax+12+1],not 1   ;reset "global" attribute
endif
@@skipitem:
    add ecx,4
    cmp ch,0
    jz @@nextitem2
    cmp edi,'RRRR'
    jnz @@nextround
    pop edi
    mov [bPagesConv],dh
    movzx edx,dh
    add word ptr [EMSPagesMax],dx
    jns @@nopagelim
    mov word ptr [EMSPagesMax],MAX_EMS_PAGES_POSSIBLE
@@nopagelim:
    shl edx,2
    add [dwMaxMem4K],edx
endif   ;?LIM32

    movzx eax,[bEmsPhysPages]
    inc eax     ;+ 1 dword for checksum
    shl eax,2
    mov emm59_.e59_sizcont, ax

if ?VCPI
    mov al, [esi].JEMMINIT.NoVCPI
    mov [bNoVCPI],al
endif
    ret
EMS_Init1 endp

;--- alloc the EMS management tables
;--- ESI -> JEMMINIT
;--- EDI -> free space

EMS_Init2 proc public

;--- set the EMS tables    

; alloc EMS handle/status/name table (4/8/8 bytes)

    call SetEMSHandleTable
    call SetEMSStateTable
    call SetEMSNameTable

if ?INITDBG
    @DbgOutS <"EMS handle table=">,1
    @DbgOutD EMSHandleTable,1
    @DbgOutS <", state table=">,1
    @DbgOutD EMSStateTable,1
    @DbgOutS <", name table=">,1
    @DbgOutD EMSNameTable,1
    @DbgOutS <10>,1
    @WaitKey 1,0
endif

;--- allocate and init EMS page descriptor array (EMSPD)
;--- size of EMSPD is 4 bytes, it
;--- consists of 2 words, first is a pointer to the next EMS page
;--- second is the pool descriptor index of this EMS page

    mov ecx,[EMSPagesMax]
    mov [EMSPageAllocationStart],edi

if ?INITDBG
    @DbgOutS <"EMS pages=">,1
    @DbgOutD ecx,1
    @DbgOutS <" at ">,1
    @DbgOutD edi,1
    @DbgOutS <10>,1
endif

    push ecx
    or eax,-1
    rep stosd
    pop ecx
    mov [EMSPageAllocationEnd],edi

if ?INITDBG
    @DbgOutS <"EMS page alloc start/end=">,1
    @DbgOutD [EMSPageAllocationStart],1
    @DbgOutS <"/">,1
    @DbgOutD [EMSPageAllocationEnd],1
    @DbgOutS <10>,1
endif

;--- behind the EMS EMSPD array comes an array of bytes
;--- which are the "nibble" offsets of the descriptor's bit array

    inc eax
    rep stosb

if ?INITDBG
    @DbgOutS <"EMS array of subindices end=">,1
    @DbgOutD edi,1
    @DbgOutS <10>,1
endif

;--- init EMS SYSTEM handle

ife ?LIM32
    movzx ecx,[bPagesConv]    ;any mappable conv. memory pages?
    jecxz @@nomap2

    pushad

    push ecx
    shl ecx, 4                  ;16k -> 1k pages
    movzx edi,[esi].JEMMINIT.Border
    shr edi,6                   ;paragraphs -> 1K
    mov al, PBF_DONTFREE or PBF_DONTEXPAND
    call Pool_AllocBlocksForEMB
    pop ebx

    MOV EDI,[EMSPageAllocationStart]
    mov esi,[EMSHandleTable]
    xor ecx,ecx
@@nextpage:
    call AllocateEMSPage
    mov [esi].EMSPD.wNext, cx
    mov esi,edi
    add edi,4
    inc ecx
    cmp ecx,ebx
    jnz @@nextpage
    popad
@@nomap2:
endif

    @DbgOutS <"EMSInit2 done",10>,?INITDBG
    ret
EMS_Init2 endp

;--- for NoPool: check if EMSPagesMax has to be adjusted
;--- in: eax = 4k pages still free in fixed XMS memory block

EMS_CheckMax proc public
    shr eax, 2
    mov edx, [EMSPagesMax]
    sub edx, [EMSPagesUsed]
    cmp eax, edx
    jnc @@isnodecrease
    sub edx, eax
    sub [EMSPagesMax],edx
@@isnodecrease:
    ret
EMS_CheckMax endp

.text$04 ends

    END
