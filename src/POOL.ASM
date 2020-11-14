
;--- Jemm's memory pool implementation
;--- originally written by Michael Devore
;--- Public Domain
;--- to be assembled with JWasm or Masm v6.1+

    .486P
    .model FLAT
    option proc:private
    option dotname

    include jemm.inc        ;common declarations
    include jemm32.inc      ;declarations for Jemm32
    include debug.inc

;--- equates

MINXMSSIZE  equ 16      ; ignore XMS blocks smaller 16 kB

;--- assembly time constants

if ?INTEGRATED
?FREEXMS    equ 1       ; std=1, 0 might work
?EXPANDFIRST equ 0      ; std=0, 1 might work
else
?FREEXMS    equ 1       ; std=1, 1=free all XMS on exit
?EXPANDFIRST equ 0      ; std=0, 1 won't work
endif

;--- publics/externals

externdef EMS_CheckMax:near

    include external.inc

;--- private structures

;--- Memory pool descriptor item
;--- this table can grow up to 174784 bytes (64*2731) for 4 GB
;--- standard is 80*64 = 5120 bytes for 120 MB

POOL_SYSTEM_INFO    struct
psi_addressK    DD ? ; base address in K (may not be XMS handle base if handle size changed later)
psi_descptr     DD ? ; pointer to XMS handle descriptor array entry/pseudo-handle value
psi_4kfree      DW ? ; free number of 4K slots (>psi_16kfree*4 if any partials)
psi_16kfree     DB ? ; free number of 16K slots
psi_16kmax      DB ? ; maximum number of 16K allocations (used allocation bytes*2)
psi_startadj    DB ? ; unused K from XMS handle base for 4K alignment (0-3)
psi_endadj      DB ? ; unused K at XMS handle end as 16K chunks (0-15)
psi_flags       DB ? ; various flag values
                DB ? ; alignment
POOL_SYSTEM_INFO    ends

; number of bytes for system info in EMS/VCPI pool allocation block,
;  must be >= sizeof POOL_SYSTEM_INFO or bad things will happen quickly

POOLBLOCK_SYSTEM_SPACE  EQU 16

; number of bytes for allocation in a pool allocation block
; that are 48*8=384 bits, -> 384 * 4 kB -> 1536 kB

POOLBLOCK_ALLOCATION_SPACE  EQU 48
POOLBLOCK_MEMSIZE           equ POOLBLOCK_ALLOCATION_SPACE*8*4

POOLBLOCK_TOTAL_SPACE   EQU POOLBLOCK_SYSTEM_SPACE+POOLBLOCK_ALLOCATION_SPACE

LPPOOL_SYSTEM_INFO typedef ptr POOL_SYSTEM_INFO

;--- start

;   assume SS:FLAT,DS:FLAT,ES:FLAT

.text$01 SEGMENT

PoolAllocationTable DD 0    ; start of pool table
PoolAllocationEnd   DD 0    ; current end of pool table
PoolAllocationMax   DD 0    ; end of pool table (usually 80 entries)

dwMaxMem4K          DD 0    ; max 4k pages allowed
dwTotalMem4K        DD 0    ; total 4k pool pages
dwUsedMem4K         DD 0    ; used 4k pool pages
LastBlockAllocated  DD 0    ; last pool block used for alloc
LastBlockFreed      DD 0    ; last pool block used for free
XMSPoolBlockCount   DD 0    ; count of XMS handles allocated for pool blocks (not counting initial UMB block)

.text$01 ends

.text$03 segment

; Pool memory management routines

;--- convert block index + nibble offset to a physical address
;--- ecx=block index
;--- eax=nibble offset
;--- out: physical address in EAX

Pool_GetPhysAddr proc public
    shl ecx,6                       ; convert to 64-byte block offset
    shl eax,14                      ; 16K to bytes
    add ecx, [PoolAllocationTable]  ; esi -> pool allocation block for page

    mov ecx,[ecx].POOL_SYSTEM_INFO.psi_addressK
    shl ecx,10                      ; K address to bytes
    add eax,ecx                     ; = physical memory address of page
    ret 
    align 4
Pool_GetPhysAddr endp

; get free 4K page count in pool
; out: EAX=free pages
; destroys EDX
; do not write segment registers here,
; the function is called from VCPI protected mode API

Pool_GetFree4KPages PROC public

    call Pool_GetFreeXMSPages   ; get free 4k XMS pages in EDX
    mov eax,[dwTotalMem4K]
    sub eax,[dwUsedMem4K]       ; eax = free 4k pages in Pool
    add edx,eax                 ; edx = true free 4k pages
    mov eax,[dwMaxMem4K]
    sub eax,[dwUsedMem4K]       ; eax = max free 4k pages allowed
    cmp eax,edx
    jb @@uselower
    mov eax,edx
@@uselower:                     ; eax = min(eax, edx)

if ?POOLDBG
    @DbgOutS <"Pool_GetFree4KPages: ">,1
    @DbgOutD eax,1
    @DbgOutS <", dwUsedMem4K=">,1
    @DbgOutD dwUsedMem4K,1
    @DbgOutS <", dwMaxMem4K=">,1
    @DbgOutD dwMaxMem4K,1
    @DbgOutS <10>,1
endif
    ret
    align 4

Pool_GetFree4KPages ENDP

; get free 16K (EMS) page count in pool
; out: EAX = free 16kB pages in pool
; other registers preserved
; the value returned is not just the total of
; the current pool descriptors.
; it is
;     total of free 16k pages in current pool
;   + Min(free XMS pages, dwMaxMem4k - dwTotalMem)/4

Pool_GetFree16KPages PROC public
    push esi
    push ecx
    push edx

;--- get free 16kb pages in pool into EAX

    xor eax, eax
    mov ecx, eax
    mov esi, [PoolAllocationTable]
@@findblkloop:
    mov cl,[esi].POOL_SYSTEM_INFO.psi_16kfree   ; high words known zero
    add eax,ecx
    add esi,POOLBLOCK_TOTAL_SPACE
    cmp esi, [PoolAllocationEnd]
    jb  @@findblkloop

;--- get MIN(free XMS pages, dwMaxMem4k - dwTotalMem)/4 into ESI

    call Pool_GetFreeXMSPages   ;return free 4k XMS pages in EDX

    mov esi, [dwMaxMem4K]
    sub esi, [dwTotalMem4K]
    jnc @@valueok
    xor esi, esi
@@valueok:
    cmp esi, edx
    jb @@issmaller
    mov esi, edx
@@issmaller:
    shr esi, 2

    add eax, esi

if ?POOLDBG
    @DbgOutS <"Pool_GetFree16KPages=">,1
    @DbgOutD eax,1
    @DbgOutS <" max4k=">,1
    @DbgOutD [dwMaxMem4K],1
    @DbgOutS <" total4k=">,1
    @DbgOutD [dwTotalMem4K],1
    @DbgOutS <" XMS-4k=">,1
    @DbgOutD edx,1
    @DbgOutS <10>,1
