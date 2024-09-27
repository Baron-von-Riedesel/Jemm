
;--- Jemm's VDS implementation
;--- Public Domain
;--- to be assembled with JWasm or Masm v6.1+

    .486
    .model FLAT
    option proc:private
    option dotname

    include jemm.inc        ;common declarations
    include jemm32.inc      ;declarations for Jemm32
    include debug.inc
    include dma.inc
    include vds.inc

;--- publics/externals

    include external.inc

;   assume SS:FLAT,DS:FLAT,ES:FLAT

.text$01 SEGMENT

if ?VDS
OldInt4B    dd 0
endif

if ?DMAPT or ?VDS

    align 4

DMABuffStart    DD  0           ; start of DMA-Buffer (linear address)
DMABuffSize     DD  0           ; max size of the DMA-Buffer in bytes
DMABuffStartPhys DD 0           ; start of DMA-Buffer (physical address)
DMABuffFree     DD ?DMABUFFMAX/32 dup (0)   ; bits for DMA buffer handling
                db 0    ; space for 2 additional bits is needed!
    align 4
endif

.text$01 ends

if ?VDS

.text$03 segment

VDS_Call_Table label dword
    Dd vds_version      ; 02 get version
    Dd vds_lock         ; 03 lock region, ES:DI -> DDS  
    Dd vds_unlock       ; 04 unlock region, ES:DI -> DDS
    Dd vds_scatterlock  ; 05 scatter lock, ES:DI -> EDDS
    Dd vds_scatterunlock; 06 scatter unlock, ES:DI -> EDDS
    Dd vds_reqbuff      ; 07 request DMA buffer, ES:DI -> DDS
    Dd vds_relbuff      ; 08 release DMA buffer, ES:DI -> DDS
    Dd vds_copyinbuff   ; 09 copy into DMA buffer, ES:DI -> DDS
    Dd vds_copyoutbuff  ; 0A copy out of DMA buffer, ES:DI -> DDS
    Dd vds_disabletrans ; 0B disable DMA translation
    Dd vds_enabletrans  ; 0C enable DMA translation
VDS_MAX equ ($ - VDS_Call_Table) / 4
    Dd vds_copyinbuffEx ; used by VDMA, 32bit version of copyinbuff
    Dd vds_copyoutbuffEx; used by VDMA, 32bit version of copyoutbuff

;--- bit vector which vds func needs DDS/EDDS translation (ES:DI -> EDI)

if 0
;------ CBA98765432
bDDS dd 00111111110b
endif

;--- bit vector which vds func needs "offset" translation (BX:CX -> ECX)
if 0
;------ CBA98765432
bCpB dd 00110000000b
endif

;--- VDS API
;--- EBP -> Client_Reg_Struc
;--- DX=flags?

vds_handler proc public

    and byte ptr [ebp].Client_Reg_Struc.Client_EFlags+2, not 1  ;v5.85: clear RF

    mov eax, [EBP].Client_Reg_Struc.Client_EAX
    cmp ah,81h
    jnz @@isnotvds
    movzx ebx,al
    @dprintf ?VDSDBG gt 2,<"VDS entry, al=%X",10>, ebx
    sub ebx,2
    jc @@vds_reserved
    cmp ebx,VDS_MAX
    jnc @@vds_reserved
    call Simulate_Iret   ;get the real "current" client flags!
if 0
    bt bDDS, ebx
    jnc @@nodds
endif
;--- make DDS/EDDS accessible with EDI
    movzx ecx,word ptr [ebp].Client_Reg_Struc.Client_ES 
    movzx edi,di
    shl ecx, 4
    add edi, ecx
@@nodds:
    movzx edx,word ptr [ebp].Client_Reg_Struc.Client_EDX
    call [VDS_Call_Table + ebx*4]
    jc @@failed
    and [ebp].Client_Reg_Struc.Client_EFlags,not 1  ;CF=0
    ret
@@failed:
    mov byte ptr [ebp].Client_Reg_Struc.Client_EAX, al
    or [ebp].Client_Reg_Struc.Client_EFlags,1      ;CF=1
    ret
@@isnotvds:
    mov ecx, [OldInt4B]
    jecxz @@novdsoldcall
    @dprintf ?VDSDBG gt 0,<"unhandled Int 4Bh, jmp to cs:ip=%X",10>, eax
    mov word ptr [ebp].Client_Reg_Struc.Client_EIP, CX
    shr ecx, 16
    mov [ebp].Client_Reg_Struc.Client_CS, ECX
    ret
