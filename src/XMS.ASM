
;--- XMS/A20 implementation
;--- Public Domain
;--- to be assembled with JWasm or Masm v6.1+

    .486P
    .model FLAT
    option proc:private
    option dotname

    include jemm.inc        ;common declarations
    include jemm32.inc      ;declarations for Jemm32
    include debug.inc

;--- publics/externals

    include external.inc

?MERGE0HDL equ 1	;std=0, 1=try to merge handles even if hdl to free has size 0
?HINF_MSCOMP equ 1	;std=1, 1=full MS compatibility for AH=0Eh

;   assume SS:FLAT,DS:FLAT,ES:FLAT

.text$01 SEGMENT

;-- Jemm's real-mode part will call XMS A20 local disable
;-- after the monitor's initialization. With wA20==1 this might
;-- disable the (emulated) A20. FreeDOS might have problems with
;-- this if MS Himem is used. wA20==2 seems to avoid these problems.

if ?A20XMS
;wA20           dw 1    ; local XMS A20 count + global A20 flag
wA20            dw 2
endif

if ?INTEGRATED
x2max           dw  -1
hmamin          dw  0
hma_used        db  0
 if ?XMS35
xms_version     dw -1
 endif
endif

if ?A20PORTS or ?A20XMS
bNoA20          DB  0
bA20Stat        DB  1   ; default is A20 enabled
endif

ife ?DYNTRAPP60
if ?A20PORTS
bLast64         DB  0
endif
endif

        align 4

XMS_Handle_Table XMS_HANDLETABLE <0,0,0,0>

ife ?INTEGRATED
XMSCtrlHandle dw 0
else
A20Index db 0
endif

.text$01 ends

.text$03 segment

;--- registers EAX, ECX and ESI dont hold client values!

xms_handler proc public
    call Simulate_Far_Ret                       ; emulate a RETF in v86
    mov eax,[ebp].Client_Reg_Struc.Client_EAX   ; restore EAX
if ?INTEGRATED
    mov esi,[ebp].Client_Reg_Struc.Client_ESI
    mov ecx,[ebp].Client_Reg_Struc.Client_ECX
    @dprintf ?EMBDBG, <"xms_handler: ax=%X edx=%X",10>, ax, edx
    cmp ah,0fh          ; 00-0F?
    jbe @@ok1
    mov al,ah
    shr al,1
    cmp al,88h/2        ; 88-89?
    jz @@ok2
    cmp al,8Eh/2        ; 8E-8F?
    jz @@ok3
 if ?XMS35
    cmp al,0C8h/2       ; C8-C9?
    jz @@ok4
    cmp ah,0CBh         ; CB?
    jz @@ok5
    cmp ah,0CCh         ; CC?
    jz @@ok5
 endif
    cmp ah,12h
    jbe umb_handler
    xor ax,ax           ; everything else fails
    mov bl,XMS_NOT_IMPLEMENTED
    jmp @@dispatcher_end
@@ok5:
	dec ah              ; CB-CC -> CA-CB
@@ok4:
	sub ah,0C8h-14h		; C8-CC -> 14-17
	jmp @@ok1
@@ok3:
    sub ah,4            ; 8E-8F -> 8A-8B
@@ok2:
    sub ah, 88h-10h     ; 88-8B -> 10-13
@@ok1:
    cld
    movzx edi,ah
    call [xms_table+edi*4]
@@dispatcher_end:
    mov [ebp].Client_Reg_Struc.Client_EBX, ebx
    mov [ebp].Client_Reg_Struc.Client_EDX, edx
    mov [ebp].Client_Reg_Struc.Client_ECX, ecx
    mov [ebp].Client_Reg_Struc.Client_EAX, eax
    ret

    align 4

xms_table label dword  
    dd xms_get_version          ;00
    dd xms_request_hma          ;01
    dd xms_release_hma          ;02
    dd xms_global_enable_a20    ;03
    dd xms_global_disable_a20   ;04
    dd xms_local_enable_a20     ;05
    dd xms_local_disable_a20    ;06
    dd xms_query_a20            ;07
    dd xms_query_free_mem       ;08
    dd xms_alloc_emb            ;09
    dd xms_free_emb             ;0A
    dd xms_move_emb             ;0B
    dd xms_lock_emb             ;0C
    dd xms_unlock_emb           ;0D
    dd xms_get_handle_info      ;0E
    dd xms_realloc_emb          ;0F

    dd xms_ext_query_free_mem   ; 88 10
    dd xms_ext_alloc_emb        ; 89 11
    dd xms_ext_get_handle_info  ; 8E 12
    dd xms_ext_realloc_emb      ; 8F 13
 if ?XMS35
    dd xms_sext_query_free_mem  ; C8 14
    dd xms_sext_alloc_emb       ; C9 15
    dd xms_move_emb             ; CB 16
    dd xms_sext_lock_emb        ; CC 17
 endif
else
  if ?A20XMS
    cmp ah,10h
    jae umb_handler
    call XMS_HandleA20
    mov word ptr [ebp].Client_Reg_Struc.Client_EAX, ax
    and ax,ax
    jnz @@a20exit_noerror
    mov byte ptr [ebp].Client_Reg_Struc.Client_EBX, bl
@@a20exit_noerror:
    ret
  else
    jmp umb_handler
  endif
endif

xms_handler endp

if ?INTEGRATED

xms_get_version proc
if ?XMS35
    mov ax,xms_version
else
    mov ax,INTERFACE_VER
endif
    mov bx,DRIVER_VER
    mov dx,1                    ; HMA is always available
    ret
xms_get_version endp

xms_request_hma proc
    xor ax,ax
    cmp [hma_used],al           ; is HMA already used?
    mov bl,XMS_HMA_IN_USE
    jnz @@exit
    cmp dx,[hmamin]             ; is request big enough?
    mov bl,XMS_HMAREQ_TOO_SMALL
    jb @@exit
    inc eax
    mov [hma_used],al           ; assign HMA to caller
    mov bl,0 
