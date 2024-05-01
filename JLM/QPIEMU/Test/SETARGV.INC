
;--- read the commandline at PSP:81h
;--- and create an argc/argv structure on the stack.
;--- in: ES=PSP, DS=DGROUP, SS=DGROUP
;--- out: _argc (=[bp-2])
;---      _argv (=[bp-4])
;--- all std registers modified (including SP)

?DUMMYFN equ 1
?QUOTES  equ 1

_setargv proc

    mov bp, sp
    sub sp, 256             ; just make enough room for argc/argv

    xor di, di              ; init argc
    xor dx, dx              ; init size of mem block
    mov si, 81H
    push es
    pop ds
;    assume ds:nothing      ; no need for assumes, since no global vars are accessed
    jmp scanarg

;--- DI = argc
;--- DX = block size (not including null terminators)
nextarg:
    push bx                 ; save argument size
scanarg:
@@:
    lodsb
    cmp al, ' '
    je @B
    cmp al, 9
    je @B
    cmp al, 13
    jz doneargs             ; exit if eol
    inc di                  ; another argument
    xor bx, bx              ; init argument size
if ?QUOTES
    cmp al, '"'
    jz handle_quote
endif
    dec si                  ; back up to reload character
    push si                 ; save argument ofs
@@:
    lodsb
    cmp al, ' '             ; end argument?
    je nextarg
    cmp al, 9
    je nextarg              ; white space terminates argument
    cmp al, 13
    jz doneargs2            ; exit if eol
    inc bx
    inc dx
    jmp @B
if ?QUOTES
handle_quote:
    push si
@@:
    lodsb
    cmp al, 13
    jz quoteerr
    cmp al, '"'
    jz @F
    inc dx
    inc bx
    jmp @B
quoteerr:
    dec si                  ; "unread" the CR
@@:
    jmp nextarg
endif
doneargs2:
    push bx                 ; last argument's size
doneargs:

;--- address & size of arguments are pushed

    mov cx, di
    add dx, di              ; DX=size arguments + terminator bytes
    inc di                  ; add one for NULL pointer
if ?DUMMYFN
    inc di                  ; add one for filename
endif
    shl di, 1               ; each ofs needs 2 bytes
    add dx, di              ; DX=size args + size argv
    and dx, -2              ; ensure stack remains word aligned
    mov ax, [bp]
    sub bp, dx              ; alloc the really needed space for argc/argv
    mov [bp-6], ax          ; store return address

_argc equ <bp-2>
_argv equ <bp-4>

    mov [_argv], bp
    mov [_argc], cx

    add di, bp              ; di -> behind vector table (strings)
    xor ax, ax
    lea bx, [di-2]
    mov ss:[bx], ax         ; terminating 0000 _argv[x]
    sub bx, 2
    jcxz noargs
    push ss
    pop es

;--- copy the arguments from PSP onto the stack

    mov dx, cx
@@:
    pop cx                  ; size
    pop si                  ; address
    mov ss:[bx], di         ; store _argv[x]
    sub bx, 2
    rep movsb
    stosb                   ; AL still 0
    dec dx
    jnz @B

noargs:
    push ss
    pop ds
;    assume ds:DGROUP
if ?DUMMYFN
    mov [bx], ax            ; store 0 as dummy filename
    inc word ptr [_argc]
endif
    lea sp, [bp-6]
    ret
_setargv endp