@@vds_reserved:
    mov byte ptr [ebp].Client_Reg_Struc.Client_EAX, VDSERR_FUNC_NOTSUPP	;v5.85
@@novdsoldcall:    
    call Simulate_Iret
    or  [ebp].Client_Reg_Struc.Client_EFlags,1      ;CF=1
    ret
    align 4

vds_handler endp

if 0
vds_unsup proc
    mov al, VDSERR_FUNC_NOTSUPP ; error "function not supported"
    stc
    ret
vds_unsup endp
endif

;--- int 4b, ax=8102h
;--- DX=flags (hiword of EDX cleared)

vds_version proc
    and edx,edx
    jnz @@fail
    mov word ptr [ebp].Client_Reg_Struc.Client_EAX, 100h    ; major/minor spec version
    mov word ptr [ebp].Client_Reg_Struc.Client_EBX, 1   ; product number
    mov word ptr [ebp].Client_Reg_Struc.Client_ECX, 1   ; product revision
    mov eax, [DMABuffSize]
    mov word ptr [ebp].Client_Reg_Struc.Client_EDI,ax
    shr eax, 16
    mov word ptr [ebp].Client_Reg_Struc.Client_ESI,ax
    mov word ptr [ebp].Client_Reg_Struc.Client_EDX, 0   ; flags
    clc
    ret
@@fail:
    mov al,VDSERR_DXRSVDBITSSET  ;"reserved bit set in dx"
    stc
    ret
    align 4

vds_version endp

;--- int 4b, ax=8107h, request DMA buffer
;--- DX = flags, bit 1: copy data into buffer
;--- EDI -> DDS
;--- modifies ECX, EAX, EBX, DDS.wID, DDS.dwPhys
;--- out: C, al=5/6/16
;---      NC, DDS.dwPhys + DDS.wID set

vds_reqbuff proc

	mov al, VDSERR_DXRSVDBITSSET	; v5.85: check added
	test dx, not VDSF_COPY
	jnz @@fail
    mov [edi].DDS.wID, 0
    mov ecx, [edi].DDS.dwSize
    @dprintf ?VDSDBG gt 1,<"VDS request buff, flgs=%X siz=%X",10>, dx, ecx
    and ecx, ecx
    jz @@ok
    mov al, VDSERR_BUFFTOOSMALL  ; buffer too small for region
    add ecx, 400h-1 ; align to kB
    and cx, 0FC00h
    cmp ecx, [DMABuffSize]
    ja @@fail

;--- scan for a free region in buffer

    mov eax, [DMABuffSize]
    shr eax, 10         ; transform in KB
    inc eax             ; the bit vector is 1-based!
    shr ecx, 10
    inc ecx             ; test for 1 bit more!
@@rescan:    
    mov ebx, ecx
@@nextbit:
    dec eax
    js @@fail6
    bt [DMABuffFree], eax
    jnc @@rescan
    dec ebx
    jnz @@nextbit

    dec ecx     ; now use the real size
    inc eax     ; skip the last bit found

;--- a free region large enough found

    @dprintf ?VDSDBG gt 1,<"VDS free region found at %X",10>, ax

    mov ebx, eax
    mov [edi].DDS.wID, ax
@@marknextbit:
    btr [DMABuffFree], ebx
    inc ebx
    loop @@marknextbit
    dec eax
    shl eax, 10     ;convert to byte
    add eax, [DMABuffStartPhys]
    mov [edi].DDS.dwPhys, eax
    @dprintf ?VDSDBG gt 1,<"VDS req buff, phys=%X",10>, eax
    test dl,VDSF_COPY       ; copy into buffer?
    jz @@ok
    xor ecx, ecx
    jmp vds_copyinbuffEx
@@fail6:    
    @dprintf ?VDSDBG gt 0,<"VDS req buff aborted, eax=%X, ebx=%X",10>, eax, ebx
    mov al, VDSERR_BUFFINUSE; error "buffer currently in use"
@@fail:
    stc
    ret
@@ok:
    clc
    ret
    align 4

vds_reqbuff endp

;--- int 4b, ax=8104h, unlock region
;--- DX=Flags, bit 1: copy data out of buffer
;--- EDI -> DDS
;--- "unlock region" is the same as "release buffer"