@@exit:
    ret
xms_request_hma endp

xms_release_hma proc
    xor ax,ax
    cmp [hma_used],al           ; is HMA used?
    mov bl,XMS_HMA_NOT_USED
    jz @@exit
    mov [hma_used],al           ; now release it
    inc eax
    mov bl,0
@@exit:
    ret
xms_release_hma endp

xms_query_a20 proc
    movzx ax,[bA20Stat]
    mov bl,0
    ret
    align 4
xms_query_a20 endp

;--- check if handle in DX is valid
;--- let ESI point to handle
;--- this function does NOT return if handle is invalid

xms_check_handle_ex:
    mov esi,edx
xms_check_handle proc	;<--- check handle in SI
    push edx
    push eax

    movzx esi,si
    add esi,[dwRes]
    jc @@no_valid_handle
    mov eax,esi
    sub eax,[XMS_Handle_Table.xht_pArray]
    jb @@no_valid_handle
    xor edx,edx

    push ebx
    mov ebx,size XMS_HANDLE
    div ebx
    pop ebx

    or edx,edx
    jnz @@no_valid_handle
    movzx edx,[XMS_Handle_Table.xht_numhandles]

    cmp eax,edx
    jae @@no_valid_handle

    cmp [esi].XMS_HANDLE.xh_flags,XMSF_USED   ; is it in use ??
    jne @@no_valid_handle
    pop eax
    pop edx
    ret
@@no_valid_handle:
    pop eax
    pop edx
    add esp,4   ;skip return address
    xor ax,ax
    mov bl,XMS_INVALID_HANDLE
    stc
    ret
    align 4

xms_check_handle endp

;--- allocate an unused handle in EBX
;--- C if no handle available

xms_alloc_handle proc
    movzx ecx,[XMS_Handle_Table.xht_numhandles]    ; check all handles
    mov ebx,[XMS_Handle_Table.xht_pArray]
@@nextitem:
    cmp [ebx].XMS_HANDLE.xh_flags,XMSF_INPOOL
    jz @@found_handle          ; found a blank handle
    add ebx,size XMS_HANDLE     ; skip to next handle
    loop @@nextitem
    stc                         ; no free block found, error
@@found_handle:
    ret
xms_alloc_handle endp


;--- AH=09H: alloc an EMB, size DX kB

xms_alloc_emb proc
    @dprintf ?EMBDBG, <"xms_alloc_emb",10>
    push edx
    movzx edx,dx  ; extend alloc request to 32-bits
    jmp @@xms_alloc2

;-- 32-bit entry for function AH=89h: alloc EMB, size EDX kB

xms_ext_alloc_emb::
if ?XMS35
xms_sext_alloc_emb::;<--- entry, ah=15h
endif
    push edx
    @dprintf ?EMBDBG, <"xms_ext_alloc_emb",10>

@@xms_alloc2:
    push ecx
if 0	;v5.80 check for size 0 after scan
    and edx,edx              ; a request for 0 kB needs no free mem
    jz @@nullhandle
endif
    movzx ecx,[XMS_Handle_Table.xht_numhandles]
    mov edi,[XMS_Handle_Table.xht_pArray] 
@@nextitem:
    cmp [edi].XMS_HANDLE.xh_flags,XMSF_FREE
    jnz @@skipitem
;--- filter blocks 
if ?XMS35
	cmp ah,15h	;15h is xms_sext_alloc_emb #
	jnz @F
	test word ptr [edi].XMS_HANDLE.xh_baseK+2,0FFC0h
	jnz sext_mem
	jmp @@skipitem
@@:
	test word ptr [edi].XMS_HANDLE.xh_baseK+2,0FFC0h
	jnz @@skipitem
sext_mem:
endif
    cmp edx,[edi].XMS_HANDLE.xh_sizeK   ; check if it's large enough
    jbe @@found_block
@@skipitem:
    add edi,size XMS_HANDLE   ; skip to next handle
    loop @@nextitem
if 1	;v5.80 check for size 0 after scan
    and edx,edx              ; a request for 0 kB needs no free mem
    jz @@nullhandle
endif
    mov bl,XMS_ALL_MEM_ALLOCATED
@@alloc_failed:
    pop ecx
    pop edx
    xor dx,dx    ;v5.80: return DX=0 if alloc fails (XMS spec)
    xor ax,ax
    ret
@@nullhandle:
    push ebx
    call xms_alloc_handle    ; get a free handle in EBX
    mov edi,ebx
    pop ebx
    mov bl,XMS_NO_HANDLE_LEFT
    jc @@alloc_failed
    xor ax,ax                ; set ZF to skip code below

@@found_block:
    mov word ptr [edi].XMS_HANDLE.xh_flags,XMSF_USED ;clear locks also
    jz @@perfect_fit2               ; if it fits perfectly, go on
    push ebx
    call xms_alloc_handle           ; get a free handle in BX
    jc  @@perfect_fit               ; no more handles, use all mem left
    mov esi,[edi].XMS_HANDLE.xh_sizeK
    mov [edi].XMS_HANDLE.xh_sizeK,edx
    sub esi,edx                     ; calculate resting memory
    add edx,[edi].XMS_HANDLE.xh_baseK   ; calc new base address of free block 
    mov word ptr [ebx].XMS_HANDLE.xh_flags,XMSF_FREE
    mov [ebx].XMS_HANDLE.xh_baseK,edx
    mov [ebx].XMS_HANDLE.xh_sizeK,esi
@@perfect_fit:
    pop ebx
@@perfect_fit2:
    pop ecx
    pop edx
    @dprintf ?EMBDBG, <"xms_alloc_emb, handle=%X baseK=%X sizeK=%X [res=%X]",10>, edi, [edi].XMS_HANDLE.xh_baseK, [edi].XMS_HANDLE.xh_sizeK, [dwRes]
    sub edi,[dwRes]
    mov dx,di                       ; return handle in DX
    mov bl,0
    mov ax,1
    @dprintf ?EMBDBG, <"xms_alloc_emb ok, handle=%X",10>, dx
    ret
