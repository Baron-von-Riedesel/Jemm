
;--- this is the Jemm EMS 3.2 implementation (functions 40h - 4Eh)
;--- since this part is copyright Harald Albrecht/Tom Ehlert,
;--- it has been extracted into a separate file.
;--- It's included by EMS.ASM

;--- API: EBP -> client registers
;--- out: BX, DX and AH will be copied to client registers
;--- change of other registers have to be done directly

;
; AH = 40h: return the actual state of the EMM-driver.
;
EMS_GET_STATUS PROC
    MOV     AH,EMSS_OK
    RET
EMS_GET_STATUS ENDP
;
; AH = 41h: request the segment address of the EMS-window
;
EMS_GET_PAGE_FRAME_ADDRESS PROC
    mov     ah,80h
    cmp     [bNoFrame],0
    jnz     @@BYE
    MOV     AH,EMSS_OK          ; No error occurred
    MOV     BH,[EMSPage2Segm+0] ; Segment address of EMS-Window/Frame
    MOV     BL,0
@@BYE:
    RET
EMS_GET_PAGE_FRAME_ADDRESS ENDP

;
; AH = 42h: Request number of free + total EMS-pages
; out: BX=free pages
; out: DX=total pages

EMS_GET_UNALLOCATED_PAGE_COUNT PROC

    call    GetFreeEMSPages
    MOV     EBX,EAX
    MOV     EDX,[EMSPagesMax]       ; total EMS pages

; follow MS-DOS EMM386 7.x lead and don't throttle pages on NOEMS
;   cmp cs:[bNoEMS],0
;   je  @@unalloc_ret
;   or  bx,bx
;   je  @@unalloc_ret
;   mov bx,1            ; only show maximum of 1 EMS page if NOEMS set
;@@unalloc_ret:

    MOV     AH,EMSS_OK
    RET
EMS_GET_UNALLOCATED_PAGE_COUNT ENDP

;
; AH = 43h: Reserve pages for new EMS handle
; in  BX = EMS pages to reserve
; out AH=00, DX = handle

EMS_ALLOCATE_PAGES PROC
    MOV     AH,EMSS_ZERO_PAGES  ; "Request to reserve null pages"
    AND     BX,BX
    JZ      SHORT @@BYE

allocate_pages_plus_zero::  ;this entry allows to alloc zero pages!

    MOV     AH,EMSS_OUT_OF_PAGES    ; "Not enough pages available"
    movzx   ebx,bx
    CMP     EBX,[EMSPagesMax]
    JA      SHORT @@BYE

    call    GetFreeEMSPages
    CMP     EBX, EAX
    MOV     AH,EMSS_OUT_OF_FREE_PAGES   ; "Not enough free pages available"
    JA      SHORT @@BYE

    MOV     ESI,[EMSHandleTable]    ; Now search for a free Handle in the table
    MOV     CL,EMS_MAX_HANDLES
@@SEARCH:
    test    [ESI].EMSHD.ehd_bFlags,EMSH_USED; Is there one free ... ?
    JZ      SHORT @@FOUND
    ADD     ESI,size EMSHD
    dec     cl
    jnz     @@SEARCH
    MOV     AH,EMSS_NO_MORE_HANDLES ; "No more free Handles"
@@BYE:
    RET

@@FOUND:
    or      [ESI].EMSHD.ehd_bFlags,EMSH_USED

    MOV     DX,EMS_MAX_HANDLES      ; Set in DX now the actual Handle-
    SUB     DL,CL                   ; number

    or      ebx,ebx                 ; zero page allocation?
    je      @@allocate_exit         ; then we're done
    mov     ecx, ebx
    call    AllocateEMSPages
    jc      @@nofind
@@allocate_exit:
    MOV     AH,EMSS_OK
    RET
@@nofind:
if ?POOLDBG
    @DbgOutS <"EMS_ALLOCATE_PAGES: @@nofind reached, BX=">,1
    @DbgOutW bx,1
    @DbgOutS <10>,1