vds_unlock proc

    @dprintf ?VDSDBG gt 2,<"VDS unlock flgs=%X addr=%X:%X siz=%X id=%X phys=%X",10>, dx, [edi].DDS.wSeg, [edi].DDS.dwOfs, [edi].DDS.dwSize, [edi].DDS.wID, [edi].DDS.dwPhys

vds_unlock endp ;fall through


;--- int 4b, ax=8108h, release DMA buffer
;--- DX = flags, bit 1: copy data out of buffer
;--- EDI -> DDS (only buffer ID is needed)
;--- modifies EBX, EAX

vds_relbuff proc

	test dx, not VDSF_COPY	;v5.85 check added
	jnz fail10

    movzx ebx, [edi].DDS.wID
    @dprintf ?VDSDBG gt 2,<"VDS release buff, flgs=%X DDS=[siz=%X ID=%X addr=%X",10>, dx, [edi].DDS.dwSize, bx, [edi].DDS.dwPhys
    @dprintf ?VDSDBG gt 2,<"DMA buffer bits:%08X-%08X-%08X-%08X-X",10>,DMABuffFree+0,DMABuffFree+4,DMABuffFree+8,DMABuffFree+12, byte ptr DMABuffFree+16
    and ebx, ebx
    jz @@ok

    mov al, VDSERR_INVAL_BUFFID  ;"invalid buffer id"
    cmp bx, ?DMABUFFMAX
    ja @@error

;--- the bit at position -1 must be "1"
;--- and bit 0 must be "0"
;--- the region ends with a "1" bit

    movzx ebx, bx
    dec ebx
    bt [DMABuffFree], ebx
    jnc @@error
    inc ebx
    bt [DMABuffFree], ebx
    jc @@error

    test dl, VDSF_COPY
    jz @@nextbit
    push ebx
    xor  ecx, ecx
    call vds_copyoutbuffEx
    pop ebx    
    jc @@error

@@nextbit:
    bts [DMABuffFree], ebx
    inc ebx
    jnc @@nextbit
@@ok:
    clc
    ret
@@error:
    stc
    ret
    align 4

vds_relbuff endp

;-- test if a buffer is valid and as large as required
;-- used by copy into/out of DMA buffer
;-- EDI -> DDS
;-- ECX = offset in buffer
;-- returns 
;--  NC and EBX == linear address of src/dst in DMA-buffer
;--  C and error code in AL
;-- modifies EAX, EBX, ECX

testbuffer proc

    movzx ebx, [edi].DDS.wID
    @dprintf ?VDSDBG gt 2,<"VDS testbuff id=%X",10>,bx
    mov al, VDSERR_INVAL_BUFFID ;"invalid buffer ID"
    and ebx, ebx
    jz  @@fail
    cmp bx, ?DMABUFFMAX
    ja  @@fail
    dec ebx
    bt [DMABuffFree], ebx   ;bit at -1 *must* be set
    jnc @@fail
    inc ebx
    bt [DMABuffFree], ebx   ;bit at 0 bit *must* be clear
    jc @@fail
    mov eax, ecx            ;eax == offset in DMA buffer

    mov ecx, [edi].DDS.dwSize
    and ecx, ecx
    jz @@ok

    lea ecx, [ecx+eax+3FFh]
    shr ecx, 10

    push eax
    lea eax, [ebx+ecx]
    cmp eax, ?DMABUFFMAX
    pop eax
    ja @@fail3

    push ebx
@@nextbit:
    bt [DMABuffFree], ebx
    jc @@fail2
    inc ebx
    dec ecx
    jnz @@nextbit
    pop ebx

    dec ebx
    shl ebx, 10
    add ebx, [DMABuffStart]
    add ebx, eax
@@ok:
    @dprintf ?VDSDBG gt 2,<"VDS testbuff ok, buff start (linear)=%X",10>, ebx
    clc
    ret
@@fail2:
    @dprintf ?VDSDBG gt 0,<"VDS testbuff @@fail2, ebx=%X ecx=%X",10>, ebx, ecx
    pop ebx
@@fail3:
    mov al,VDSERR_BNDVIOLATION  ;"copy out of buffer range" - buffer boundary violation
@@fail:
    @dprintf ?VDSDBG gt 0,<"VDS testbuff failed, al=%X",10>, al
    stc
    ret
    align 4