xms_alloc_emb endp

if ?XMS35
;******************************************************************************
; query free super-extended memory
; In:   AH=C8h
; Out:  EAX=size of largest free super-extended block in kbytes
;   EDX=total amount of free super-extended block in kbytes
;   BL=0 if ok
;   BL=080h -> function not implemented
;   BL=081h -> VDISK is detected
;   BL=0a0h -> all super-extended memory is allocated

xms_sext_query_free_mem proc

	xor eax,eax 	; contains largest free block
	xor edx,edx 	; contains total free block

	push ecx
	push ebx
    movzx ecx,[XMS_Handle_Table.xht_numhandles]
    mov ebx,[XMS_Handle_Table.xht_pArray]
nextitem:
	test [ebx].XMS_HANDLE.xh_flags,XMSF_FREE	; check if flagged free or in use
	je @F

;--- filter blocks below 4 GB
;--- 00000000-003fffffh
	test word ptr [ebx].XMS_HANDLE.xh_baseK+2, 0ffc0h
	jz @F

	mov esi, [ebx].XMS_HANDLE.xh_sizeK
	add edx, esi
	cmp esi, eax			  ; check if larger than largest
	jbe @F
	mov eax,esi 			  ; larger, update
@@:
	add ebx,sizeof XMS_HANDLE
	loop nextitem
	pop ebx
	pop ecx
	mov bl,0
	and edx,edx
	jnz @F
	mov bl,XMS_ALL_MEM_ALLOCATED
@@:
	ret 			; success

xms_sext_query_free_mem endp
endif

;--- AH=88h: get free mem info
;--- out: eax=max free block, edx=total free, ecx=highest phys addr

xms_ext_query_free_mem proc

    @dprintf ?EMBDBG, <"xms_ext_query_free_mem",10>
    xor edi,edi     ; highest ending address of any memory block
    xor eax,eax     ; contains largest free block
    xor edx,edx     ; contains total free XMS

    push ebx
    movzx ecx,[XMS_Handle_Table.xht_numhandles]
    mov ebx,[XMS_Handle_Table.xht_pArray]
@@nextitem:
    test [ebx].XMS_HANDLE.xh_flags,XMSF_USED or XMSF_FREE   ; check if flagged free or in use
    je  @@skipitem

;--- filter blocks beyond 4 GB
;--- 00000000-003fffffh
	test word ptr [ebx].XMS_HANDLE.xh_baseK+2, 0ffc0h
	jnz @@skipitem

    mov esi, [ebx].XMS_HANDLE.xh_sizeK
    cmp  [ebx].XMS_HANDLE.xh_flags,XMSF_FREE
    jnz @@notfree
    add edx, esi
    cmp esi, eax              ; check if larger than largest
    jbe @@notfree
    mov eax,esi               ; larger, update
@@notfree:
    add esi,[ebx].XMS_HANDLE.xh_baseK
    cmp edi,esi
    jae @@skipitem
    mov edi,esi             ; higher address, update
@@skipitem:
    add ebx,size XMS_HANDLE
    loop @@nextitem
    pop ebx
    mov bl,0
    and edx,edx
    jnz @@freeblockexists
    mov bl,XMS_ALL_MEM_ALLOCATED
@@freeblockexists:
    mov ecx,edi     ; highest address to ecx return value
    shl ecx,10      ; convert to bytes
    dec ecx         ; relative zero
    ret             ; success

xms_ext_query_free_mem endp    

;--- AH=08h: get free mem info

xms_query_free_mem proc
           
    @dprintf ?EMBDBG, <"xms_query_free_mem",10>

    push ecx
    push eax
    push edx

    call xms_ext_query_free_mem 

    ; the call returned:
    ;   EAX=size of largest free XMS block in kbytes
    ;   ECX=highest ending address of any memory block (not used)
    ;   EDX=total amount of free XMS in kbytes

    movzx ecx, [x2max]
    cmp edx,ecx             ; dx = min(edx,0ffff | 7fff)
    jb @@edx_not_larger
    mov edx,ecx
@@edx_not_larger:
    cmp eax,ecx             ; ax = min(eax,0ffff | 7fff)
    jb @@eax_not_larger
    mov eax,ecx
@@eax_not_larger:
                ; use LoWords only
    mov [esp+0],dx
    mov [esp+4],ax
    pop edx
    pop eax
    pop ecx
    ret

xms_query_free_mem endp

;--- AH=0A, free emb in DX

xms_free_emb proc

    @dprintf ?EMBDBG, <"xms_free_emb, dx=%X",10>, dx

    call xms_check_handle_ex     ; check if DX holds a "used" handle, set ESI
    mov bl,XMS_BLOCK_LOCKED
    xor ax,ax
    cmp [esi].XMS_HANDLE.xh_locks,0     ; is the block locked?
    jnz @@exit
    push eax
    push ebx
    push ecx
    push edx
                                    ; see if there are blocks to merge
    mov eax,[esi].XMS_HANDLE.xh_baseK   ; get base address
    mov edx,[esi].XMS_HANDLE.xh_sizeK
    mov edi, eax                    ; base in edi
    add eax, edx                    ; end-address in EAX
ife ?MERGE0HDL
    mov cl, XMSF_FREE
    and edx, edx
    jnz @F
    mov cl, XMSF_INPOOL
@@:
    mov [esi].XMS_HANDLE.xh_flags,cl;mark this block as free (or inpool if size is 0)
    jz @@done
endif

;--- now scan the handle array for successor/predecessor

    movzx ecx,[XMS_Handle_Table.xht_numhandles]
    mov ebx,[XMS_Handle_Table.xht_pArray] 