endif
    call EMS_DEALLOCATE_PAGES       ;free the handle in DX  
    MOV AH,EMSS_OUT_OF_FREE_PAGES   ; "Not enough pages available anymore"
    ret
    align 4

EMS_ALLOCATE_PAGES ENDP

; AH = 44h: map logical page DX:BX into physical page AL (the EMS-window)
; AL = physical page (0-3)
; DX = handle
; BX = logical page # (or FFFF to unmap the page)
;
EMS_MAP_HANDLE_PAGE PROC

    CALL    EMS_TEST_HANDLE

    CMP     AL,[bEmsPhysPages]      ; not" Only pages 0..3
    JAE     SHORT @@PAGE_TOO_LARGE  ; are allowed!

    PUSH    EBX                     ; save BX  (since it is changed)
    call    EMS_MAP_REL_PAGE        ; map/unmap the page in DX:BX to AL
    jc      @@done
    call    FlushTLB
    MOV     AH,EMSS_OK
@@done:
    POP     EBX
    RET
@@PAGE_TOO_LARGE:
@@ERR8B:
    MOV     AH,EMSS_PHYS_PAGE_INVALID   ; "physical page does not exist"
    RET

EMS_MAP_HANDLE_PAGE ENDP

; AH = 45h: Release reserved memoryspace again
; DX = handle to release
; any pages of this handle mapped in page frame remain mapped!
; this is same behaviour as MS Emm386

EMS_DEALLOCATE_PAGES PROC
    CALL    EMS_TEST_HANDLE
    and     dx,dx
    jz      ems_release_null
    MOV     AH,EMSS_CONTEXT_EXISTS  ; "A saved state still
    CMP     [ESI].EMSHD.ehd_bSS,-1      ; exists" ?
    JNZ     SHORT @@BYE

    and     [esi].EMSHD.ehd_bFlags,not EMSH_USED
    MOV     EDI,[EMSPageAllocationStart]
    xor     eax, eax
    jmp     @@test
@@LOOP:
    lea     esi,[edi+eax*4]
    call    ReleaseEMSPage          ; preserves registers
@@test:
    mov     ax,-1
    xchg    ax,[esi].EMSPD.wNext
    cmp     ax,-1
    jnz     @@LOOP

; zero handle name on free
    mov edi, [EMSNameTable]
    xor esi, esi
    movzx   ecx, dx
    mov DWORD PTR [edi+ecx*8+0],esi
    mov DWORD PTR [edi+ecx*8+4],esi

    MOV     AH,EMSS_OK
@@BYE:
    RET
ems_release_null:
ife ?LIM32
    push ebx
    xor ebx,ebx
    call ems4_realloc
    pop ebx
else
    mov ah,EMSS_OK
endif
    ret
EMS_DEALLOCATE_PAGES ENDP

;
; AH = 46h: determine Version-number of EMM
;

EMS_GET_VERSION PROC
if ?LIM32
    mov     byte ptr [ebp].Client_Reg_Struc.Client_EAX, 32h
else
    mov     byte ptr [ebp].Client_Reg_Struc.Client_EAX, 40h
endif
    MOV     AH,EMSS_OK
    RET
EMS_GET_VERSION ENDP

;--- save the frame window mapping state

EMS_SaveFrameToEdi proc
    mov     cl,4
EMS_SaveFrameToEdi endp ;fall through

;--- save CL (0 - bEmsPhysPages) pages to ESI
;--- EDI -> array of DWORDs, where PTEs will be stored
;--- modifies CL

EMS_SavePagesToEdi PROC
    PUSH    EAX
    PUSH    EDX
    PUSH    ESI
    INC     CL
    xor     edx,edx
    mov     esi,offset EMSPage2Segm
    jmp     @@test