testbuffer endp

;--- int 4b, ax=8109h, copy into DMA buffer
;--- DX = flags, must be 0000
;--- Client->BX:CX = offset in buffer
;--- EDI -> DDS

vds_copyinbuff proc

    cmp dx,0
    jnz fail10
    mov ecx, [ebp].Client_Reg_Struc.Client_EBX
    shl ecx, 16
    mov cx, word ptr [ebp].Client_Reg_Struc.Client_ECX

vds_copyinbuff endp ;fall thru

;--- ECX = DMA buffer offset

vds_copyinbuffEx proc

    call testbuffer		; returns EBX=linear address (inside DMA buffer)
    jc @@exit
    mov ecx, [edi].DDS.dwSize
    movzx eax, [edi].DDS.wSeg
    shl eax, 4
    add eax, [edi].DDS.dwOfs
    @dprintf ?VDSDBG gt 1,<"VDS copyinbuff src=%X dst=%X siz=%X",10>, eax, ebx, ecx
    pushad
    mov esi, eax
    mov edi, ebx
    cld
    call MoveMemory
    popad
    clc
@@exit:    
    ret
    align 4

vds_copyinbuffEx endp

fail10:
	mov al, VDSERR_DXRSVDBITSSET
	stc
	ret

;--- int 4b, ax=810Ah, copy out of DMA buffer
;--- DX = flags, must be 0000
;--- Client->BX:CX = offset in buffer
;--- EDI -> DDS

vds_copyoutbuff proc

    cmp dx,0
    jnz fail10
    mov ecx, [ebp].Client_Reg_Struc.Client_EBX
    shl ecx, 16
    mov cx, word ptr [ebp].Client_Reg_Struc.Client_ECX
    
vds_copyoutbuff endp    ;fall thru

;--- ECX = DMA buffer offset

vds_copyoutbuffEx proc

    call testbuffer
    jc @@exit
    mov ecx, [edi].DDS.dwSize
    movzx eax, [edi].DDS.wSeg
    shl eax, 4
    add eax, [edi].DDS.dwOfs
    pushad
    mov esi, ebx
    mov edi, eax
    cld
    call MoveMemory
    popad
    clc
@@exit:
    ret
    align 4

vds_copyoutbuffEx endp

;--- subroutines for vds_lock

;--- test if a region is contiguous and crosses 64/128 kB borders
;--- eax = start page, ebx = end page, dx=flags
;--- for first 4 MB only
;--- out: NC if ok, C if failed
;---      NC -> EAX = initial physical address
;---      C -> AL = error code, EDX = size that would be ok
;--- error code:
;---  01: region not contiguous
;---  02: region crossed 64kb/128kb boundary
;--- called by vds_lock

vds_contiguous proc

    push esi
    push edi

    @GETPTEPTR esi, ?PAGETAB0, 1    ;get start of page tab 0

    mov ecx, [esi+eax*4]
    and cx, 0F000h
    mov edi, ecx
    push ecx
@@nextitem:    
    cmp eax, ebx
    jz @@iscontiguous
    inc eax
    mov ecx, [esi+eax*4]
    add edi, 1000h
    and cx, 0F000h
    cmp edi, ecx
    je @@nextitem
    pop ecx
    mov edx, edi
    sub edx, ecx
    mov al, VDSERR_NOTCONTIGUOUS
@@failed:
    pop edi
    pop esi
    stc
    ret
@@failed2:          ;failed because 64/128 kb boundary crossing
    mov edx, esi
    shl edx, cl
    sub edx, eax
    mov al, VDSERR_CROSSEDBOUNDS
    jmp @@failed
@@iscontiguous:
    pop eax         ;get start physical address
    test dl,VDSF_64KALIGN or VDSF_128KALIGN ; boundary check?
    jz @@nocheck
    mov edi, eax
    mov esi, ecx
    test dl, VDSF_64KALIGN  ;check for 64 kb border crossing?
    setz cl
    add cl, 16
    shr edi, cl
    shr esi, cl
    cmp edi, esi
    jnz @@failed2
@@nocheck:
    pop edi
    pop esi
    ret
    align 4

vds_contiguous endp