@@nextitem:
    cmp [ebx].XMS_HANDLE.xh_flags,XMSF_FREE
    jnz @@skipitem
    mov edx,[ebx].XMS_HANDLE.xh_baseK
    cmp eax, edx                    ; is successor also free?
    je @F
    add edx,[ebx].XMS_HANDLE.xh_sizeK
    cmp edi, edx                    ; is predecessor free?
    jne @@skipitem
@@:
;--- predecessor/successor in EBX
    cmp ebx,esi
    jbe @F
    xchg ebx,esi                    ; merge into the "lower" handle and free the "higher" handle
@@:
    xor edx, edx                    ; merge 2 handles, then free one
    xchg edx, [esi].XMS_HANDLE.xh_sizeK
    add [ebx].XMS_HANDLE.xh_sizeK, edx  ;new size is sum(hdl1.size,hdl2.size)
    xor edx, edx
    xchg edx, [esi].XMS_HANDLE.xh_baseK
    cmp edx, [ebx].XMS_HANDLE.xh_baseK
    ja @F
    mov [ebx].XMS_HANDLE.xh_baseK, edx  ;new base is min(hdl1.base,hdl2.base)
@@:
    mov [esi].XMS_HANDLE.xh_flags,XMSF_INPOOL
    mov esi,ebx
@@skipitem:
    add ebx,sizeof XMS_HANDLE
    loop @@nextitem
if ?MERGE0HDL
    mov cl, XMSF_FREE
    cmp [esi].XMS_HANDLE.xh_sizeK,0
    jnz @F
    mov cl,XMSF_INPOOL
@@:
    mov [esi].XMS_HANDLE.xh_flags,cl
endif
@@done:
    pop edx
    pop ecx
    pop ebx
    pop eax
    inc eax
    mov bl,0
@@exit:
    ret

xms_free_emb endp

;--- AH=0C, lock EMB in DX, return base in DX:BX

xms_lock_emb proc

    @dprintf ?EMBDBG, <"xms_lock_emb enter, dx=%X",10>, dx

    call xms_check_handle_ex    ; check if DX holds "used" handle
    xor ax,ax                   ; flag error 
    inc [esi].XMS_HANDLE.xh_locks   ; increase lock counter
    jz @@lock_error
    mov esi,[esi].XMS_HANDLE.xh_baseK
    shl esi,10                  ; calculate linear address
    push esi
    pop bx
    pop dx
    inc eax
    ret
@@lock_error::
    dec [esi].XMS_HANDLE.xh_locks
    mov bl,XMS_LOCK_COUNT_OVERFLOW
    ret
xms_lock_emb endp

if ?XMS35
;******************************************************************************
; locks a (super-extended) MB
; In:   AH=0cch
;   DX=XMS handle to be locked
; Out:  AX=1 if block is locked
;     EDX:EBX=64-bit linear address of block
;   AX=0 if not successful
;     BL=080h -> function not implemented
;     BL=081h -> VDISK is detected
;     BL=0a2h -> handle is invalid
;     BL=0ach -> lock count overflow
;     BL=0adh -> lock fails

xms_sext_lock_emb proc

	@dprintf ?EMBDBG, <"xms_sext_lock_emb enter",10>
	call xms_check_handle_ex	; check if dx holds "used" handle
    xor ax,ax                   ; flag error 
	inc [esi].XMS_HANDLE.xh_locks; increase lock counter
	jz @@lock_error
	mov ebx,[esi].XMS_HANDLE.xh_baseK
	mov edx,ebx
	shl ebx,10					; calculate linear address 0-31
	shr edx,22					; calculate linear address 32-41
	inc eax
	ret
xms_sext_lock_emb endp
endif

;--- AH=0D, unlock EMB in DX

xms_unlock_emb proc

    @dprintf ?EMBDBG, <"xms_unlock_emb enter",10>
    call xms_check_handle_ex       ; check if DX holds "used" handle
    xor ax,ax
    cmp [esi].XMS_HANDLE.xh_locks,al; check if block is locked
    jz @@is_notlocked
    dec [esi].XMS_HANDLE.xh_locks   ; decrease lock counter
    inc eax
    mov bl,0
    ret
@@is_notlocked:
    mov bl,XMS_BLOCK_NOT_LOCKED
    ret
xms_unlock_emb endp

;--- AH=8E, dx=handle
;--- out: bh=lock count, cx=free handles, edx=size in kB

xms_ext_get_handle_info proc

    @dprintf ?EMBDBG, <"xms_ext_get_handle_info enter, dx=%X",10>, dx

    call xms_check_handle_ex; check if handle in DX is valid (="used")
    xor cx,cx               ; reset free handle counter
    xor ax,ax
    movzx edx,[XMS_Handle_Table.xht_numhandles]
    mov edi,[XMS_Handle_Table.xht_pArray]
@@nextitem:
    cmp [edi].XMS_HANDLE.xh_flags,XMSF_INPOOL
    setz al
    add cx,ax
    add edi,size XMS_HANDLE
    dec edx
    jnz @@nextitem
    mov bh,[esi].XMS_HANDLE.xh_locks     ; store lock count
    mov edx,[esi].XMS_HANDLE.xh_sizeK    ; store block size
;   mov bl,0   ;set BL on exit?
    mov al,1
    ret
xms_ext_get_handle_info endp

;--- in: ah=0Eh
;--- in: dx=handle
;--- out: ax=0|1
;--- out: if ax==1, dx=size in kB
;--- out: if ax==1, bl=free handle count
;--- out: if ax==1, bh=block lock count

xms_get_handle_info proc

    push ecx
    push edx
    @dprintf ?EMBDBG, <"xms_get_handle_info enter, dx=%X",10>, dx
    
    call xms_ext_get_handle_info ;modifies edx, bx, cx; ax=0|1
    or ax,ax
    jz @@get_handle_info_err    ; if invalid handle (bl=A2h then)

;--- in cx, free handles
    cmp ch,0                    ; bl = min(cx,0xff)
    jz @@handle_count_ok
    mov cl,0ffh
@@handle_count_ok:
    mov bl,cl

    cmp edx,010000h
    jb @@handle_size_ok