endif
    pop edx
    pop ecx
    pop esi
    ret
    align 4

Pool_GetFree16KPages ENDP


; locate any adjacent free XMS block to current pool allocation block
; if found, try consuming 32K of it for pool allocation block
; the adjacent XMS block must be at the end of current pool block,
; since the pool block base cannot be changed once set
; pool block base+block size == owner XMS handle base+handle size (end match end)
; ends must match since you can't span noncontiguous sub-blocks of an owner XMS
; block with a single EMS/VCPI pool allocation block
; INP: ESI -> Pool block to expand (and is ensured to be expandable)
; OUT: NC if success, C if fail
; all registers preserved

Pool_ExpandBlock PROC

    pushad

if ?POOLDBG
    @DbgOutS <"Pool_ExpandBlock: esi=">,1
    @DbgOutD esi,1
    @DbgOutS <", addrK=">
    @DbgOutD [esi].POOL_SYSTEM_INFO.psi_addressK
    @DbgOutS <", pArray=">
    @DbgOutD [esi].POOL_SYSTEM_INFO.psi_descptr
    @DbgOutS <10>,1
endif


    mov edi,[esi].POOL_SYSTEM_INFO.psi_descptr
if ?EXPANDFIRST
    add edi,[dwRes]
endif
    
    mov ebx,[edi].XMS_HANDLE.xh_baseK
    add ebx,[edi].XMS_HANDLE.xh_sizeK   ; ebx -> end of current pool block owner XMS

; see if owner XMS for pool allocation block end matches
;  end of pool allocation block

    movzx ecx,[esi].POOL_SYSTEM_INFO.psi_startadj
    mov eax,[esi].POOL_SYSTEM_INFO.psi_addressK
    sub eax,ecx                 ; true XMS start when pool allocation block created
    mov cl,[esi].POOL_SYSTEM_INFO.psi_endadj
    add eax,ecx                 ; true XMS end when block created
    mov cl,[esi].POOL_SYSTEM_INFO.psi_16kmax
    shl ecx,4                   ; convert to K
    add eax,ecx
    cmp eax,ebx
    jne @@locfail               ; owner XMS end no longer matches initial pool block owner XMS end

    movzx ecx, [XMS_Handle_Table.xht_numhandles]
    mov edx, [XMS_Handle_Table.xht_pArray]

; edx -> test XMS block

    movzx eax, [XMS_Handle_Table.xht_sizeof]
@@hanloop:
    cmp ebx,[edx].XMS_HANDLE.xh_baseK   ; see if test block immediately follows current block   
    je  @@found
    add edx,eax     ; move to next handle descriptor
    dec ecx
    jne @@hanloop
@@locfail:
    popad
    stc             ; flag failure
    ret

@@found:
    test [edx].XMS_HANDLE.xh_flags,XMSF_FREE    ; if block is not free, abort scan
    je  @@locfail
    movzx eax,[esi].POOL_SYSTEM_INFO.psi_endadj
    add eax,[edx].XMS_HANDLE.xh_sizeK
    cmp eax,32                  ; large enough?
    jb @@locfail

; transfer 32K of following block to current block - unused end K in current
    mov eax,32
    movzx ecx,[esi].POOL_SYSTEM_INFO.psi_endadj
    sub eax,ecx                 ; adjust amount to change preceding block
    add [edx].XMS_HANDLE.xh_baseK,eax       ; move changed block address ahead
    sub [edx].XMS_HANDLE.xh_sizeK,eax       ; and adjust size
    mov edi,[esi].POOL_SYSTEM_INFO.psi_descptr
if ?EXPANDFIRST
    add edi,[dwRes]
endif
    add [edi].XMS_HANDLE.xh_sizeK,eax       ; increase pool associated XMS block size
    mov [esi].POOL_SYSTEM_INFO.psi_endadj,0     ; no end overlap

    add [esi].POOL_SYSTEM_INFO.psi_16kmax,2     ; adjust allocation tracking bytes
    add [esi].POOL_SYSTEM_INFO.psi_16kfree,2
    add [esi].POOL_SYSTEM_INFO.psi_4kfree,2*4
    add [dwTotalMem4K],2*4
    
;--- zero tracking allocation byte (not really needed)

if 0
    movzx eax,[esi].POOL_SYSTEM_INFO.psi_16kmax
    shr eax,1                   ; byte offset in allocation space (32K/byte)
    mov BYTE PTR [esi+eax+POOLBLOCK_SYSTEM_SPACE-1],0
endif

; see if changed contiguous XMS block size went to <16K,
;  if so, transfer any remainder to pool block and zero XMS block

    mov eax,[edx].XMS_HANDLE.xh_sizeK
    cmp eax,MINXMSSIZE
    jae @@loc2
    mov [esi].POOL_SYSTEM_INFO.psi_endadj,al

    xor eax,eax
    mov [edx].XMS_HANDLE.xh_baseK,eax           ;required for FD Himem
    mov [edx].XMS_HANDLE.xh_sizeK,eax
;   mov [edx].XMS_HANDLE.xh_locks,al
    mov [edx].XMS_HANDLE.xh_flags,XMSF_INPOOL   ; flag: free handle!
@@loc2:
    popad
    clc                 ; flag success
    ret
    align 4

Pool_ExpandBlock ENDP

; expand any available allocation pool block by minimum amount, if possible
; return NC on success, then ESI=block which has been expanded
; return C on failure
; other registers preserved
; called by VCPI, do not write segment registers here!

Pool_ExpandAnyBlock PROC

    cmp [bNoPool],0 ; dynamic memory allocation on?
    jne @@fail
    mov esi, [PoolAllocationTable]

@@findblkloop:
    cmp [esi].POOL_SYSTEM_INFO.psi_addressK,0   ; unused/deallocated block?
    je  @@nextblock
    cmp [esi].POOL_SYSTEM_INFO.psi_16kmax,2*POOLBLOCK_ALLOCATION_SPACE - 1  ;32k still free?
    jae @@nextblock             ; current block is full
    test [esi].POOL_SYSTEM_INFO.psi_flags,PBF_DONTEXPAND
    jne @@nextblock             ; can't expand this block
    call Pool_ExpandBlock
    jnc @@done
@@nextblock:
    add esi,POOLBLOCK_TOTAL_SPACE
    cmp esi, [PoolAllocationEnd]
    jb @@findblkloop
@@fail:
    stc     ; failure
@@done:
    ret
    align 4

Pool_ExpandAnyBlock ENDP

; find and allocate free 4K (VCPI) block in pool blocks
; return NC and EAX == physical address
;         C if none found
; modifies ECX, ESI, EDI
; do not write segment registers here! this function is
; called by VCPI protected-mode API