;-- simplified version of vds_contiguous
;-- assumes linear == physical (for regions above 400000h)
;-- eax = linear start address
;-- ebx = size of region in bytes
;-- ret C -> boundary error, AL=error code, EDX==size ok
;-- ret NC -> ok, EAX == physical address [== linear address]
;-- modifies ECX, EBX, EDX, EAX
;-- called by vds_lock

vds_contiguous2 proc

;-- see if boundary alignment check

    test dl,VDSF_64KALIGN or VDSF_128KALIGN ; boundary check?
    jz @@ok
    lea ebx,[eax+ebx-1]
    test dl,VDSF_64KALIGN   ;if 64K works, then 128K will too
    setz cl
    add cl,16       ; shift 16 (64 kB) or 17 (128 kb) positions
    mov edx,eax
    shr ebx,cl      ; convert start/end to alignment 64K frames
    shr edx,cl
    cmp ebx,edx
    je @@ok
    inc edx         ; ecx == starting alignment frame+1
    shl edx,cl      ; convert to next alignment frame address
    sub edx,eax     ; get bytes to next alignment frame address from start
    mov al,2        ; region crossed alignment boundary error code
    stc
@@ok:
    ret
    align 4

vds_contiguous2 endp

;--- int 4b, ax=8103h, lock region
;--- EDI -> DDS
;--- DX=Flags
;--- 0:reserved
;--- 1:1=data should be copied into buffer (if necessary) [requires 2 cleared]
;--- 2:1=buffer disable (no DMA buffer should be allocated if noncontiguous or crosses 64/128 kB)
;--- 3:1=disable automatic remap
;--- 4:1=region must not cross 64 kb border
;--- 5:1=region must not cross 128 kb border

;--- there are several cases:
;--- 1. region is contiguous (and does not cross borders)
;---    out: NC
;---         DDS.wID = 0
;---         DDS.dwPhys = physical addr
;--- 2. region is not contiguous and/or does cross borders
;---    2.1 buffer disable flag set
;---      out: C
;---           DDS.wID = 0
;---           AL = 1/2/3 
;---    2.2 buffer disable flag cleared
;---       2.2.1 buffer available and large enough
;---             alloc buffer
;---             if copy requested then copy data into buffer
;---         out: NC
;---              DDS.wID <> 0
;---              DDS.dwPhys = physical addr of buffer
;---       2.2.2 buffer too small
;---         out: C
;---              DDS.dwSize = size that would be ok
;---              DDS.wID = 0
;---              AL = 5
;---       2.2.3 buffer not available
;---         out: C
;---              DDS.dwSize = ?
;---              DDS.wID = 0
;---              AL = 6
;---
;---     field DDS.dwPhys may be filled by "Lock Region"

vds_lock proc

    mov esi, edx    ;save flags

    @dprintf ?VDSDBG gt 1, <"VDS lock flgs=%X addr=%X:%X siz=%X",10>, dx, [edi].DDS.wSeg, [edi].DDS.dwOfs, [edi].DDS.dwSize

    xor eax, eax
    mov ebx, [edi].DDS.dwSize   ; region size
    cmp ebx, eax
if 0
    je @@locksuccess       ; zero byte-sized region always works
else
    setz al         ;size 0 is always ok, but the physical address must be set
    add ebx, eax    ;as well. So handle size 0 as if it is size 1
endif
    mov ax, [edi].DDS.wSeg
    shl eax,4
    add eax, [edi].DDS.dwOfs
;    jc --> overflow error

    lea ecx, [eax+ebx-1]
    cmp ecx, 400000h; region in first 4 MB ?
    jb @@below4MB

;-- assume linear == physical
;-- call a simplified version of vds_contiguous

    call vds_contiguous2
    jnc @@locksuccess
    jmp @@lenfail

@@below4MB:
    mov ebx, ecx    ; ebx == final linear address
    shr ebx,12      ; convert end to 4K frame
    push eax
    shr eax,12      ; convert start to 4K frame
    call vds_contiguous
    pop ecx
    jc @@notcontiguous
    and ch, 0Fh
    or ax, cx
    jmp @@locksuccess ;save EAX in DDS

; physical memory is noncontiguous, error code is 1 or 2
; return maximum length which would be ok

@@notcontiguous:

    and ecx, 0fffh
    sub edx, ecx
    mov ecx, esi            ; restore flags
    test cl, VDSF_NOBUFFER  ; buffering disabled?
    jnz @@nobuffering
    push edx
    mov edx, esi
    call vds_reqbuff        ; modifies DDS.wID
    pop edx
    jnc @@lockok
