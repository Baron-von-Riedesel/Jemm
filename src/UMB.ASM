
;--- XMS UMB part implementation
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

;--- for 100% MS compatibility, the UMB handler would have to
;--- implement a linked list of special MCBs:

UMBMCB struct
sig   db ?   ;signature 'M'
segm  dw ?   ;segment address of content or 0000 if UMB is free
size_ dw ?   ;size in paragraps
      db 3 dup (?)
name_ db 8 dup (?) ;name (='UMB',0,0,0,0,0)
UMBMCB ends

;   assume SS:FLAT,DS:FLAT,ES:FLAT

.text$01 SEGMENT

UMBsegments UMBBLK UMB_MAX_BLOCKS dup (<>)
UMBend  label byte

.text$01 ends

.text$03 segment

;--- XMS UMB handler
;--- EAX, EBX, EDX hold client values

umb_handler proc public

    cmp ah,11h          ;free UMB, DX=segment address to release
    je UMB_free
    cmp ah,12h          ;realloc UMB, DX=segment to resize, BX=new size
    je UMB_realloc

umb_handler endp        ;fall thru!

;--- UMBalloc
;--- inp: DX=size of block in paragraphs, size=0 is allowed
;--- out: success: AX=1, BX=segment, DX=size
;---      error:   AX=0, BL=error code, DX=largest block

UMB_alloc proc

if ?UMBDBG
    @DbgOutS <"UMBalloc enter, DX=">,1
    @DbgOutW dx,1
    @DbgOutS <10>,1
endif

    mov esi, offset UMBsegments
    xor ebx,ebx     ; holds largest too-small block size

@@UMBloop:
    cmp [esi].UMBBLK.wSegm,0    ; see if valid UMB
    je @@UMBnext                ; no
    test BYTE PTR [esi].UMBBLK.wSize+1,UMB_ALLOCATED
    jne @@UMBnext               ;  yes
    cmp dx,[esi].UMBBLK.wSize   ; dx = requested block size (high bit of UMB size known reset)
    jbe @@UMBfound              ; enough memory available in UMB
    cmp bx,[esi].UMBBLK.wSize
    ja @@UMBnext
    mov bx,[esi].UMBBLK.wSize   ; update largest too-small block size
@@UMBnext:
    add esi,size UMBBLK
    cmp esi,offset UMBend
    jnz @@UMBloop
if ?UMBDBG
    @DbgOutS <"UMBalloc failed, bx=">,1
    @DbgOutW bx,1
    @DbgOutS <10>,1
endif
    xor eax,eax     ; flag failure
    or ebx,ebx
    jne @@umb_too_small
    mov bl,0B1h     ; error "no UMB's are available"
    xor edx,edx
    jmp UMB_exit
@@umb_too_small:
    mov edx,ebx     ; return largest UMB in DX
    mov bl,0B0h     ; error "only smaller UMB available"
    jmp UMB_exit

@@UMBfound:

; see if actual UMB size exceeds request size by >=2K

    mov ax,80h              ; 128 paras == 2K
    add ax,dx
    cmp ax,[esi].UMBBLK.wSize
    ja @@good_umb          ; can't split it, just use it

;  2K or over would be unused, see if we can split the block

    mov ebx, offset UMBsegments
@@splitloop:
    cmp [ebx].UMBBLK.wSegm,0
    je @@freefound
    add ebx,size UMBBLK
    cmp ebx,offset UMBend
    jne @@splitloop
    jmp @@good_umb
    
;-- an unused entry found, split the block

@@freefound:
    mov eax, edx
    add eax, 7Fh
    and eax,not 7Fh             ; round up allocation to next 2K in paras
    mov cx,[esi].UMBBLK.wSegm
    add cx,ax
    mov [ebx].UMBBLK.wSegm,cx   ; new block has segment offset of old block+allocation
    mov cx,[esi].UMBBLK.wSize   ; get original UMB block size, in paras
    sub cx,ax                   ; subtract allocation
    mov [ebx].UMBBLK.wSize,cx   ; update new block with old block size minus allocation
    mov [esi].UMBBLK.wSize,ax   ; update original UMB block size to allocation
