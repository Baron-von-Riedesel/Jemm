
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

UMBsegments UMBBLK UMB_MAX_BLOCKS dup (<0,0>)
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

.text$04 segment

;--- UMB initialization code
;--- in: ESI->JemmIni
;--- preserves esi, ebp

UMB_Init proc public
    mov ebx,[esi].JEMMINIT.PageMap
    mov ecx,0A0h
    mov edi,offset UMBsegments - size UMBBLK
    mov dl,0
@@nextitem2:
    mov al,[ebx+ecx]
    call IsShadowRAM
    jnc @@isshadow
    cmp [esi].JEMMINIT.NoRAM,0
    jnz @@skippage2
    call IsUMBMemory
    jc @@skippage2
@@isshadow:
    cmp dl,0
    jz @@newumb
if ?SPLIT
    cmp al,'8'      ;is it a SPLIT ROM?
    jb @@newumb    ;then it must be a new UMB
endif
    add [edi].UMBBLK.wSize,100h
    call clearpage
    jmp @@nextpage
@@newumb:
    add edi, size UMBBLK
    cmp edi, offset UMBsegments + UMB_MAX_BLOCKS * size UMBBLK
    jnc @@umbdone
    inc [esi].JEMMINIT.NumUMBs
    mov byte ptr [edi].UMBBLK.wSegm+1,cl
    @DbgOutS <"new UMB at ">,?INITDBG
    @DbgOutW [edi].UMBBLK.wSegm,?INITDBG
    @DbgOutS <10>,?INITDBG
    mov [edi].UMBBLK.wSize,100h
if ?SPLIT
    call clearpageEx
else
    call clearpage
endif
    mov dl,1
    jmp @@nextpage
@@skippage2:
    mov dl,0
@@nextpage:
    inc ecx
    cmp cl,0F8h
    jb @@nextitem2
@@umbdone:
    @DbgOutS <"UMBs initialized",10>,?INITDBG
    ret
UMB_Init endp

IsShadowRAM proc
    cmp al,'S'
    jnz @@isnotshadow
    push ecx
    shl ecx,12
    mov ah,[ecx]
    mov byte ptr [ecx],55h
    cmp byte ptr [ecx],55h
    jnz @@isnotshadow2
    mov byte ptr [ecx],0AAh
    cmp byte ptr [ecx],0AAh
    jnz @@isnotshadow2
    mov [ecx],ah
    pop ecx
    ret
@@isnotshadow2:
    mov [ecx],ah
    pop ecx
@@isnotshadow:
    stc
    ret
IsShadowRAM endp

;--- clear an UMB "page"
;--- in: ecx = page number
;--- in: al = page type, if '1' <= al < '8' then split ROM
;--- in: EDI -> UMBBLK 

if ?SPLIT

clearpageEx proc
    cmp al,'8'
    jnc clearpage
    sub al,'0'  ;1,2,3,4,5,6,7
    movzx eax,al
    shl eax,5   ;20,40,60,80,A0,C0,E0
    mov byte ptr [edi].UMBBLK.wSegm,al
    sub word ptr [edi].UMBBLK.wSize,ax
    @DbgOutS <"split page, UMB at ">,?INITDBG
    @DbgOutW [edi].UMBBLK.wSegm,?INITDBG
    @DbgOutS <" size=">,?INITDBG
    @DbgOutW [edi].UMBBLK.wSize,?INITDBG
    @DbgOutS <10>,?INITDBG
    shl eax,4   ;1->200, 2->400, 3->600, 4->800, 5->A00, 6->C00, 7->E00
    push edi
    push ecx
    mov edi,ecx
    shl edi,12
    add edi,eax
    sub eax,1000h
    neg eax
    shr eax,2      ;added in v5.78
    mov ecx,eax
    xor eax,eax
    rep stosd
    pop ecx
    pop edi
    ret
clearpageEx endp

endif

;--- clear a "page"
;--- in: ecx = page number

clearpage proc
    push edi
    push ecx
    mov edi,ecx
    shl edi,12
    mov ecx,1000h/4
    xor eax,eax
    rep stosd
    pop ecx
    pop edi
    ret
clearpage endp

.text$04 ends

    END