if ?HINF_MSCOMP
    dec ax
    mov bl,XMS_INVALID_HANDLE
    jmp @@get_handle_info_err
else
    mov dx,0ffffh               ; dx = min(edx,0xffff);
endif
@@handle_size_ok:
    mov [esp],dx
@@get_handle_info_err:
    pop edx
    pop ecx
    ret

xms_get_handle_info endp

;--- realloc emb
;--- dx=handle, ebx=new size
;--- modifies esi, edi, ax, bl

xms_ext_realloc_emb proc public

    @dprintf ?EMBDBG, <"xms_ext_realloc_emb enter, dx=%X ebx=%X esp=%X",10>, dx, ebx, esp
    call xms_check_handle_ex   ; dx == "used" handle?
    push edx

; fail if block is locked
    cmp [esi].XMS_HANDLE.xh_locks,0
    jne @@ext_xms_locked

    mov edx, ebx
if 1;v5.80
;--- find the successor.
	movzx ecx,[XMS_Handle_Table.xht_numhandles]
	mov edi,[XMS_Handle_Table.xht_pArray]
	mov eax,[esi].XMS_HANDLE.xh_sizeK
	add eax,[esi].XMS_HANDLE.xh_baseK
nextitem:
	test [edi].XMS_HANDLE.xh_flags,XMSF_FREE	;scan "free embs" only
	jz skipitem
	cmp eax,[edi].XMS_HANDLE.xh_baseK	;successor?
	jnz skipitem
	mov eax,[esi].XMS_HANDLE.xh_sizeK
	add eax,[edi].XMS_HANDLE.xh_sizeK	;get the total size
	cmp edx,eax                         ;new size > total size?
	ja @@ext_growing                    ;then the handle can't grow, have to copy...
	sub edx,[esi].XMS_HANDLE.xh_sizeK	;get the size which is additionally needed (might be < 0!)
	mov [esi].XMS_HANDLE.xh_sizeK, ebx
	add [edi].XMS_HANDLE.xh_baseK, edx
	sub [edi].XMS_HANDLE.xh_sizeK, edx
	jnz @@ext_grow_success              ;remaining size > 0?
	mov [edi].XMS_HANDLE.xh_flags, XMSF_INPOOL	;no, so free the handle
	mov [edi].XMS_HANDLE.xh_baseK, 0
	jmp @@ext_grow_success
skipitem:
	add edi,sizeof XMS_HANDLE
	loop nextitem
endif
    cmp ebx,[esi].XMS_HANDLE.xh_sizeK
    jbe @@ext_shrink_it

@@ext_growing:
; growing, try to allocate a new block

    mov ah,11h              ;11h is xms_ext_alloc_emb #
    test word ptr [esi].XMS_HANDLE.xh_baseK+2, 0FFC0h
    jz @F
    mov ah,15h              ;15h is for super-extended memory
;	test word ptr [esi].XMS_HANDLE.xh_sizeK+2, 0FFC0h   ;old size >= 4G
;	jnz @@ext_failed                                    ;then fail for now
@@:
    call xms_ext_alloc_emb  ;get a new handle in DX, size EDX
    and ax,ax
    jz @@ext_failed

; got new block, copy info from old block to new block


; transfer old handle data to new location
; since the block may be > 4G and max amount to copy is 4G-2,
; the transfer is done with chunks of max. 4G - 1K.

MAXCHUNK equ 4096 * 1024 - 1

    movzx esi,word ptr [esp] ; get old handle
    xor edi,edi
if ?XMS35
    push edi            ; bits 32-39 of src/dst.offset (pushed as dword for alignment reasons)
endif
    push edi            ; dst.offset
    push dx             ; dst.handle
    push edi            ; src.offset
    push si             ; src.handle
    add esi,[dwRes]
if ?XMS35
    mov ecx,[esi].XMS_HANDLE.xh_sizeK
nextchk:
    mov edi, ecx
    cmp ecx, MAXCHUNK   ;remaining more than max.?
    jb @F
    mov edi, MAXCHUNK   ;load edi with 4G-1K
@@:
else
    mov edi,[esi].XMS_HANDLE.xh_sizeK
endif
    shl edi, 10         ; K to byte
    push edi            ; length
    mov esi, esp
if ?XMS35
    mov ah, 16h         ; always use superext move
endif
    call xms_move_emb_ex
if ?XMS35
    mov esi, esp
    pop edi                                 ; get size of current chunk in edi
    add [esi].XMS_MOVEX.src_offset, edi     ; adjust src and dest offsets
    adc [esi].XMS_MOVEX.src_hi, 0           ; including bits 32-39
    add [esi].XMS_MOVEX.dest_offset, edi
    adc [esi].XMS_MOVEX.dest_hi, 0
    shr edi, 10
    sub ecx, edi
    jnz nextchk
    add esp, sizeof XMS_MOVEX-2
else
    add esp, sizeof XMS_MOVE
endif
    movzx esi,word ptr [esp]
    add esi,[dwRes]

; swap handle data so handle pointers remain valid
; handle data is 10 bytes long

    push edx
    movzx edi,dx
    add edi,[dwRes]
    mov edx,[esi+0]
    xchg edx,[edi+0]
    mov [esi+0],edx
    mov edx,[esi+4]
    mov ax,[esi+8]
    xchg edx,[edi+4]
    xchg ax,[edi+8]
    mov [esi+4],edx
    mov [esi+8],ax
    pop edx

; free newly allocated handle in DX with old handle data in it

    call xms_free_emb
    jmp @@ext_grow_success

@@ext_no_xms_handles_left:
    pop ebx
    mov bl,XMS_NO_HANDLE_LEFT
    jmp @@ext_failed

@@ext_xms_locked:
    mov bl,XMS_BLOCK_LOCKED

@@ext_failed:
    pop edx
    xor ax,ax
    ret

;--- shrink a memory block
;--- esi = handle data
;--- edx,ebx = new size