@@NEXTPAGE:
    lodsb
    movzx   eax,al
    @GETPTEPTR eax, EAX*4+?PAGETAB0
    MOV     EAX, [EAX]
    mov     al,dl
    inc     edx
    STOSD
@@test:
    DEC     CL
    jnz     @@NEXTPAGE
    POP     ESI
    POP     EDX
    POP     EAX
    RET
EMS_SavePagesToEdi ENDP

;--- restore the frame window mapping state

EMS_RestoreFrameFromEsi PROC
    mov     cl, 4
EMS_RestoreFrameFromEsi ENDP        ;fall through

;-- restore CL (0 - bEmsPhysPages) pages
;-- esi -> array of DWORDs, containing PTEs

EMS_RestorePagesFromEsi PROC

    push    edi
    INC     CL
    jmp     @@test
@@NEXTPAGE:
    lodsd
    movzx   edi,al
    movzx   edi,[EMSPage2Segm+EDI]
    @GETPTEPTR EDI,EDI*4+?PAGETAB0
    MOV     al,7
    stosd
    add     eax,1000h
    stosd
    add     eax,1000h
    stosd
    add     eax,1000h
    stosd
@@test:
    DEC     CL
    jnz     @@NEXTPAGE
    pop     edi
    call    FlushTLB
    MOV     AH,EMSS_OK      ; report OK (because of functions $4E01/$4E02)
    RET

EMS_RestorePagesFromEsi ENDP

; AH = 47h: Save status of EMS page frame to internally
;           maintained buffers (max 1 for each handle)
; in: DX = handle
; it might be that there are pages mapped into the EMS page frame
; which don't belong to any handles (anymore)!
;
EMS_SAVE_PAGES PROC
    mov     ah,EMSS_SOFTWARE_ERR
    cmp     [bNoFrame],0
    jnz     @@BYE
    CALL    EMS_TEST_HANDLE
    MOV     AH,EMSS_STATE_ALREADY_SAVED   ; "State for Handle already saved"
    CMP     [ESI].EMSHD.ehd_bSS,-1
    JNZ     @@BYE
    mov     edi,[EMSStateTable]
    xor     eax,eax
@@nextitem:
    cmp     [edi].EMSSTAT.dPg0,-1
    jz      @@found
    add     edi,size EMSSTAT
    inc     eax
    cmp     eax,EMS_MAXSTATE
    jnz     @@nextitem
    mov     ah,EMSS_CONTEXT_STACK_FULL
    ret
@@found:
    mov     [esi].EMSHD.ehd_bSS,al
    call    EMS_SaveFrameToEdi
    MOV     AH,EMSS_OK
@@BYE:
    RET
EMS_SAVE_PAGES ENDP

; AH = 48h: Restore saved state of the EMS-window
; DX = handle

EMS_RESTORE_PAGES PROC
    mov     ah,EMSS_SOFTWARE_ERR
    cmp     [bNoFrame],0
    jnz     @@BYE
    CALL    EMS_TEST_HANDLE
    MOV     AH,EMSS_NO_STATE_IS_SAVED ; "A saved state does not exist"
    CMP     [ESI].EMSHD.ehd_bSS,-1
    JZ      SHORT @@BYE
    mov     al,-1
    xchg    al,[ESI].EMSHD.ehd_bSS
    movzx   eax,al
    shl     eax,4           ;size of EMSSTAT
    mov     esi,[EMSStateTable]
    add     esi, eax
    push    esi
    CALL    EMS_RestoreFrameFromEsi
    pop     esi
    mov     [esi].EMSSTAT.dPg0,-1
    MOV     AH,EMSS_OK
@@BYE:
    RET

EMS_RESTORE_PAGES ENDP

; report the failure so that we can maybe support it in the future

EMS_NOT_IMPL PROC

IF  ?UNIMPL_EMS_DBG
    mov     edi,offset unimpl_ax
    call    w2a
    push    offset unimpl_func
    call    PrintString
