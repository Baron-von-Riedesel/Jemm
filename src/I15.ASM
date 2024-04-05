
;--- I15, ah=87 extended memory move 
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

;--- assembly time constants

;--- segment definitions

;--- publics/externals

    include external.inc

;--- start

;   assume SS:FLAT,DS:FLAT,ES:FLAT

;--- expected GDT structure pointed to by ES:SI for int 15h, ah=87

I15MOVE struct
    dq ?
    dq ?
src DESCRIPTOR <?>
dst DESCRIPTOR <?>
I15MOVE ends

.text$01 SEGMENT
.text$01 ends

.text$03 segment

;************************************************************
; simulate INT15/87
;
;INT 15 - SYSTEM - COPY EXTENDED MEMORY (by RBIL)
;        AH = 87h
;        CX = number of words to copy (max 8000h)
;        ES:SI -> GDT (see I15MOVE)
;Return: CF set on error
;        CF clear if successful
;        AH = status 
;
;Values for extended-memory copy status (RBIL):
; 00h    source copied into destination
; 01h    parity error
; 02h    interrupt error
; 03h    address line 20 gating failed
; 80h    invalid command (PC,PCjr)
; 86h    unsupported function (XT,PS30)
;************************************************************

I15_Simulate87 proc public

    call Simulate_Iret
    movzx ecx,word ptr [ebp].Client_Reg_Struc.Client_ECX

    cld

    MOVZX edi,WORD PTR [ebp].Client_Reg_Struc.Client_ES   ; make edi = linear address of command
    MOVZX esi,WORD PTR [ebp].Client_Reg_Struc.Client_ESI
    SHL edi,4
    add esi,edi

;-- MS Emm386 returns with error AH=2 if CX > 8000h!

    cmp cx, 8000h
    ja @@error02
    or ecx,ecx
    je @@ok            ; nothing to do
    shl ecx,1

    mov eax,ecx         ; verify that src and dst descriptors are ok.
    dec eax             ; we don't care about segment access rights
                        
    cmp ax, [esi].I15MOVE.src.wLimit; 16-bit overflow not an issue (0->ffff)
    ja @@error80
    cmp ax, [esi].I15MOVE.dst.wLimit
    ja @@error80

    mov al,[esi].I15MOVE.src.bA1623
    mov ah,[esi].I15MOVE.src.bA2431 ; get linear source address
    mov dl,[esi].I15MOVE.dst.bA1623
    mov dh,[esi].I15MOVE.dst.bA2431 ; get linear destination address
    shl eax,16
    shl edx,16
    mov ax,[esi].I15MOVE.src.wA0015
    mov dx,[esi].I15MOVE.dst.wA0015
    mov esi,eax
    mov edi,edx

;--- here we have: esi=src, edi=dst, ecx=size

    @dprintf ?I15DBG, <"Int 15h, ah=87h, src=%X, dst=%X, siz=%X",10>, esi, edi, ecx

;-- NOCHECK -> moves for addresses not backuped with RAM/ROM will fail
;-- (cause an exception)

    test [bV86Flags], V86F_NOCHECK
    je @@memcheck

    lea eax, [esi+ecx]
    lea edx, [edi+ecx]
    cmp eax, [dwMaxPhysMem]
    jae @@fail
    cmp edx, [dwMaxPhysMem]
    jae @@fail

@@memcheck:
    call MoveMemoryPhys
@@ok:
    mov AH,0    ; everything OK and finished
    and [ebp].Client_Reg_Struc.Client_EFlags, not 1 ;CF=0
@@i1587_exit:
    mov byte ptr [ebp].Client_Reg_Struc.Client_EAX+1, ah
    ret
@@error02:
if ?XMS35COMPAT
    cmp cx,0F00Fh
    jnz @F
    cmp cx,word ptr [ebp].Client_Reg_Struc.Client_EAX+2
    jnz @F
    bt [dwFeatures],17  ;PSE supported?
    jnc @F
    mov cx,word ptr [ebp].Client_Reg_Struc.Client_ECX+2
    shl ecx,1
    mov al,[esi].I15MOVE.src.bA1623
    mov ah,[esi].I15MOVE.src.bA2431 ; get linear source address
    mov dl,[esi].I15MOVE.dst.bA1623
    mov dh,[esi].I15MOVE.dst.bA2431 ; get linear destination address
    shl eax,16
    shl edx,16
    mov ax,[esi].I15MOVE.src.wA0015
    mov dx,[esi].I15MOVE.dst.wA0015
    mov esi,eax
    mov edi,edx
    mov eax,[ebp].Client_Reg_Struc.Client_EDX   ;src bits 32-47
    mov edx,[ebp].Client_Reg_Struc.Client_EBX   ;dst bits 32-47
    @dprintf ?I15DBG, <"Int 15h, ah=87h, src=%X.%X, dst=%X.%X siz=%X",10>, ax, esi, dx, edi, cx
    call MoveMemoryPhysEx
    jmp @@ok
@@:
endif
    mov ah,02h
    or [ebp].Client_Reg_Struc.Client_EFlags, 1 ;CF=1
    jmp @@i1587_exit
@@error80:
    mov ah,80h
    or [ebp].Client_Reg_Struc.Client_EFlags, 1 ;CF=1
    jmp @@i1587_exit
@@fail:
    jmp V86_Exc0D

    align 4

I15_Simulate87 endp

.text$03 ends

    END