@@ext_shrink_it:
    mov edi,[esi].XMS_HANDLE.xh_sizeK    ; get old size
    sub edi, edx                     ; calculate what's left over
    jz @@ext_dont_need_handle        ; jump if we don't need another handle
    push ebx
    call xms_alloc_handle            ; alloc a handle in EBX (edx not modified)
    jc @@ext_no_xms_handles_left     ; exit if no more handles
    mov [esi].XMS_HANDLE.xh_sizeK, edx ;set new (reduced) size
    add edx,[esi].XMS_HANDLE.xh_baseK; calculate base of new "free" block
    mov [ebx].XMS_HANDLE.xh_baseK,edx
    mov [ebx].XMS_HANDLE.xh_sizeK,edi
if 1;v5.80
;--- if this branch is active, there's surely NO free successor
;--- so we don't need to merge.
	mov [ebx].XMS_HANDLE.xh_flags,XMSF_FREE
	pop ebx
else
    mov word ptr [ebx].XMS_HANDLE.xh_flags,XMSF_USED
    mov edx,ebx                      ; and FREE it again -
    sub edx,[dwRes]                  ;!!! 2.2.2020: line added for v5.79
    pop ebx
    call xms_free_emb                ; to merge it with free block list
endif
@@ext_dont_need_handle:
@@ext_grow_success:
    pop edx
    @dprintf ?EMBDBG, <"xms_ext_realloc_emb exit, esp=%X",10>, esp
    mov ax,1
    mov bl,0
    ret
xms_ext_realloc_emb endp

;--- dx=handle, bx=new size

xms_realloc_emb proc

    @dprintf ?EMBDBG, <"xms_realloc_emb enter, ebx=%X",10>, ebx
    push ebx                        ; preserve Hiword(ebx)
    movzx ebx,bx                    ; clear top 16 bit
    call xms_ext_realloc_emb
    mov [esp],bx                   ; modify Loword(ebx)
    pop ebx
    @dprintf ?EMBDBG, <"xms_realloc_emb exit, ebx=%X",10>, ebx
    ret                                 

xms_realloc_emb endp

; calculate the move src/dst address
; In: SI - handle (0 if EDX should be interpreted as seg:ofs value)
;   EDX - offset
;   ECX - length
; Out: SI:EAX=linear address 00-39

xms_get_move_addr proc
    or si,si           ; translate address in EDX?
    jnz @@is_emb

                        ; its segment:offset in EDX

                        ; eax = 16*(edx high) + dx
    movzx eax,dx        ; save offset
    mov dh,0
    shr edx,12          ; convert segment to absolute address
    add eax,edx         ; add offset

    mov edx,eax         ; check that eax(address) + ecx (length) is <= 10fff0
    add edx,ecx
    jc @@wrong_size     ; negative length might wrap
    cmp edx,10fff0h
    ja @@wrong_size
    clc
    ret

@@is_emb:               ; it's a handle:offset pair
    call xms_check_handle   ;check if SI holds a "used" handle

if ?XMS35
    push ebx
    xor ebx,ebx
endif
    mov eax,ecx         ; contains length
    add eax,edx         ; assert length + offset < size    
if ?XMS35
    adc ebx,ebx
else
    jc @@wrong_size
endif
    add eax,1024-1      ; round up to kB
if ?XMS35
    adc ebx,0
    shrd eax,ebx,10     ; convert to kB units
    pop ebx
else
    jc @@wrong_size
    shr eax,10          ; convert to kB units
endif
    cmp eax,[esi].XMS_HANDLE.xh_sizeK    ; compare with max offset
    ja @@wrong_size

    mov eax,[esi].XMS_HANDLE.xh_baseK   ; get block base address
    mov esi,eax         ; store in source index
    shl eax,10          ; convert from kb to linear
    shr esi,22
    add eax,edx         ; add offset into block
if ?XMS35
    adc esi,ebx
endif
    ret

@@wrong_size:
    mov bl,XMS_INVALID_LENGTH
    xor ax,ax
    stc
    ret
    align 4
xms_get_move_addr endp

;--- move extended memory block
;--- v86 DS:SI->XMS_MOVE

xms_move_emb proc

    movzx edi,word ptr [ebp].Client_Reg_Struc.Client_DS
    shl edi, 4
    movzx esi,si
    add esi,edi
xms_move_emb_ex::           ; <--- entry for internal use (realloc)
if ?XMS35
    mov byte ptr [ebp].Client_Reg_Struc.Client_Error+3,ah  ;abuse Error field to store AH
endif
    xor ax,ax               ; default to error
    push ecx
    push edx
    push eax
    push ebx

    @dprintf ?EMBDBG, <"xms_move_emb: siz=%X src=%X:%X dst=%X:%X",10>,\
        [esi].XMS_MOVE.len, [esi].XMS_MOVE.src_handle, [esi].XMS_MOVE.src_offset, [esi].XMS_MOVE.dest_handle, [esi].XMS_MOVE.dest_offset

    mov ecx,[esi].XMS_MOVE.len      ; get length
    test cl,1                       ; is it even?
    jnz @@move_invalid_length

if ?XMS35
    xor ebx, ebx
    cmp byte ptr [ebp].Client_Reg_Struc.Client_Error+3, 16h
    jnz @F
    mov bl,[esi].XMS_MOVEX.dest_hi
@@:
endif
    push esi
    mov edx,[esi].XMS_MOVE.dest_offset
    mov si,[esi].XMS_MOVE.dest_handle
    call xms_get_move_addr          ; get move address
    mov edx,esi ;save lines 32-39 in DX, since BL must be preserved
    pop esi
    jc @@copy_dest_is_wrong
    mov edi,eax                     ; store in destination index
if ?XMS35
    cmp byte ptr [ebp].Client_Reg_Struc.Client_Error+3, 16h
    jnz @F
    mov bl,[esi].XMS_MOVEX.src_hi
@@:
    push edx