Pool_Allocate4KPage PROC public

; first try last block allocated, to avoid searching full blocks if possible

    xor eax,eax
    mov esi, [LastBlockAllocated]
    or esi,esi
    je @@nolastalloc
    cmp [esi].POOL_SYSTEM_INFO.psi_4kfree,ax
    jne @@searchbytes

; try last freed chunk

@@nolastalloc:
    mov esi, [LastBlockFreed]
    or esi,esi
    je @@nolastfreed
    cmp [esi].POOL_SYSTEM_INFO.psi_4kfree,ax
    jne @@searchbytes

@@nolastfreed:
    mov esi, [PoolAllocationTable]
@@findblkloop:
    cmp [esi].POOL_SYSTEM_INFO.psi_4kfree,ax
    jne @@searchbytes
@@nextblock:
    add esi,POOLBLOCK_TOTAL_SPACE
    cmp esi, [PoolAllocationEnd]
    jb  @@findblkloop
    call Pool_ExpandAnyBlock    ; try to expand a pool block 
    jnc @@searchbytes           ; if NC, ESI -> expanded block
    call Pool_AllocateEMBForPool
    jnc @@nolastfreed
    ret

@@searchbytes:
    movzx ecx,[esi].POOL_SYSTEM_INFO.psi_16kmax
    shr ecx,1                   ; count of allocation bytes in block
    adc ecx,0                   ; don't forget the last nibble

    lea edi,[esi+POOLBLOCK_SYSTEM_SPACE]
    mov al,-1
    repz scasb
    jz @@blockbad           ; jump should never happen
    dec edi
    mov al,[edi]
    mov cl,al
    xor al,-1
    bsf eax,eax             ; find the first '1' bit scanning from right to left
    bts dword ptr [edi],eax ; flag page as 'used'
    cmp eax,4
    jc @@islownyb
    shr cl,4
@@islownyb:
    and cl,0Fh
    setz cl                 ; cl will be 1 if low/high nibble became <> 0
    sub [esi].POOL_SYSTEM_INFO.psi_16kfree, cl
if ?POOLDBG    
    jnc @@blockok
    @DbgOutS <"Pool_Allocate4kPage: 16k-free count underflow for block ">,1
    @DbgOutD esi,1
    @DbgOutS <10>,1
@@blockok:
endif
    dec [esi].POOL_SYSTEM_INFO.psi_4kfree
    mov [LastBlockAllocated],esi    ; update "last block allocated from"

    inc [dwUsedMem4K]

    sub edi,esi
    sub edi,POOLBLOCK_SYSTEM_SPACE  ; get "byte offset" into EDI
    shl edi,15      ; each byte covers 32K
    shl eax,12      ; each bit covers 1000h
    add eax,edi     ; compute base address of block addressed by byte
    mov ecx,[esi].POOL_SYSTEM_INFO.psi_addressK
    shl ecx,10      ; convert from K to bytes
    add eax,ecx
if ?POOLDBG
    @DbgOutS <"Pool_Allocate4kPage ok, page=">,1
    @DbgOutD eax,1
    @DbgOutS <", block=">,1
    @DbgOutD esi,1
    @DbgOutS <10>,1
endif
    ret

@@blockbad:
if ?POOLDBG
    @DbgOutS <"Pool_Allocate4kPage: found inconsistent block ">,1
    @DbgOutD esi,1
    @DbgOutS <10>,1
endif
    @CheckBlockIntegrity; nothing free, although block indicated there was
    jmp @@nextblock     ; continue search
    align 4

Pool_Allocate4KPage ENDP

; allocate a 16K page (for EMS)
; out: NC if ok,
;     eax == index for descriptor entry
;     edx == nibble offset in descriptor
;      C on errors
; destroy no other registers

Pool_Allocate16KPage PROC public
    push ecx
    push esi
    push edi

; first try last block allocated, to avoid searching full blocks if possible

    xor edx,edx
    mov esi, [LastBlockAllocated]
    or esi,esi
    je @@nolastalloc
    cmp [esi].POOL_SYSTEM_INFO.psi_16kfree,dl
    jne @@searchbytes

; try last freed chunk
@@nolastalloc:
    mov esi, [LastBlockFreed]
    or esi,esi
    je @@nolastfreed
    cmp [esi].POOL_SYSTEM_INFO.psi_16kfree,dl
    jne @@searchbytes

@@nolastfreed:
    mov esi, [PoolAllocationTable]

@@findblkloop:
    cmp [esi].POOL_SYSTEM_INFO.psi_16kfree,dl
    jne @@searchbytes
@@nextblock:    
    add esi,POOLBLOCK_TOTAL_SPACE
    cmp esi, [PoolAllocationEnd]
    jb @@findblkloop
    call Pool_ExpandAnyBlock    ; expand a block
    jnc @@searchbytes           ; if NC, esi -> expanded block
    call Pool_AllocateEMBForPool
    jnc @@nolastfreed
    jmp @@exit                  ; error: no 16k page free anymore

@@searchbytes:
    movzx ecx,[esi].POOL_SYSTEM_INFO.psi_16kmax
    shr ecx,1           ; count of allocation bytes in block
    adc ecx,0

    xor edi,edi

@@findbyteloop:
    mov al,[esi+edi+POOLBLOCK_SYSTEM_SPACE]
    xor al,-1           ; unallocated 4K areas show as bit set
    mov ah,al
    mov dl,0fh
    and al,dl
    cmp al,dl
    je  @@lowfree       ; low nybble unallocated, free 16K area
    mov dl,0f0h
    and ah,dl
    cmp ah,dl
    je  @@highfree      ; high nybble unallocated, free 16K area
    inc edi
    loop @@findbyteloop

; no free 16K area? should not happen.

    @CheckBlockIntegrity
    jmp @@nextblock

@@highfree:
    stc
@@lowfree:
    setc cl
    or [esi+edi+POOLBLOCK_SYSTEM_SPACE],dl

    dec [esi].POOL_SYSTEM_INFO.psi_16kfree
    sub [esi].POOL_SYSTEM_INFO.psi_4kfree,4
    jnc @@valid2

    @CheckBlockIntegrity    ; force valid value

    mov [esi].POOL_SYSTEM_INFO.psi_4kfree,0    

; update ebx pointer

@@valid2:

    add [dwUsedMem4K],4             ; update pool page counter

    mov [LastBlockAllocated],esi    ; update last block allocated from
    mov eax,esi
    sub eax, [PoolAllocationTable]
    shr eax, 6                      ; convert to an index
    mov edx,edi
    shl edx,1
    or dl,cl                        ; subindex in dl, also clears Carry
@@exit:
    pop edi
    pop esi
    pop ecx
    ret
    align 4

