
;*** debug macros and equates

?USEMONO	equ 0

?RMDBG   = 0	;trace real-mode
?INITDBG = 0	;trace init
?PEDBG   = 0	;trace PE loader
?IODBG   = 0	;trace IO trapping
?PAGEDBG = 0	;trace page memory
?JLMDBG  = 1	;trace jlm handling

ifdef _DEBUG
?TRACE = ?INITDBG + ?PEDBG + ?IODBG + ?PAGEDBG + ?JLMDBG
else
?TRACE = 0
endif

VPRINTSTR proto
VDWORDOUT proto
VWORDOUT  proto

@DbgOutS macro string, bCond
ifdef _DEBUG
 if bCond
	call VPRINTSTR
	db string
	db 0
 endif
endif
	endm

;--- display DWORD in V86

@DbgOutD macro _dword, bCond
ifdef _DEBUG
 if bCond
	push eax
	mov eax, _dword
	call VDWORDOUT
	pop eax
 endif
endif
	endm

;--- display WORD in V86

@DbgOutW macro _word, bCond
ifdef _DEBUG
 if bCond
	push eax
	mov ax, _word
	call VWORDOUT
	pop eax
 endif
endif
	endm

@tracejmp macro target
if ?TRACE
	jmp target
endif
	endm
