
?BUFFERED equ 0
?USEMONO equ 0  ;1=use monochrome monitor for dbg displays

;--- display string

@DbgOutS macro string, bCond
local bDisp
bDisp = 0
ifdef _DEBUG
bDisp = 1
endif
ifnb <bCond>
bDisp = bCond
endif
if bDisp
        call VPRINTSTR
        db string
        db 0
endif
endm

;--- display char

@DbgOutC macro bChar, bCond
local bDisp
bDisp = 0
ifdef _DEBUG
bDisp = 1
endif
ifnb <bCond>
bDisp = bCond
endif
if bDisp
        push eax
        mov al,bChar
        call VPUTCHR
        pop eax
endif
endm

;--- display DWORD

@DbgOutD macro _dword, bCond
local bDisp
bDisp = 0
ifdef _DEBUG
bDisp = 1
endif
ifnb <bCond>
bDisp = bCond
endif
if bDisp
        push eax
        mov eax, _dword
        call VDWORDOUT
        pop eax
endif
endm

;--- display WORD

@DbgOutW macro _word, bCond
local bDisp
bDisp = 0
ifdef _DEBUG
bDisp = 1
endif
ifnb <bCond>
bDisp = bCond
endif
if bDisp
        push ax
        mov ax, _word
        call VWORDOUT
        pop ax
endif
endm

;--- display BYTE

@DbgOutB macro _byte, bCond
local bDisp
bDisp = 0
ifdef _DEBUG
bDisp = 1
endif
ifnb <bCond>
bDisp = bCond
endif
if bDisp
        push ax
        mov al, _byte
        call VBYTEOUT
        pop ax
endif
endm