Pool_Allocate16KPage    ENDP

;--- find pool descriptor for 4k page in EDI
;--- EDI is 1K address
;--- returns PD in ESI and EAX=block base
;--- destroy eax,ecx,esi

Pool_FindBlock proc

    mov esi, [LastBlockFreed]

    or esi,esi
    je @@notlastfreed
    mov eax,[esi].POOL_SYSTEM_INFO.psi_addressK
    or eax,eax
    je @@notlastfreed  ; unused/deallocated block

    cmp edi,eax
    jb @@notlastfreed  ; pool block starts after page
    movzx ecx,[esi].POOL_SYSTEM_INFO.psi_16kmax
    shl ecx,4           ; convert 16K to 1K
    add ecx,eax         ; ecx == end of block
    cmp edi,ecx
    jb @@rightblock    ; block found?

@@notlastfreed:
    mov esi, [LastBlockAllocated]
    or esi,esi
    je @@notlastalloc
    mov eax,[esi].POOL_SYSTEM_INFO.psi_addressK
    or eax,eax
    je @@notlastalloc  ; unused/deallocated block

    cmp edi,eax
    jb @@notlastalloc  ; pool block starts after page
    movzx ecx,[esi].POOL_SYSTEM_INFO.psi_16kmax
    shl ecx,4           ; convert 16K to 1K
    add ecx,eax         ; ecx == end of block
    cmp edi,ecx
    jb @@rightblock    ; block found?

@@notlastalloc:
    mov esi, [PoolAllocationTable]

@@findblkloop:
    mov eax,[esi].POOL_SYSTEM_INFO.psi_addressK
    or eax,eax
    je @@nextblock     ; unused/deallocated block

    cmp edi,eax
    jb @@nextblock     ; pool block starts after page
    movzx ecx,[esi].POOL_SYSTEM_INFO.psi_16kmax
    shl ecx,4           ; convert 16K to 1K
    add ecx,eax         ; ecx == end of block
    cmp edi,ecx
    jb @@rightblock    ; block found?

@@nextblock:
    add esi,POOLBLOCK_TOTAL_SPACE
    cmp esi, [PoolAllocationEnd]
    jb @@findblkloop
if ?POOLDBG    
    @DbgOutS <"Pool_FindBlock: page ">,1
    @DbgOutD edx,1
    @DbgOutS <" not in pool",10>,1
endif
    stc
    ret
@@rightblock:
    clc
    ret
    align 4
Pool_FindBlock endp

; upon entry edx = 4K page physical address to free
; return carry clear on success, set on fail
; destroy eax,ecx,esi,edi

Pool_Free4KPage PROC public

    mov edi,edx
    shr edi,10          ; convert bytes to K
    and edi,NOT 3       ; ensure 4K alignment

; edi == start of 4K page in K after alignment adjustment

    call Pool_FindBlock ; find descriptor 
    jc @@fail1          ; error "page not in pool"

; the pool allocation block is in ESI

    sub edi,eax         ; 4K offset from block base in K
    mov eax,edi
    shr eax,2           ; K to 4K page
    mov cl,al           ; keep bit offset
    shr eax,3           ; 4K page to 32K byte offset
    and ecx,7

    btr dword ptr [esi+eax+POOLBLOCK_SYSTEM_SPACE],ecx  ; see if bit set (was allocated)
    jnc @@fail2         ; no

    inc [esi].POOL_SYSTEM_INFO.psi_4kfree
    mov [LastBlockFreed],esi
    
    dec [dwUsedMem4K]

; check if this frees up a 16K chunk

    mov al,[esi+eax+POOLBLOCK_SYSTEM_SPACE]
    cmp cl,4
    jc @@islow
    shr al,4
@@islow:
    test al,0Fh         ; see if all bits of nybble cleared
    jne @@success       ; no
    inc [esi].POOL_SYSTEM_INFO.psi_16kfree
    call Pool_TryFreeToXMS  ; free empty pool allocation block to XMS if appropriate
@@success:

if ?POOLDBG
    @DbgOutS <"Pool_Free4kPage ok, page=">,1
    @DbgOutD edx,1
    @DbgOutS <" block=">,1
    @DbgOutD esi,1
    @DbgOutS <10>,1
endif
    clc
@@fail1:
    ret
@@fail2:
if ?POOLDBG
    @DbgOutS <"Pool_Free4kPage: page ">,1
    @DbgOutD edx,1
    @DbgOutS <" was not allocated (block=">,1
    @DbgOutD esi,1
    @DbgOutS <")",10>,1
endif
    stc
    ret
    align 4

Pool_Free4KPage ENDP


; inp: eax = descriptor index, ecx = nibble offset
; destroys eax, ecx

Pool_Free16KPage PROC public

    push esi

    mov esi,eax
    shl esi,6                       ; convert 64-byte count to byte offset
    add esi, [PoolAllocationTable]  ; esi -> pool allocation block

    mov ah,0Fh
    shr ecx,1           ; byte offset
    jnc @@islow
    mov ah,0F0h
@@islow:
    mov al,[esi+ecx+POOLBLOCK_SYSTEM_SPACE]
    and al,ah           ; mask out bits which dont interest
    cmp al,ah
    jne @@fail2
    rol al,4
    and [esi+ecx+POOLBLOCK_SYSTEM_SPACE],al ; reset all expected bits

    inc [esi].POOL_SYSTEM_INFO.psi_16kfree
    add [esi].POOL_SYSTEM_INFO.psi_4kfree,4

    sub [dwUsedMem4K],4     ; update pool page counter 

    mov [LastBlockFreed],esi
    call Pool_TryFreeToXMS  ; free empty pool allocation block to XMS if appropriate
    clc
@@ret:
    pop esi
    ret

@@fail1:
if ?POOLDBG
    @DbgOutS <"Pool_Free16kPage failed edx=">,1
    @DbgOutD edx,1
    sub edx, [EMSPageAllocationStart]
    shr edx, 2
    @DbgOutS <" EMS page=">,1
    @DbgOutD edx,1
    @DbgOutS <10>,1
    jmp @@fail
endif
@@fail2:
if ?POOLDBG
    @DbgOutS <"Pool_Free16kPage failed page=">,1
    @DbgOutD edx,1
    @DbgOutS <", masks=">,1
    @DbgOutD eax,1
    @DbgOutS <10>,1
endif
@@fail:
    @CheckBlockIntegrity
    stc
    jmp @@ret

Pool_Free16KPage ENDP


; find an unused Pool block
; return NC and edx -> Pool block
; or C if none and no space available
; no other registers modified

Pool_GetUnusedBlock PROC

    mov edx, [PoolAllocationTable]