endif
    mov edx,[esi].XMS_MOVE.src_offset
    mov si,[esi].XMS_MOVE.src_handle
    call xms_get_move_addr          ; get move address
if ?XMS35
    pop edx
endif
    jc @@copy_source_is_wrong
    xchg eax,esi
if ?XMS35
    mov bh,al
    mov bl,dl
endif

;**************************************************
; setup finished with
;   BH.ESI = source A00-A39
;   BL.EDI = destination A00-A39
;   ECX = number of words to move
;**************************************************
 if ?XMS35
    @dprintf ?EMBDBG,<"xms_move_emb: siz(byt)=%X src(40bit)=%X%08X dst(40bit)=%X%08X",10>, ecx, bh, esi, bl, edi
 else
    @dprintf ?EMBDBG,<"xms_move_emb: siz(byt)=%X src(32bit)=%X dst(32bit)=%X",10>, ecx, esi, edi
 endif

    or ecx,ecx                 ; nothing to do ??
    jz @@xms_exit_copy

; overlap test. start of destination block (BL.EDI)
; must either be <= start of source block (BH.ESI) 
; or  >= start of source block + block length (BH.ESI+ECX)

; 1. check if BL.EDI <= BH.ESI
if ?XMS35
    cmp bl,bh
    jb @@move_ok_to_start
    ja @F
endif
    cmp edi,esi
    jbe @@move_ok_to_start
if ?XMS35
@@:
; calculate source + block length: DL.EAX = BH.ESI + ECX
    mov dl,bh
endif
    mov eax, esi
    add eax, ecx
if ?XMS35
    adc dl,0
; 2. check if BL.EDI >= DL.EAX
    cmp bl,dl
    ja @@move_ok_to_start
    jb @@move_invalid_overlap
endif
    cmp edi,eax
    jb @@move_invalid_overlap

@@move_ok_to_start:

if ?XMS35
	and bx,bx
	jnz @F
endif
    call MoveMemoryPhys
if ?XMS35
    jmp @@xms_exit_copy
@@:
    movzx ax,bh
    movzx dx,bl
    call MoveMemoryPhysEx ;copy ecx bytes from [ax:esi] to [dx:edi]
endif
@@xms_exit_copy:
    pop ebx
    pop eax
    pop edx
    pop ecx
    inc eax         ; success
;   mov bl,0        ; BL is not set to 00 by MS Himem    
    ret

@@move_invalid_overlap:
    mov bl,XMS_INVALID_OVERLAP
    jmp @@xms_exit_copy_failure

@@move_invalid_length:
    mov bl,XMS_INVALID_LENGTH
    jmp @@xms_exit_copy_failure

@@copy_source_is_wrong:
    cmp bl,XMS_INVALID_LENGTH
    je @@xms_exit_copy_failure
    mov bl,XMS_INVALID_SOURCE_HANDLE
    jmp @@xms_exit_copy_failure

@@copy_dest_is_wrong:
    cmp bl,XMS_INVALID_LENGTH
    je @@xms_exit_copy_failure
    mov bl,XMS_INVALID_DESTINATION_HANDLE
    jmp @@xms_exit_copy_failure

@@move_a20_failure:
    mov bl,XMS_A20_FAILURE

                            ; common error exit routine
@@xms_exit_copy_failure:
    mov al,bl
    pop ebx
    mov bl,al
    pop eax
    pop edx
    pop ecx
    ret

xms_move_emb endp

    align 4
xms_global_enable_a20:
xms_global_disable_a20:
xms_local_enable_a20:
xms_local_disable_a20:
    call XMS_HandleA20
    mov word ptr [ebp].Client_Reg_Struc.Client_EAX, ax
    mov eax, [ebp].Client_Reg_Struc.Client_EAX
    mov ecx, [ebp].Client_Reg_Struc.Client_ECX
    ret

endif


if ?A20XMS

    align 4

; handles XMS A20 functions
; 3 = global enable
; 4 = global disable
; 5 = local enable
; 6 = local disable

XMS_HandleA20 proc

    mov al,ah
if ?A20DBG
    push eax
    @dprintf ?A20DBG, <"XMS A20 emulation, ah=%X, curr cnt=%X, curr state=%X",10>, al,[wA20], [bA20Stat]
    pop eax
endif

    mov cx, word ptr [wA20]
    cmp al,4
    jb @@glen
    jz @@gldi
    cmp al,6
    jb @@loen
    jmp @@lodi

@@glen:
    or ch,1
    jmp @@testa20
@@gldi:
    and ch,not 1
    jcxz @@testa20
    jmp @@stillenabled
@@loen:
    inc cl
    jz @@localerr
    jmp @@testa20
@@lodi:
    sub cl,1
    jc @@localerr2
    and cx, cx
    jnz @@stillenabled
@@testa20:
    and cx, cx
    setnz al
    call A20_Set
@@notchanged:
    mov ax,1
    mov bl,0
    mov [wA20],cx
    jmp @@a20_exit
@@localerr2:
if 1        ;potential Delay Angel
    inc cl
    dec ch
    jz @@testa20
endif
@@localerr:
if 1
    xor eax,eax
    mov bl,82h
else
    mov ax,1
endif
    jmp @@a20_exit
@@stillenabled:    
    mov [wA20],cx
    xor eax,eax
    mov bl,94h

@@a20_exit:
    ret
    align 4

XMS_HandleA20 endp

endif

if ?A20PORTS or ?A20XMS

;--- set PTEs for HMA to emulate enable/disable A20
;--- in: AL=1 enable, AL=0 disable
;--- ecx+edx must be preserved

A20_Set proc public
    cmp [bNoA20], 0 ;NOA20 option set?
    jnz @@exit
    cmp al,[bA20Stat];status change?    
    jz @@exit
    mov [bA20Stat],al
    push edi
    and eax,1
    shl eax,20     ;000000h or 100000h
    or eax, PTF_PRESENT or PTF_RW or PTF_USER
    @GETPTEPTR edi, ?PAGETAB0+256*4, 1  ;EDI?= ptr PTE for 0100000h
