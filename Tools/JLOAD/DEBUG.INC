
;*** debug macros and equates

?USEMONO	equ 0

?RMDBG   = 0	;trace real-mode
?INITDBG = 0	;trace init
?PEDBG   = 0	;trace PE loader
?IODBG   = 0	;trace IO trapping
?PAGEDBG = 0	;trace page memory

?TRACE = ?INITDBG + ?PEDBG + ?IODBG + ?PAGEDBG

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
externdef VPRINTSTR:near
	call VPRINTSTR
	db string
	db 0
endif
	endm

;--- display DWORD in V86

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
externdef VDWORDOUT:near
	push eax
	mov eax, _dword
	call VDWORDOUT
	pop eax
endif
	endm

;--- display WORD in V86

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
externdef VWORDOUT:near
	push eax
	mov ax, _word
	call VWORDOUT
	pop eax
endif
	endm


@tracejmp macro target
if ?TRACE
	jmp target
endif
	endm