@@findblkloop:
    cmp [edx].POOL_SYSTEM_INFO.psi_addressK,0   ; unused/deallocated block?
    je @@found
    add edx,POOLBLOCK_TOTAL_SPACE
    cmp edx, [PoolAllocationMax]
    jb @@findblkloop
if ?POOLDBG
    @DbgOutS <"Pool_GetUnusedBlock failed, table start/end=">,1
    @DbgOutD [PoolAllocationTable],1
    @DbgOutS <"/">,1
    @DbgOutD [PoolAllocationMax],1
    @DbgOutS <10>,1
endif
    stc
@@found:
    ret

Pool_GetUnusedBlock ENDP

; prepare pool block for use
; upon entry:
;  edx -> pool allocation block
;  ecx == raw size in K before alignment (max 1536+3)
;  edi == raw address in K before alignment
;  esi == owner XMS handle psi_descptr value, do NOT use XMS handle values for
;   size and address since this call may be part of a multi-pool block span
;  returns memory in 1kB assigned to this descriptor in EAX

Pool_PrepareBlock PROC

    pushad

if ?POOLDBG
    @DbgOutS <"Pool_PrepareBlock: size in kB=">,1
    @DbgOutD ecx,1
    @DbgOutS <" addr in kB=">,1
    @DbgOutD edi,1
    @DbgOutS <10>,1
endif

    mov [edx].POOL_SYSTEM_INFO.psi_descptr,esi

    mov ebx,edi         ; raw address - must be aligned to page boundary
    add ebx,3
    and ebx,not 3
    mov [edx].POOL_SYSTEM_INFO.psi_addressK, ebx
    sub ebx, edi        ; 00->00, 01->03, 02->02, 03->01
    mov [edx].POOL_SYSTEM_INFO.psi_startadj,bl
    mov [edx].POOL_SYSTEM_INFO.psi_endadj,0

; zero allocation entries
    xor eax,eax
    lea edi,[edx+POOLBLOCK_SYSTEM_SPACE]
    push ecx
    mov ecx,POOLBLOCK_ALLOCATION_SPACE/4
    rep stosd
    pop ecx
    cmp edi,[PoolAllocationEnd]
    jb @@notlast
    mov [PoolAllocationEnd],edi
@@notlast:

; block size = (raw size - start adjustment) rounded down to 16K boundary

    mov eax,ecx         ; raw size
    sub eax,ebx
    shr eax,4           ; 16K count, known 16-bit value going to 8-bit

    cmp ax,POOLBLOCK_ALLOCATION_SPACE*2
    jbe @@setmax
    mov ax,POOLBLOCK_ALLOCATION_SPACE*2

@@setmax:
    mov [edx].POOL_SYSTEM_INFO.psi_16kmax,al
    mov [edx].POOL_SYSTEM_INFO.psi_16kfree,al
    test al,1
    jz @@is32kaligned   ;is 16kb page count "uneven"?
    movzx ebx, al
    shr ebx, 1
    mov byte ptr [edx+ebx+POOLBLOCK_SYSTEM_SPACE],0F0h  ;mark last page "used"
@@is32kaligned:    
    shl eax,2           ; 8-bit value potentially going to 16-bit
    mov [edx].POOL_SYSTEM_INFO.psi_4kfree,ax

    add [dwTotalMem4K],eax

; return true memory assigned - (block size + start adjustment)

    shl eax,2           ; convert mem size to 1K
    movzx ebx,[edx].POOL_SYSTEM_INFO.psi_startadj
    add eax,ebx
    mov [esp].PUSHADS.rEAX, eax
    popad
    ret
    align 4

Pool_PrepareBlock ENDP

if ?FREEXMS

Pool_FreeAllBlocks proc public

    pushad
    mov esi, [PoolAllocationTable]  ; esi -> pool allocation block
@@nextitem:
    cmp [esi].POOL_SYSTEM_INFO.psi_addressK,0
    jz @@skipitem
    movzx eax, [esi].POOL_SYSTEM_INFO.psi_16kmax
    mov [esi].POOL_SYSTEM_INFO.psi_16kfree,al
    shl eax, 2
    mov [esi].POOL_SYSTEM_INFO.psi_4kfree,ax
    call Pool_TryFreeToXMS
@@skipitem:    
    add esi,POOLBLOCK_TOTAL_SPACE
    cmp esi, [PoolAllocationEnd]
    jb @@nextitem
    popad
    ret
    align 4
    
Pool_FreeAllBlocks endp

endif

; upon entry esi -> pool allocation block to check if freeable to XMS
; perform the free if possible
; destroys eax,ecx
; if a pool descriptor is freed, it gets fields psi_addressK,
; psi_4kfree, psi_16kfree and psi_16kmax set to 0.

Pool_TryFreeToXMS PROC

    test [esi].POOL_SYSTEM_INFO.psi_flags,PBF_DONTFREE
    jne @@exit          ; never free these blocks

    mov al,[esi].POOL_SYSTEM_INFO.psi_16kfree
    cmp al,[esi].POOL_SYSTEM_INFO.psi_16kmax
    ja @@bad           ; free more than max, try to fix
    jne @@exit          ; free is less than maximum, used

    movzx eax,[esi].POOL_SYSTEM_INFO.psi_4kfree
    shr eax,2
    or ah,ah
    jne @@bad
    cmp al,[esi].POOL_SYSTEM_INFO.psi_16kmax
    ja @@bad
    jne @@exit          ; free less than max

; ok, this pool block is not used anymore.
; now scan all pool blocks and check those linked to the same XMS handle
; if they are free too. If yes, then mark XMS handle as free and clear all
; blocks.

    push esi
    mov esi,[esi].POOL_SYSTEM_INFO.psi_descptr
    mov eax,[PoolAllocationTable]

@@checkblkloop:
    cmp [eax].POOL_SYSTEM_INFO.psi_addressK,0
    je @@checknext         ; unused block

    cmp esi,[eax].POOL_SYSTEM_INFO.psi_descptr
    jne @@checknext

    test [eax].POOL_SYSTEM_INFO.psi_flags,PBF_DONTFREE
    jne @@checkdone     ; can't free this block

; see if block empty
    movzx ecx,[eax].POOL_SYSTEM_INFO.psi_16kmax
    cmp cl,[eax].POOL_SYSTEM_INFO.psi_16kfree
    jne @@checkdone

    shl ecx,2               ; convert to 4K max
    cmp cx,[eax].POOL_SYSTEM_INFO.psi_4kfree
    jne @@checkdone

@@checknext:
    add eax, POOLBLOCK_TOTAL_SPACE
    cmp eax, [PoolAllocationEnd]
    jb @@checkblkloop

; checked all blocks as empty, go through them again and mark unused.
; also update the PoolAllocationEnd variable if needed.

    push edx
    push edi
    mov edi, [PoolAllocationTable]
    mov ecx, edi

    xor eax, eax