@@nobuffering:    

    @dprintf ?VDSDBG gt 0,<"VDS lock failed, ret size=%X rc=%X addr=%X:%X siz=%X flags=%X">, edx, al, [edi].DDS.wSeg, [edi].DDS.dwOfs, [edi].DDS.dwSize, si

@@lenfail:
    mov [edi].DDS.dwSize,edx    ; update maximum contiguous length
    mov [edi].DDS.wID,0         ; zero buffer id?
    stc
    ret

@@locksuccess:
    @dprintf ?VDSDBG gt 1, <"VDS lock ok, ret size=%X phys=%X",10>, [edi].DDS.dwSize, eax
    mov [edi].DDS.dwPhys,eax ; physical address
    mov [edi].DDS.wID,0      ; zero buffer id

@@lockok:
    clc
    ret

    align 4

vds_lock endp

;--- int 4b, ax=8105h
;--- inp: EDI -> EDDS
;---      DX=flags (bits 6 & 7)
;--- out: NC
;---      EDDS.wNumUsed: no of entries used to describe region
;---      regions/PTEs behind EDDS are set
;--- err: C set
;---      AL=error code
;---      dwSize: length that can be locked with current entries
;---      EDDS.wNumUsed: number of entries required to fully describe region!
;--- modifies EAX, EBX, ECX, EDX, ESI

vds_scatterlock proc

    @dprintf ?VDSDBG gt 1, <"VDS scatlock flgs=%X addr=%X:%X siz=%X avl=%X",10>, dx, [edi].EDDS.wSeg, [edi].EDDS.dwOfs, [edi].EDDS.dwSize, [edi].EDDS.wNumAvail

	mov al, VDSERR_DXRSVDBITSSET		; v5.85: check added
	test dx, not (VDSF_PTE or VDSF_NPPTE)
	jz @F
    stc
    ret
@@:
    mov ebx,[edi].EDDS.dwSize
    xor ecx,ecx     ; cx holds entries used
    mov eax,ecx     ; zero eax for later calcs
    mov [edi].EDDS.wNumUsed,cx  ; EDDS number entries used
    and ebx,ebx
    setz al
    add ebx,eax     ; handle size=0 like size=1

    mov ax,[edi].EDDS.wSeg
    shl eax,4
    add eax,[edi].EDDS.dwOfs    ;eax=linear address

;    jc --> overflow error

    test dl,VDSF_PTE    ; PTEs flagged?
    jne @@getptes

    mov edx,eax         ; edx == start linear address
    shr eax,12          ; convert start to 4K frame
    cmp eax,256
    jb @@checklock     ; inside of UMB remapping range (<1M)

; outside of UMB remapping range, assuming linear == physical
    mov [edi].EDDS.wNumUsed,1   ; one region used/needed
    cmp cx,[edi].EDDS.wNumAvail
    jnc @@notenoughregions
    mov [edi+size EDDS].EDDSRG.dwPhysAddr,edx   ; region physical address
    mov [edi+size EDDS].EDDSRG.dwSizeRg,ebx     ; region size
    clc
    ret
@@notenoughregions:
    mov al, VDSERR_NAVL_TOOSMALL   ;error "NumAvail too small"
    stc
    ret

;--- return regions, 1. MB
;--- eax = linear start page (linear address >> 12)

@@checklock:
    push    edx         ; save start linear address

    lea ebx,[ebx+edx-1] ; ebx == final linear address
    shr ebx,12          ; convert to 4K frame
    @GETPTE edx, eax*4+?PAGETAB0
    and dx, 0F000h
    mov esi,edx         ; current physical address of 4K page
    cmp cx,[edi].EDDS.wNumAvail
    jnc @@bumpused
    mov [edi+size EDDS].EDDSRG.dwPhysAddr,edx
    mov [edi+size EDDS].EDDSRG.dwSizeRg,0
    jmp @@bumpused

@@entryloop:
    cmp cx,[edi].EDDS.wNumAvail ; entries available count
    jnc @@bumpused
    mov [edi+ecx*8+size EDDS].EDDSRG.dwSizeRg,1000h ; init region size
    mov [edi+ecx*8+size EDDS].EDDSRG.dwPhysAddr, esi