if ?UMBDBG
    @DbgOutS <"UMB block split, new entry=">,1
    @DbgOutD ebx,1
    @DbgOutS <" segm=">,1
    @DbgOutW [ebx].UMBBLK.wSegm,1
    @DbgOutS <", size=">,1
    @DbgOutW [ebx].UMBBLK.wSize,1
    @DbgOutS <10>,1
endif

@@good_umb:
    mov dx,[esi].UMBBLK.wSize               ; return actual block size in dx
    or BYTE PTR [esi].UMBBLK.wSize+1,UMB_ALLOCATED
    mov bx,[esi].UMBBLK.wSegm               ; get UMB segment address in bx
    mov word ptr [EBP].Client_Reg_Struc.Client_EBX,bx
    mov ax,1
UMB_alloc endp  ;fall throu

;--- there was a problem with JWasm if there's a jump to a forward
;--- reference which is not a simple label but a PROC! If the 
;--- jump cannot be SHORT, the displacement isn't adjusted then!

UMB_exit proc
;UMB_exit:
if ?UMBDBG
    @DbgOutS <"UMB exit, ax=">,1
    @DbgOutW ax,1
    @DbgOutS <", bx=">,1
    @DbgOutW bx,1
    @DbgOutS <", dx=">,1
    @DbgOutW dx,1
    @DbgOutS <10>,1
endif
    mov word ptr [ebp].Client_Reg_Struc.Client_EAX, ax
    mov word ptr [ebp].Client_Reg_Struc.Client_EDX, dx
    and al,al
    jnz @@umbexit_noerror
    mov byte ptr [ebp].Client_Reg_Struc.Client_EBX, bl
@@umbexit_noerror:
    ret
UMB_exit endp

;--- UMBFree
;--- todo: merge free blocks

;UMB_free proc
UMB_free:
if ?UMBDBG
    @DbgOutS <"UMBfree enter, DX=">, 1
    @DbgOutW DX, 1
    @DbgOutS <10>, 1
endif

    call UMB_findblock  ;clears eax
    jc  UMB_exit
    and BYTE PTR [esi].UMBBLK.wSize+1,7fh   ; flag UMB not allocated
    inc eax         ; flag success
    jmp UMB_exit

;UMB_free endp

;--- UMBrealloc
;--- currently can only shrink a block
;--- and it does not really shrink, just return success
;--- inp: DX=segment, BX=new size of block in paragraphs

UMB_realloc proc

;;  mov ebx,[ebp].Client_Reg_Struc.Client_EBX   ; restore EBX

if ?UMBDBG
    @DbgOutS <"UMBrealloc enter, DX=">, 1
    @DbgOutW DX,1
    @DbgOutS <", BX=">, 1
    @DbgOutW BX,1
    @DbgOutS <10>, 1
endif

    call UMB_findblock  ;clears eax
    jc UMB_exit
    mov cx, [esi].UMBBLK.wSize
    and ch, 7Fh
    cmp bx, cx
    ja @@umbreal_error
    inc eax         ; flag success
    jmp UMB_exit
@@umbreal_error:    ; block is too small
    mov dx,cx
    mov bl,0B0h
    jmp UMB_exit

UMB_realloc endp

UMB_findblock proc
    mov esi,offset UMBsegments
    xor eax,eax                 ; flag failure
@@freeloop:
    cmp [esi].UMBBLK.wSegm,dx   ; see if matches existing UMB allocation
    je  @@blockfound
    add esi,size UMBBLK
    cmp esi,offset UMBend
    jnz @@freeloop
@@blocknotalloced:
    mov bl,0b2h                 ; invalid UMB segment number error code
    stc
    ret
@@blockfound:
    test byte ptr [esi].UMBBLK.wSize+1,UMB_ALLOCATED
    jz @@blocknotalloced
    clc
    ret
    align 4
UMB_findblock endp

.text$03 ends

    END
