
;*** german keyboard driver for MF keyboards
;--- the first JLM (Jemm Loadable Module) ever.

;--- v1.0: initial
;--- v1.1: route nontranslated key presses to previous handler
;--- v1.2: now fully compatible with the old KEYBGR.EXE (needs 30h DOS mem)
;--- v1.3: source now compatible with JWasm

        .386
        .model flat

        include jlm.inc

cr equ 13
lf equ 10

kbdstat1 equ 417h;  byte
kbdstat2 equ 418h;  byte
bufsta   equ 41ah;  word
bufend   equ 41ch;  word
ebufsta  equ 480h;  word
ebufend  equ 482h;  word
kbdflgs  equ 496h;  byte
LEDflgs  equ 497h;  byte

DLL_PROCESS_ATTACH  equ 1
DLL_PROCESS_DETACH  equ 0

        .code

;--- AltGr keys

altgrkeytab label byte
       db 03h           ;2 -> ˝
       db 04h           ;3 -> ¸
       db 08h           ;7 -> {
       db 09h           ;8 -> [
       db 0Ah           ;9 -> ]
       db 0Bh           ;0 -> }
       db 0Ch           ;· -> \
       db 10h           ;Q -> @
       db 1Bh           ;+ -> ~
       db 32h           ;M -> Ê
       db 56h           ;< -> |
ALTGRTABSIZ equ $ - altgrkeytab
       db '˝'
       db '¸'
       db '{'
       db '['
       db ']'
       db '}'
       db '\'
       db '@'
       db '~'
       db 'Ê'
       db '|'

;--- numlock keys

numpadkeytab label byte
       db 53h       ;',' 
NUMPADTABSIZ equ $ - numpadkeytab
       public PLAB1
PLAB1  db ','

;--- ctrl keys

ctrlkeytab label byte
       db 15h       ;ctrl z
       db 2ch       ;ctrl y
CTRLTABSIZ equ $ - ctrlkeytab
       db 1Ah
       db 19h

;--- standard keys

stdkeytab label byte
       db 15h            ;z
       db 1ah            ;Å
       db 27h            ;î
       db 28h            ;Ñ
       db 2ch            ;y
       db 03h            ;2
       db 04h            ;3
       db 07h            ;6
       db 08h            ;7
       db 09h            ;8
       db 0ah            ;9
       db 0bh            ;0
       db 0ch            ;sz
       db 0dh            ;apost
       db 1bh            ;+
       db 29h            ;^
       db 2Bh            ;#
       db 33h            ;,
       db 34h            ;.
       db 35h            ;-
       db 56h            ;<
STDTABSIZ equ $ - stdkeytab

       db 'z'
       db 'Å'
       db 'î'
       db 'Ñ'
       db 'y'
L02B3X label byte                 ;CAPS-LOCK insensitive keys
       db 0ffh
       db 0ffh
       db 0ffh
       db 0ffh
       db 0ffh
       db 0ffh
       db 0ffh
       db '·'
       db "'"
       db '+'
       db '^'
       db '#'
       db 0ffh           ;,
       db 0ffh           ;.
       db '-'
       db '<'

       db 'Z'
       db 'ö'
       db 'ô'
       db 'é'
       db 'Y'
       db '"'
       db ''
       db '&'
       db '/'
       db '('
       db ')'
       db '='
       db '?'
       db '`'
       db '*'
       db '¯'
       db "'"
       db ';'
       db ':'
       db '_'
       db '>'

        align 4

introu15 proc

;--- this is the entry from v86-mode when a key has been pressed
;--- (int 15h, ah=4Fh)

        @VMMCall Simulate_Iret   ;emulate an IRET in v86

        mov     eax,[ebp].Client_Reg_Struc.Client_EAX
        cmp     al,0E0h
        jnc     done
        call    trans
done:
        ret
introu15 endp

trans   proc near
        mov     dx,word ptr ds:[kbdstat1]
        CLD
        mov     bl,al
        mov     bh,ds:[kbdflgs]
        and     al,7Fh
        MOV     ECX,ALTGRTABSIZ         ;ch=0!
        test    bh,08h                  ;right alt (altgr) pressed?
        jz      @F
        test    dx,0204h                ;any ctrl or alt-left pressed?
        jnz     @F
        MOV     EDI,offset altgrkeytab
        jmp     scantabX
@@:
        test    dl,08h                  ;any alt pressed?
        jnz     exit
        MOV     EDI,offset ctrlkeytab
        mov     CL,CTRLTABSIZ
        test    dl,04h                  ;any ctrl pressed?
        jnz     scantabX
        MOV     EDI,offset stdkeytab
        MOV     cl,STDTABSIZ
        cmp     al,53h                  ;numpad ','?
        jnz     scantab
        test    bh,2                    ;extended key (E0)?
        jnz     scantab
        test    dl,20h                  ;num lock active?
        jz      exit
        mov     cl,NUMPADTABSIZ
        mov     edi,offset numpadkeytab