@@freeblkloop:
    cmp [edi].POOL_SYSTEM_INFO.psi_addressK,0
    je @@freenext          ; unused block
    cmp esi,[edi].POOL_SYSTEM_INFO.psi_descptr
    je @@freenext2
    mov ecx, edi            ; remember last block not free
    jmp @@freenext
@@freenext2:

; mark the block as free

    movzx edx, [edi].POOL_SYSTEM_INFO.psi_16kmax 
    shl edx, 2
    mov [edi].POOL_SYSTEM_INFO.psi_addressK, eax
    sub [dwTotalMem4K], edx
    mov dword ptr [edi].POOL_SYSTEM_INFO.psi_4kfree, eax    ;this also clears the 16kb counters

@@freenext:
    add edi,POOLBLOCK_TOTAL_SPACE
    cmp edi, [PoolAllocationEnd]
    jb @@freeblkloop

    add ecx,POOLBLOCK_TOTAL_SPACE
    mov [PoolAllocationEnd], ecx

    pop edi
    pop edx

if ?EXPANDFIRST
    add esi, [dwRes]
endif
    call Pool_FreeEMB

@@checkdone:
    pop esi
@@exit:
    ret

@@bad:
    @CheckBlockIntegrity
    stc
    ret
    align 4

Pool_TryFreeToXMS ENDP

; populate empty pool blocks with XMS owner info
; inp:
;  esi -> XMS (pseudo-)handle
;  ecx == size in kB XMS block 
;  edi == physical address (in K, shifted 10 to right!)
;  al == flags
; NOTE: ecx and edi may not match owner XMS size/address
; out: NC success, edi=physical address after alloc
;       C if insufficient number of empty blocks to cover XMS handle range
; destroys eax,ebx,edx,edi

Pool_AllocBlocksForEMB  PROC public

    mov ebx,ecx
if ?EXPANDFIRST
    sub esi,[dwRes]
endif
@@allocloop:
    call Pool_GetUnusedBlock
    jc @@exit      ; no more blocks, remainder of XMS is effectively discarded

    mov [edx].POOL_SYSTEM_INFO.psi_flags,al

    push eax
    mov eax,edi     ; compute size of candidate block/offset to new
    add eax,3
    and al,not 3
    sub eax,edi
    add eax,POOLBLOCK_MEMSIZE   ; 1.5M (in K) plus alignment adjustment size
    cmp eax,ebx
    jbe @@sizeok
    mov eax,ebx
@@sizeok:
    mov ecx,eax
    call Pool_PrepareBlock  ; uses esi entry condition
    add edi,eax         ; update pool allocation block address
    sub ebx,eax         ; update size left to allocate
    pop eax
    cmp ebx,MINXMSSIZE  ; see if should remainder what's left
    jnb @@allocloop
    test al,PBF_DONTEXPAND
    jnz @@exit
    mov [edx].POOL_SYSTEM_INFO.psi_endadj,bl
@@exit:
    ret
    align 4

Pool_AllocBlocksForEMB  ENDP

;  walk XMS blocks, find largest XMS block x which has 
; max( min(dwMemMax4K-dwMemTotal4K, 1.5M), 32K) >= x >= 32K
; after 4K alignment and allocate it for new pool allocation block.
;  if all XMS blocks >1.5M, then pick smallest and try to put remainder
; into a free handle. If no free handle, allocate sufficient new pool
; descriptors to cover full range. If not enough free pool decriptors
; available, the remaining mem is lost until handle is freed. This could 
; only happen under very bad XMS fragmentation, if at all.

; return carry clear if success, set if fail
; all registers preserved
; called by VCPI protected-mode API, do not write segment registers here!

Pool_AllocateEMBForPool PROC

    pushad

    cmp [bNoPool],0 ; check if pool sharing
    jne @@allocfail

    mov ebp, POOLBLOCK_MEMSIZE  ;1536 kB
    mov eax, [dwMaxMem4K]
    sub eax, [dwTotalMem4K] 
    jbe @@allocfail     ;if max memory already allocated
    shl eax, 2          ;convert to 1K units
    cmp ebp, eax
    jc @@usesmaller
    mov ebp, eax
    cmp ebp, MINXMSSIZE
    jnc @@usesmaller
    mov ebp, MINXMSSIZE
@@usesmaller:           ;ebp = max( min(dwMemMax4K-dwMemTotal4K, 1.5M), 32K)

    call Pool_GetUnusedBlock; free pool descriptor available?
    jc @@allocfail         ; no need to process further

;--- scan XMS handle table

    mov esi, [XMS_Handle_Table.xht_pArray]
    movzx ecx, [XMS_Handle_Table.xht_numhandles]

    xor edx,edx             ; edx -> largest block <= 1.5M or smallest if none <=1.5M

@@hanloop:
    test [esi].XMS_HANDLE.xh_flags, XMSF_FREE   ; free XMS memory block?
    je @@next                      ; no, don't check
    mov ebx,[esi].XMS_HANDLE.xh_baseK
    mov eax,[esi].XMS_HANDLE.xh_sizeK
if ?XMS35COMPAT
	test ebx,0ffc00000h    ; block beyond 4GB?
	jnz @@next
endif
ife ?INTEGRATED    
    and ebx,ebx
    je @@next              ; FD Himem bug, ignore blank or zero-sized handle
    or eax,eax
    je @@next
endif
    and bl,3
    mov bh,4
    sub bh,bl       ;bh=4,3,2,1
    and bh,3        ;bh=3,2,1,0 bl=1,2,3,0
    movzx ebx,bh
    sub eax,ebx     ;eax = page adjusted size in 1kb units
    cmp eax,MINXMSSIZE  ;ignore everything below our limit
    jb @@next

    or edx,edx
    je @@newcandidate      ; auto-match if first xms block available

; eax = test value size, edi = current candidate size, both 4k adjusted

    cmp eax,edi
    je @@next
    ja @@larger

; test XMS block smaller than candidate block
    cmp edi,ebp
    jbe @@next          ; current candidate closer to match size
    jmp @@newcandidate

; test XMS block larger than candidate block
@@larger:
    cmp edi,ebp
    jae @@next          ; current candidate closer to match size
    cmp eax,ebp
    ja @@next          ; test too large
@@newcandidate:
    mov edx, esi        ; new best candidate
    mov edi, eax        ; edi = candidate size in 1 kB units
@@next:
    movzx eax, [XMS_Handle_Table.xht_sizeof]
    add esi,eax         ; move to next handle descriptor
    dec ecx
    jne @@hanloop
    or  edx,edx         ; candidate found?
    jne @@allocok
@@allocfail:
    popad
    stc
    ret

; candidate is ensured to have MINXMSSIZE after 4K alignment adjustment

@@allocok:

if ?POOLDBG
    @DbgOutS <"Pool_AllocateEMBForPool: found XMS block hdl=">,1
    @DbgOutD edx,1
    @DbgOutS <" addr=">,1
    @DbgOutD [edx].XMS_HANDLE.xh_baseK,1
    @DbgOutS <" siz=">,1
    @DbgOutD [edx].XMS_HANDLE.xh_sizeK,1
    @DbgOutS <10>,1
endif

    mov [edx].XMS_HANDLE.xh_flags,XMSF_USED ; flag candidate as used
    mov [edx].XMS_HANDLE.xh_locks,1         ; and locked

    mov esi,ebp                     ; default allocation maximum size
    cmp ebp,POOLBLOCK_MEMSIZE
    jnz @@adjusted

    mov eax, [XMSPoolBlockCount]
    cmp eax,1
    jbe @@trailadj          ; use standard 1.5M size for first two blocks
    dec eax                 ; should never overflow before we hit 4G total allocated
    and al,0fh              ; but ensure that overflow doesn't happen anyway
    mov cl,al               ; shift the block size higher by factor of two
    shl esi,cl

; if esi (=XMSBlockSize) >= max free, then reduce XMSBlockSize

    mov eax,[dwMaxMem4K]
    sub eax,[dwTotalMem4K]
    shl eax,2               ; convert to 1K blocks

@@checksize:
    cmp eax, esi
    jae @@adjusted
    cmp esi,ebp             ; see if esi(=XMSBlockSize) is at minimum default
    jbe @@adjusted          ; yes, can't reduce it any further
    shr esi,1               ; reduce block size by one shift and try again
    jmp @@checksize
@@adjusted:

; allow up to MINXMSSIZE-1 trailing bytes

@@trailadj:
    mov eax, esi
    add eax, MINXMSSIZE-1   ; adjust for possible trail
    cmp edi, eax
    jbe @@setblock          ; no need to split XMS handle allocation

; search for a free XMS handle

    mov edi, [XMS_Handle_Table.xht_pArray]
    movzx ecx, [XMS_Handle_Table.xht_numhandles]
    movzx eax, [XMS_Handle_Table.xht_sizeof]

@@freeloop:
    test [edi].XMS_HANDLE.xh_flags,XMSF_INPOOL
    jnz @@gotfree
ife ?INTEGRATED
    cmp [edi].XMS_HANDLE.xh_flags,XMSF_USED ; some Himems dont set XMSF_INPOOL, so
    je @@nextfree                  ; check FREE items if address/size is NULL
    cmp [edi].XMS_HANDLE.xh_baseK,0
    je @@gotfree
    cmp [edi].XMS_HANDLE.xh_sizeK,0
    je @@gotfree
endif
@@nextfree:
    add edi,eax         ; move to next handle descriptor
    loop @@freeloop

; no free handle found, try to allocate multiple blocks, discarding excess

    jmp @@setblock

@@gotfree:
    mov cl,BYTE PTR [edx].XMS_HANDLE.xh_baseK   ; compute size of candidate block/offset to new
    and cl,3
    mov ch,4
    sub ch,cl
    and ch,3
    movzx ecx,ch

    add ecx, esi                ; maximum size (exceeded) plus alignment adjustment size

; edx -> candidate block being allocated
; edi -> new block receiving remainder
; update candidate XMS block size

    mov eax,[edx].XMS_HANDLE.xh_sizeK       ; keep original size for updating new block
    mov [edx].XMS_HANDLE.xh_sizeK,ecx

; update new XMS block info
    sub eax,ecx                 ; new block size == old block original size - old block new size
    mov [edi].XMS_HANDLE.xh_sizeK,eax
    mov [edi].XMS_HANDLE.xh_flags,XMSF_FREE ; explicitly flag free
    mov [edi].XMS_HANDLE.xh_locks,0
    mov eax,[edx].XMS_HANDLE.xh_baseK
    add eax,ecx
    mov [edi].XMS_HANDLE.xh_baseK,eax   ; new block start == old block start + old block new size

if ?POOLDBG
    @DbgOutS <"Pool_AllocateEMBForPool: free XMS block hdl=">,1
    @DbgOutD edi,1
    @DbgOutS <" addr=">,1
    @DbgOutD [edi].XMS_HANDLE.xh_baseK,1
    @DbgOutS <" siz=">,1
    @DbgOutD [edi].XMS_HANDLE.xh_sizeK,1
    @DbgOutS <10>,1
endif

; edx -> owner XMS handle for new pool allocation block(s)
; may be multiple blocks due to XMSBlockCount shifter

@@setblock:
    mov esi,edx
    mov ecx,[esi].XMS_HANDLE.xh_sizeK
    mov edi,[esi].XMS_HANDLE.xh_baseK
    xor al,al
    call Pool_AllocBlocksForEMB

    inc [XMSPoolBlockCount]
    popad
    clc
    ret
    align 4

Pool_AllocateEMBForPool ENDP

;  count available XMS 4K-aligned 4K pages in 16K chunks
;  return count in edx
;  destroys no other registers
;  do not write segment registers here! function
;  is called by VCPI protected mode API.

Pool_GetFreeXMSPages PROC
    push esi
    push ecx
    xor edx,edx
    cmp [bNoPool], 0    ; XMS memory pool?
    jne @@countdone
    movzx ecx, [XMS_Handle_Table.xht_numhandles]
    mov esi, [XMS_Handle_Table.xht_pArray]

    push eax
    push ebx

@@hanloop:
    test [esi].XMS_HANDLE.xh_flags,XMSF_FREE
    jz @@next
ife ?INTEGRATED
    xor eax,eax
    cmp eax,[esi].XMS_HANDLE.xh_baseK   ; account for FD Himem bug
    je @@next
    cmp eax,[esi].XMS_HANDLE.xh_sizeK
    je @@next
endif
    mov eax,[esi].XMS_HANDLE.xh_baseK
if ?XMS35COMPAT
	test eax,0FFC00000h    ; block beyond 4GB?
	jnz @@next
endif
    mov ebx,eax
    add ebx,3       ; round up
    add eax,[esi].XMS_HANDLE.xh_sizeK
    and al,0fch     ; align to 4K boundary
    and bl,0fch
    sub eax,ebx     ; compute size of block after alignments
    jbe @@next
    cmp eax,MINXMSSIZE  ; ignore free blocks < 16 kB
    jb @@next
    and al,NOT 0fh  ; mask to 16K
    shr eax,2       ; convert 1K to 4K
    add edx,eax     ; update total count

@@next:
    movzx eax, [XMS_Handle_Table.xht_sizeof]
    add esi,eax ; move to next handle descriptor
    dec ecx
    jne @@hanloop

    pop ebx
    pop eax
@@countdone:
    pop ecx
    pop esi
    ret

Pool_GetFreeXMSPages ENDP


