
;--- a simple JLM which displays a message onto the screen
;--- with the help of v86-int 21h and nested execution

        .386
        .MODEL FLAT, stdcall

        include jlm.inc

        .DATA

szText  db "Hello, world!", 13,10,0

        .CODE

_main   proc

        push esi
        @VMMCall Begin_Nest_Exec     ;start nested execution
        mov esi, offset szText
@@nextitem:
        lodsb
        and al,al
        jz @@done

;--- Call int 21h, ah=2 in v86-mode.
;--- Be aware that in Jemm's context is no DOS extender installed.
;--- So there is no translation for DOS functions that use pointers.

        mov byte ptr [ebp].Client_Reg_Struc.Client_EDX,al
        mov byte ptr [ebp].Client_Reg_Struc.Client_EAX+1,2
        mov eax,21h
        @VMMCall Exec_Int

        jmp @@nextitem
@@done:
        @VMMCall End_Nest_Exec       ;end nested execution
        pop esi
        ret

_main   ENDP

        END _main