@@spec_loop:
    stosd
    add ah,10h      ;10000x, 10100x, 10200x, ...
    jnz @@spec_loop
    pop edi
if 0  ;usually "16 * INVLPG" is slower than 1 * "mov cr3, eax"
 if ?INVLPG
    cmp [bNoInvlPg],0
    jnz @@noinvlpg
    mov eax, 100000h
@@nextpte:
    invlpg ds:[eax]
    add ah, 10h
    jnz @@nextpte
    ret
@@noinvlpg:
 endif
endif
; flush TLB to update page maps
    mov eax,CR3
    mov CR3,eax
@@exit:
    ret
    align 4

A20_Set endp

endif

if ?A20PORTS

;--- port trap handlers
;--- eax=value (for out)
;--- dx=port
;--- cl=type

P60BITOFS   equ size TSSSEG+32+60h/8

A20_Handle60 proc public
if ?DYNTRAPP60
    mov ebx, [dwTSS]
    and dword ptr [ebx+P60BITOFS],not 1
endif
    test cl,OUT_INSTR   ;is it IN or OUT?
    jz @@input
ife ?DYNTRAPP60
    cmp [bLast64],0D1h  ;last value written to 64 was "write output port"?
    jnz Simulate_IO
    mov [bLast64],0
endif
    push eax
    @dprintf ?A20DBG, <"A20_Handle60: write to port 60h kbc output port, al=%X",10>, al
    shr al,1
    and al,1
    call A20_Set
    pop eax
    or al,2
    out dx, al
    ret
@@input:
ife ?DYNTRAPP60
    cmp [bLast64],0D0h  ;last value written to 64 was "read output port"?
    jnz Simulate_IO
endif
A20_Inp92::
    in al,dx
    and al, not 2
    mov ah, [bA20Stat]
    shl ah, 1
    or al, ah
    @dprintf ?A20DBG, <"A20_Handle60: read port %X kbc output port, al=%X",10>, dx, al
    ret
    align 4
A20_Handle60 endp

A20_Handle64 proc public
    test cl, OUT_INSTR
    jz Simulate_IO
if ?DYNTRAPP60
    mov ah,al
    and ah,0FEh
    cmp ah,0D0h
    jnz Simulate_IO
    mov ebx, dwTSS
    or dword ptr [ebx+P60BITOFS],1
else
    mov [bLast64],al    ;save last value written to port 64h
endif
if ?A20DBG
;   cmp al,0D1h
;   jnz @@nokbcout
    @dprintf ?A20DBG, <"A20_Handle64: write to port 64h, al=%X",10>, al
@@nokbcout:
endif
    out dx, al
    ret
    align 4
A20_Handle64 endp

A20_Handle92 proc public
    test cl, OUT_INSTR  ;is it IN or OUT?
    jz A20_Inp92
    @dprintf ?A20DBG, <"A20_Handle92: write to port 92h, al=%X",10>, al
    push eax
    shr al,1
    and al,1
    call A20_Set
    pop eax
    or al, 2       ;dont allow disable
if 1
;--- refuse reset via bit 0 = 1
    and al,not 1
endif
    out dx, al
    ret
    align 4
A20_Handle92 endp

endif

.text$03 ends

.text$04 segment

;--- init XMS
;--- esi -> JEMMINIT

XMS_Init proc public

if ?A20PORTS or ?A20XMS
    mov al, [esi].JEMMINIT.NoA20
    mov [bNoA20],al
endif

if ?INTEGRATED
    mov ax, [esi].JEMMINIT.HmaMin
    mov [hmamin], ax
    mov ax, [esi].JEMMINIT.X2Max
    mov [x2max], ax
    @dprintf ?INITDBG, <"XMS init: x2max=%X",10>, ax
    mov al, [esi].JEMMINIT.A20Method
    mov [A20Index],al
 if ?XMS35
    mov ax, [esi].JEMMINIT.xms_version
    mov xms_version,ax
 endif
else
    mov ax, [esi].JEMMINIT.XMSControlHandle
    mov [XMSCtrlHandle],ax
endif

;---  is XMS pool on? then direct access to XMS handle table required?

ife ?INTEGRATED
    cmp [bNoPool],0
    jne @@noxmsarray
endif
    mov ecx, [esi].JEMMINIT.XMSHandleTable	;get FAR16 address of XMS handle table
    movzx eax, cx
    shr ecx, 12
    and cl, 0F0h
    add ecx, eax	;convert to linear address in ecx
    
; transfer XMS table info to fixed memory location, assume size 8 (sizeof XMS_HANDLETABLE)

    mov eax,[ecx+0]     ;get sig(byte), hdlsiz(byte) in ax and numhandles(word) into HiWord(eax)
    mov dword ptr [XMS_Handle_Table],eax
ife ?INTEGRATED
    test eax,0FFFF0000h      ;if size of array is null, disable pooling
    setz [bNoPool]
    jz @@noxmsarray
endif
    movzx edx,word ptr [ecx+4]  ;offset of xht_pArray
    movzx eax,word ptr [ecx+6]	;segment of xht_pArray
    shl eax,4
    add eax,edx
ife ?INTEGRATED
    and eax, eax        ;if the array pointer is NULL, disable pooling
    setz [bNoPool]
    jz @@noxmsarray
endif
    cmp eax, 100000h    ;is handle array in HMA?
    jb @@nohmaadjust

    push eax
    mov cl,16
    mov eax, 100000h
    call MapPhysPagesEx
    mov [PageMapHeap], edx
    
    @dprintf ?INITDBG, <"HMA shadowed at %X",10>, eax
    pop ecx
    sub ecx, 100000h
    add eax, ecx

@@nohmaadjust:
    mov [XMS_Handle_Table.xht_pArray],eax
@@noxmsarray:

    ret
XMS_Init endp

.text$04 ends

    END