@@bumpused:
    inc [edi].EDDS.wNumUsed ; bump count of used/needed entries

@@nextframe:
    inc eax             ; next linear page frame
    cmp eax,ebx
    ja @@scatdone      ; no more regions to map
    cmp ah,0            ; page below 100h?
    jz @@next2         ; not at end of first 1M
    cmp ax,256
    ja @@scatdone      ; finishing off final region entry
    cmp esi,0ff000h     ; end of 1M, see if final 4K block was identity mapped
    je @@scatdone      ; yes

; start new region for final
    inc ecx
    mov esi, 100000h
    jmp @@entryloop

@@next2:
    add esi, 1000h
    @GETPTE edx, eax*4+?PAGETAB0
    and dx, 0F000h
    cmp edx, esi
    je @@samereg
    inc ecx             ; have to move to next region/entry
    mov esi,edx         ; update current physical address
    jmp @@entryloop

@@samereg:
    cmp cx,[edi].EDDS.wNumAvail ; entries available count
    jnc @@nextframe
    add [edi+ecx*8+size EDDS].EDDSRG.dwSizeRg,1000h
    jmp @@nextframe

; calculate final region byte size or maximum allowed
@@scatdone:
    pop edx
    cmp [edi].EDDS.wNumAvail,0  ; entries available count
    jz @@noregions
    and edx,0fffh
    add [edi+size EDDS].EDDSRG.dwPhysAddr, edx
    mov ebx,1000h
    sub ebx,edx 
    add [edi+size EDDS].EDDSRG.dwSizeRg,ebx
@@noregions:
    xor ebx,ebx
    mov edx,ebx
    movzx ecx,[edi].EDDS.wNumUsed   ; number regions used (cannot be 0)
    mov al,0  ; no error
    cmp cx, [edi].EDDS.wNumAvail
    jbe @@finalloop
    mov cx,[edi].EDDS.wNumAvail ; only count up to minimum of available/used
    mov al, VDSERR_NAVL_TOOSMALL
if ?VDSDBG
    and ecx, ecx
    jz @@scatfail
else
    jecxz @@scatfail 
endif
@@finalloop:
    mov esi,edx         ; keep previous, last known valid value
    add edx,[edi+ebx*8+size EDDS].EDDSRG.dwSizeRg
    inc ebx
    loop @@finalloop
    cmp al,0
    jne @@scatfail      ; not all regions represented, update EDDS.dwSize

    mov edx,[edi].EDDS.dwSize   ; update final region byte count
    sub edx,esi
    dec ebx
    mov [edi+ebx*8+size EDDS].EDDSRG.dwSizeRg, edx
    @dprintf ?VDSDBG gt 1, <"VDS scatlock exit, rc=0, used=%X, addr=%X, siz=%X",10>, [edi].EDDS.wNumUsed, [edi+size EDDS].EDDSRG.dwPhysAddr, [edi+size EDDS].EDDSRG.dwSizeRg
    clc
    ret
@@scatfail:
    mov [edi].EDDS.dwSize,edx
    @dprintf ?VDSDBG gt 0, <"VDS scatlock exit, rc=%X, siz=%X used=%X",10>, al, [edi].EDDS.dwSize, [edi].EDDS.wNumUsed
    stc
    ret

;--- return PTEs
;--- DL & 40h == 40h
;--- eax == linear address
;--- ebx == size in bytes
;--- ecx == count entries used

@@getptes:
    push eax            ; save linear address

    shr eax,12          ; convert linear start to PTE index
    @GETPTEPTR esi, ?PAGETAB0, 1
@@loop:
    xor edx, edx
    cmp eax, 400h       ; don't cross page table 0 border!
    jnc @@noPTE
    mov edx, [esi+eax*4]
    and dx, 0F001h
@@noPTE:    
    cmp cx, [edi].EDDS.wNumAvail
    jnc @@noPTEupdate
    mov [edi+ecx*4+size EDDS].EDDSPT.dwPTE, edx
@@noPTEupdate:
    inc ecx
    inc eax
    sub ebx, 1000h
    ja @@loop
    mov [edi].EDDS.wNumUsed,cx
    pop eax

    and ah,0Fh
    cmp cx, [edi].EDDS.wNumAvail
    ja @@notenoughregions2
    mov word ptr [ebp].Client_Reg_Struc.Client_EBX, ax
    clc
    ret