ENDIF
    MOV     AH,EMSS_INVALID_FUNCTION      ; "Invalid function code"
    RET

if ?UNIMPL_EMS_DBG    
unimpl_func db "Unimplemented EMS function called, ax="
unimpl_ax   db "____"
            db 13,10
            db 0
endif

EMS_NOT_IMPL ENDP

; AH = 4Bh: return Number of open Handles in BX

EMS_GET_OPEN_HANDLES_COUNT PROC
    MOV     ESI,[EMSHandleTable] ; Search Handle-status-table for
    MOV     ECX,EMS_MAX_HANDLES      ; assigned/given handles
    XOR     EBX,EBX
    XOR     EAX,EAX
@@LOOP:
    test    [ESI].EMSHD.ehd_bFlags,EMSH_USED; Free ?
    setnz   al
    ADD     ESI,size EMSHD              ; Next entry
    add     ebx,eax
    loop    @@LOOP
    MOV     AH,EMSS_OK
    RET
EMS_GET_OPEN_HANDLES_COUNT ENDP
;
; AH = 4Ch: return number of reserved pages for a handle
; inp: handle in DX.
; out: pages in BX.
; modifies ESI, EDI, EBX, EAX

EMS_GET_PAGES_ONE_HANDLE PROC
    CALL    EMS_TEST_HANDLE
    movzx   EAX,[esi].EMSHD.ehd_wIdx
    MOV     EDI,[EMSPageAllocationStart]
    XOR     EBX,EBX
    jmp     @@test
@@LOOP:
    mov     ax,[edi+eax*4].EMSPD.wNext
    INC     EBX
@@test:
    cmp     ax,-1
    jnz     @@LOOP
    MOV     AH,EMSS_OK
    RET
EMS_GET_PAGES_ONE_HANDLE ENDP
;
; AH = 4Dh: determine Number of reserved pages for all Handles
; ES:DI -> array of 2 WORD entries (handle, pages)
; out: AH=00 success, BX=number of handles stored in array
;
EMS_GET_PAGES_ALL_HANDLES PROC
    MOVZX   ESI,WORD PTR [ebp].Client_Reg_Struc.Client_ES
    SHL     ESI,4
    MOVZX   EDI,DI
    ADD     ESI,EDI                      ; ESI -> array
    PUSH    EDX
    MOV     EDI,[EMSHandleTable]
    XOR     EAX,EAX                      ; current Handle-Number
    XOR     EBX,EBX                      ; count open handles
@@NEXT_HANDLE:
    test    [EDI].EMSHD.ehd_bFlags,EMSH_USED ; handle free?
    JZ      SHORT @@NEXT
    INC     EBX                          ; One more Handle is open...
    MOV     [ESI+0],AX                   ; Place handle
    PUSH    EDI
    movzx   ecx,[edi].EMSHD.ehd_wIdx
    MOV     EDI,[EMSPageAllocationStart] ; get pages for handle
    XOR     EDX,EDX                      ; EDX is counter
    jmp     @@test
@@LOOP:
    inc     edx
    mov     cx,[edi+ecx*4].EMSPD.wNext
@@test:
    cmp     cx,-1
    jnz     @@LOOP
    MOV     [ESI+2],DX                   ; Set number of handle's pages
    add     ESI, 4
    POP     EDI
@@NEXT:
    ADD     EDI,size EMSHD
    INC     EAX
    CMP     AL,EMS_MAX_HANDLES               ; All Handles processed ?
    JB      @@NEXT_HANDLE
    POP     EDX
    MOV     AH,EMSS_OK
    RET
EMS_GET_PAGES_ALL_HANDLES ENDP

; AH = 4Eh: Get & Set Page Map
; AL = 0,1,2,3
; AL = 0: ES:DI -> array to get info
; AL = 1: DS:SI -> array to set info
; AL = 2: DS:SI -> array to set info, ES:DI -> array to get info
; AL = 3: AL returns size of array (bytes)