; mark an XMS handle as free.
; scan through the XMS handle array
; and try to merge this block with other free blocks
; ESI = handle which just has become free
; preserves all registers

Pool_FreeEMB PROC

    pushad

    mov [esi].XMS_HANDLE.xh_locks,0
    mov [esi].XMS_HANDLE.xh_flags,XMSF_FREE

    dec [XMSPoolBlockCount]

    mov edi, [XMS_Handle_Table.xht_pArray]
    movzx ecx, [XMS_Handle_Table.xht_numhandles]

    mov edx, [esi].XMS_HANDLE.xh_baseK
    add edx, [esi].XMS_HANDLE.xh_sizeK

    movzx eax, [XMS_Handle_Table.xht_sizeof]
@@checkloop:
    cmp [edi].XMS_HANDLE.xh_flags,XMSF_FREE ; see if free
    jne @@checknext                 ; anything else is to ignore
ife ?INTEGRATED
    cmp [edi].XMS_HANDLE.xh_baseK,0         ; FD Himem: free + base 0 is "INPOOL"
    je @@checknext                 ; can't check blank handle
endif
    cmp edi, esi
    je @@checknext
    mov ebx,[edi].XMS_HANDLE.xh_baseK           ; which starts at EBX (end of test block)
    cmp edx,ebx
    jz @@merge1
    add ebx,[edi].XMS_HANDLE.xh_sizeK
    cmp ebx,[esi].XMS_HANDLE.xh_baseK
    jz @@merge2
@@checknext:
    add edi,eax         ; move to next handle descriptor
    loop @@checkloop
@@nodefrag:
    popad
    ret

@@merge2:
    push edi
    xchg esi, edi
    call merge
    pop edi
    jmp @@checknext     ;there might come just another free block to merge
@@merge1:
    push offset @@checknext
merge:
    mov ebx,[edi].XMS_HANDLE.xh_sizeK
    add [esi].XMS_HANDLE.xh_sizeK, ebx
    mov [edi].XMS_HANDLE.xh_flags,XMSF_INPOOL   ; flag handle as free
    xor ebx,ebx
    mov [edi].XMS_HANDLE.xh_locks,bl
    mov [edi].XMS_HANDLE.xh_baseK,ebx
    mov [edi].XMS_HANDLE.xh_sizeK,ebx
    retn

Pool_FreeEMB ENDP

; hook left for debugging, no current actions taken
;; upon entry esi -> pool allocation block to perform integrity check upon
;;  update with valid information if allocation counts mismatch
;; destroy no registers

if ?POOLDBG
CheckBlockIntegrity PROC
    ret
CheckBlockIntegrity ENDP
endif

.text$03 ends

.text$04 segment

; initialize memory pool block descriptors
; each descriptor describes a memory block <= 1.5M (48*8 * 4K)
; and is 16 + 48 = 64 bytes in size.
; required are: ((dwMaxMem4K / 1.5M) + x) * 64 bytes bytes for these items
; x is max number of XMS handles
; in: ESI -> JEMMINIT
; in: EDI -> free memory
; out: EDI -> free memory

Pool_Init1 proc public

    add edi,15          ; align on paragraph
    and edi,not 15

    mov [PoolAllocationTable],edi
    mov [PoolAllocationEnd],edi

    mov eax,[dwMaxMem4K]    ;= 30720 x 4k = 120 MB
    cdq
    mov ecx,POOLBLOCK_MEMSIZE/4     ; since dwMaxMem4k is in 4k units
    div ecx             ; default: 30720/384 = 80
    add eax,2           ; round up, not down (and 1 extra for NoPool)
    cmp [bNoPool],0
    jnz @@isnopool
    movzx ecx,[XMS_Handle_Table.xht_numhandles]
    dec ecx
    add eax, ecx
@@isnopool:    
    shl eax,6-2         ; size of 1 descriptor: 64 bytes or 16 dwords
    mov ecx,eax

    xor eax,eax
    rep stosd

    mov [PoolAllocationMax],edi

if ?INITDBG
    @DbgOutS <"pool start/end=">,1
    @DbgOutD PoolAllocationTable,1
    @DbgOutS <"/">,1
    @DbgOutD PoolAllocationMax,1
    @DbgOutS <10>,1
endif
    ret

Pool_Init1 endp

; Pool Init phase 2
;
; ESI -> JEMMINIT
; EDI -> free memory fix block (physical, page aligned)
; EAX -> size (in 4kb pages) still free in fix block 

; out:
; EDI -> free memory (physical)
; destroys EAX, EBX, ECX, EDX

; first pool allocation block(s) are used to manage remainder of initial XMS
; allocated memory (fixed EMS/VCPI allocations).
; never expand these blocks, the descriptor holds a real XMS handle rather than
; an XMS pseudo-handle/pointer taken from the XMS handle array.

Pool_Init2 proc public

    push esi

    cmp [bNoPool], 0
    je @@setblocks

if ?INITDBG
    @DbgOutS <"pool sharing is off, 4k pages remaining=">,1
    @DbgOutD eax,1
    @DbgOutS <" dwMaxMem4k=">,1
    @DbgOutD dwMaxMem4K,1
    @DbgOutS <10>,1
endif

;-- pool sharing is off, rest of block is used for EMS/VCPI
;-- make sure current values of MaxMem4K and EMSPagesMax
;-- are not too high

    mov ecx,[dwMaxMem4K] 
    sub ecx,[dwTotalMem4K]
    cmp eax, ecx
    jnc @@isnodecrease      ;jump if more pages are available
    sub ecx, eax
    sub [dwMaxMem4K],ecx
    mov ecx, eax            ;dwMaxMem4K has to be adjusted
@@isnodecrease:
    push ecx
    call EMS_CheckMax
    pop eax

@@setblocks:

    mov ecx, eax            ; count of available 4K pages


if ?EXPANDFIRST
    mov al,PBF_DONTFREE
else
    mov al,PBF_DONTEXPAND or PBF_DONTFREE
endif
    movzx esi, [esi].JEMMINIT.XMSControlHandle

;--- al=flags, edi=phys addr, esi=XMS handle, ecx=size in kB

if ?INITDBG
    @DbgOutS <"Pool_init2: addr=">,1
    @DbgOutD edi,1
    @DbgOutS <" size in 4kb pg=">,1
    @DbgOutD ecx,1
    @DbgOutS <10>,1
endif
    shl ecx, 2  ;convert to 1kb units
    shr edi, 10 ;must be a 1k-address
    call Pool_AllocBlocksForEMB
    shl edi, 10 ;convert back to phys. address

if ?INITDBG
    @DbgOutS <"Pool_init2: exit, edi=">,1
    @DbgOutD edi,1
    @DbgOutS <10>,1
endif

    pop esi
    ret

Pool_Init2 ENDP

.text$04 ENDS

    END