scantabX:
        mov     dl,0                    ;ignore shift state
scantab:
        push    ecx
        repnz   scasb
        pop     ecx
        jnz     exit
        dec     edi
        add     edi,ecx
        cmp     edi,offset L02B3X    ;caps lock sensitiv?
        jnb     @F
        test    dl,40h              ;shift lock?
        jz      @F
        test    dl,3                ;shift pressed?
        jnz     unorm1
        jmp     unorm2
@@:
        test    dl,3                ;shift pressed?
        jz      unorm1
unorm2:
        add     edi,ecx
unorm1:
        mov     ah,al               ;save scan code
        mov     al,[edi]
        cmp     al,0FFh
        jz      exit
found:
        test    bl,80h              ;is key released?
        jnz     dontsave
        call    savekey
dontsave:
        and     byte ptr [ebp].Client_Reg_Struc.Client_EFlags,not 1 ;clear carry
        ret
exit:
        stc
        ret
savekey:
        MOVzx   EDI,word ptr ds:[bufend]
        MOV     eSI,eDI
        INC     eDI
        INC     eDI
        CMP     DI,ds:[ebufend]
        JNZ     @F
        MOV     DI,ds:[ebufsta]
@@:
        CMP     DI,ds:[bufsta]
        JZ      @F                  ;no more room in buffer
        MOV     [ESI+400h],AX
        MOV     ds:[bufend],DI
@@:
        retn

trans   endp

;--- install the JLM:
;--- + first try to alloc a v86 callback
;--- + save this callback and the previous v86 int 15h vector
;---   in the 16-bit "real-mode" code.
;--- + set driver attributes in JLoad's header
;--- + copy the "real-mode" code to JLoad's begin in DOS memory
;---   (this is ensured to be safe as long as the code size doesn't
;---   exceed 1 kB).
;--- + set the size of the resident driver part in the driver's
;---   request header.

install proc uses esi edi

        test [ecx].JLCOMM.wFlags, JLF_DRIVER  ;loaded as device driver?
        jz failed

        push ecx
        mov esi, offset introu15
        mov edx, 0
        @VMMCall Allocate_V86_Call_Back      ;get a v86 callback
        pop esi
        jc failed
        mov edx, offset rmcode
        mov [edx+newvec-@], eax             ;patch the 16-bit code
        mov eax, ds:[15h*4]
        mov [edx+oldvec-@], eax

        movzx edi,[esi].JLCOMM.wLdrCS       ;set driver attributes
        shl edi, 4
        mov  word ptr [edi+6],18            ;offset strategy (dummy)
        mov  word ptr [edi+8],18            ;offset interrupt (dummy)
        mov dword ptr [edi+10],"BYEK"       ;driver name
        mov dword ptr [edi+14],"$$RG"
        mov  byte ptr [edi+18],0CBh         ;RETF
        add edi,20

        push esi
        push edi
        mov esi, offset rmcode              ;copy 16-bit code to DOS memory
        mov ecx, sizermcode
        rep movsb
        pop edi
        pop esi

        mov ax,[esi].JLCOMM.wLdrCS          ;set the new int 15h vector
        shl eax, 16
        mov ax,20 
        mov ds:[15h*4],eax

        add ax,sizermcode
        mov edx,[esi].JLCOMM.lpRequest
        mov [edx+14],ax                     ;set resident size

        mov eax,1
        ret
failed:
        xor eax,eax
        ret

install endp

;--- deinstall. Since the module will only load
;--- as a device driver in CONFIG.SYS, it cannot be unloaded

deinstall   proc

        xor eax, eax    ;refuse to unload
        ret

deinstall   endp

DllMain proc stdcall public hModule:dword, dwReason:dword, dwRes:dword

        mov ecx, dwRes
        mov eax,dwReason
        cmp eax,DLL_PROCESS_ATTACH
        jnz @F
        call install
        jmp exit
@@:        
        cmp eax,DLL_PROCESS_DETACH
        jnz @F
        call deinstall
@@:
exit:
        ret

DllMain endp

;--- DOS 16-bit "real-mode" code.
;--- this code will be patched and then copied to DOS memory
;--- it will be the new v86 int 15h handler.

    align dword
rmcode label near

_TEXT16 segment use16 dword public 'CODE'
@:
        cmp ah, 4Fh
        jz @F
        db 0EAh     ; jmp SSSS:OOOO
oldvec  dd 0		; previous handler
@@:
        db 0EAh     ; jmp SSSS:0000
newvec  dd 0		; v86-breakpoint
sizermcode equ $ - @
_TEXT16 ends

        end DllMain