@CHKSUM MACRO   REG
    MOV     EAX,[REG+04]        ; Calculate checksum
    ADD     EAX,[REG+08]
    ADD     EAX,[REG+12]
    ADD     EAX,[REG+16]
ENDM

EMS_GET_SET_PAGE_MAP PROC
    CMP     AL,3                    ; Subfunction 0 to 3 ?
    JA      bad_subfunc
    JZ      SHORT @@SUBF_3          ; Size of field
    CMP     AL,1
    JZ      SHORT @@SUBF_1          ; Set Page Map

; AL = 2: Get & Set Page Map
; AL = 0: Get Page Map - save Hardwarestatus

@@SUBF_0:
    MOVZX   ECX, WORD PTR [ebp].Client_Reg_Struc.Client_ES; ES:DI ^ convert from statusfield in
    SHL     ECX, 4                  ; usual REAL-Mode-Format
    MOVZX   EDI, DI
    ADD     EDI, ECX
save_page_map_int::                 ; <--- internal, EDI=save area, AL=0 ( ax=5B00h )
    PUSH    EAX                     ; save Subfunctioncode
    PUSH    edi
    add     edi,4
    mov     cl, [bEmsPhysPages]
    CALL    EMS_SavePagesToEdi
    pop     edi
    @CHKSUM EDI                     ; Calculate checksum and ...
    stosd
    POP     EAX                     ; restore and examen subfunctioncode
    CMP     AL,2                    ; if subfuction 2 is wanted,
    JZ      SHORT @@SUBF_1          ; then also set new map
    MOV     AH,EMSS_OK
    RET

; Subf. 1: Set Page Map - restore Hardwarestatus

@@SUBF_1:
    MOVZX   ECX,WORD PTR [ebp].Client_Reg_Struc.Client_DS   ; DS:SI ^ convert from statusfield in
    SHL     ECX,4                   ; usual REAL-Mode-Format
    MOVZX   ESI,SI
    ADD     ESI,ECX
restore_page_map_int::              ; <--- internal: ESI=save area ( ax=5B01h )
    @CHKSUM ESI                     ; Calculate checksum and check it
    CMP     [ESI],EAX
    JNZ     @@CHKERR
    lodsd                           ; skip checksum
    mov     cl, [bEmsPhysPages]
    JMP     EMS_RestorePagesFromEsi

; Checksum is incorrect !
@@CHKERR:
;    MOV     AH,0A3H                 ; data is destroyed !
    MOV     AH, EMSS_SRC_ARRAY_INVALID
    RET

; Subf. 3: return size of the field in AL

@@SUBF_3:
    MOV     AL, byte ptr emm59_.e59_sizcont
    MOV     byte ptr [ebp].Client_Reg_Struc.Client_EAX, al
    MOV     AH,EMSS_OK
    RET

EMS_GET_SET_PAGE_MAP ENDP

bad_subfunc:
    MOV     AH,EMSS_INVALID_SUBFUNC ; Invalid subfunctioncode !
    RET
    align 4
    
; Check a given Handle (in DX) for validness.
; In case the Handle is invalid the returnaddress is thrown away
; and afterwards through RET returned to dispatcher.
; Else ESI will point to the handle in EMSHandleTable array

EMS_TEST_HANDLE PROC
    CMP     DX,EMS_MAX_HANDLES          ; out of area ?
    JAE     @@INVALID
    MOVZX   ESI,DL                      ; get a pointer to the handle table
    SHL     ESI,2                       ; size is 4
    ADD     ESI, [EMSHandleTable]
    test    [ESI].EMSHD.ehd_bFlags, EMSH_USED
    JZ      @@INVALID
    RET
@@INVALID:
    ADD     ESP,4                       ; throw away call(ing)-address
    MOV     AH,EMSS_INVALID_HANDLE      ; "Handle invalid"
    RET
    align 4
EMS_TEST_HANDLE ENDP