@@notenoughregions2:
    movzx ecx, [edi].EDDS.wNumAvail
    shl ecx, 12
    movzx eax,ax
    sub ecx, eax
    mov [edi].EDDS.dwSize, ecx
    mov al, VDSERR_NAVL_TOOSMALL ;error "NumAvail too small"
    stc
    ret

vds_scatterlock endp

;--- int 4b, ax=8106h
;--- DX=flags (6 & 7 may be set)
;--- ES:DI=EDDS
;--- errors VDSERR_REG_NOTLOCKED and VDSERR_DXRSVDBITSSET may happen!

vds_scatterunlock proc
	mov al, VDSERR_DXRSVDBITSSET		; v5.85: check added
	test dx, not (VDSF_PTE or VDSF_NPPTE)
	jnz @@fail
	;--- todo: check if region was locked
    clc
    ret
@@fail:
	stc
	ret
vds_scatterunlock endp

;--- int 4b, ax=810B: disable automatic translation for a DMA channel
;--- Client->BX=DMA channel number
;--- DX=flags (all reserved and must be 0, hiword EDX is cleared)

vds_disabletrans proc

    mov ebx, [EBP].Client_Reg_Struc.Client_EBX
    @dprintf ?VDSDBG gt 1, <"VDS disable translation for channel %X",10>, bx
    cmp bx, MAXDMACHANNEL
    mov al, VDSERR_INVAL_DMACHN  ;error "invalid channel"
    jnc @@fail
    mov al, VDSERR_DXRSVDBITSSET ;error "reserved flags set in DX"
    and edx, edx
    jnz @@fail
if ?DMAPT
    mov al, VDSERR_DISCNTOVFL    ;error "disable count overflow"
    movzx ebx, bx
    cmp [DmaChn+ebx*sizeof DMAREQ].cDisable,255
    jz @@fail
    inc [DmaChn+ebx*sizeof DMAREQ].cDisable
endif
    clc
    ret
@@fail:
    stc
    ret

vds_disabletrans endp

;--- int 4b, ax=810C: enable automatic translation for a DMA channel
;--- Client->BX=DMA channel number
;--- DX=flags (all reserved and must be 0, hiword EDX cleared)
;--- out: Z if disablecnt is now zero

vds_enabletrans proc

    mov ebx, [EBP].Client_Reg_Struc.Client_EBX
    @dprintf ?VDSDBG gt 1, <"VDS enable translation for channel %X",10>, bx
    cmp bx, MAXDMACHANNEL
    mov al, VDSERR_INVAL_DMACHN  ;error "invalid channel"
    jnc @@fail
    mov al, VDSERR_DXRSVDBITSSET ;error "reserved flags set in DX"
    and edx, edx
    jnz @@fail
if ?DMAPT
    mov al, VDSERR_DISCNTUNFL    ;error "disable count underflow"
    movzx ebx, bx
    cmp [DmaChn+ebx*sizeof DMAREQ].cDisable,0
    jz @@fail
    dec [DmaChn+ebx*sizeof DMAREQ].cDisable
;--- v5.85: set ZF
    setz al
    shl al, 6   ; position of ZF in flags
    and byte ptr [ebp].Client_Reg_Struc.Client_EFlags,not 40h  ;ZF=0
    or  byte ptr [ebp].Client_Reg_Struc.Client_EFlags,al
endif
    clc
    ret
@@fail:
    stc
    ret

vds_enabletrans endp

VDS_Exit proc public
    mov eax, [OldInt4B]
    mov ds:[4Bh*4],eax
    and byte ptr ds:[47Bh],not 20h
    ret
VDS_Exit endp

.text$03 ends

.text$04 segment

;--- esi ->JEMMINIT

VDS_Init proc public
    mov eax, ds:[4Bh*4] ;vector may be 0000:0000
    mov [OldInt4B],eax
    cmp [esi].JEMMINIT.NoVDS, 0
    jnz @@novds
    mov eax, [dwRSeg]
    shl eax, 16
    mov al, [bBpTab]
if BPTABLE.pInt4B
    add al, (BPTABLE.pInt4B shr 2)
endif
    mov ds:[4Bh*4], eax
    or byte ptr ds:[47Bh],20h
@@novds:
    ret
VDS_Init endp

.text$04 ENDS

endif   ;?VDS

    END
