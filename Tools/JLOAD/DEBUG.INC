
;*** debug macros and equates

?USEMONO	equ 0

ifndef ?RMDBG
?RMDBG   = 0	;trace real-mode
endif
ifndef ?INITDBG
?INITDBG = 0	;trace init
endif
ifndef ?PEDBG
?PEDBG   = 0	;trace PE loader
endif
ifndef ?IODBG
?IODBG   = 0	;trace IO trapping
endif
ifndef ?PAGEDBG
?PAGEDBG = 0	;trace page memory
endif
ifndef ?JLMDBG
?JLMDBG  = 0	;trace jlm handling
endif
ifndef ?DMADBG
?DMADBG  = 0	;trace DMA handling
endif

ifdef _DEBUG
?TRACE = ?INITDBG + ?PEDBG + ?IODBG + ?PAGEDBG + ?JLMDBG + ?DMADBG
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
	push _dword
	call VDWORDOUT
 endif
endif
	endm

;--- display WORD in V86

@DbgOutW macro _word, bCond
ifdef _DEBUG
 if bCond
	push _word
	call VWORDOUT
 endif
endif
	endm

@tracejmp macro target
if ?TRACE
	jmp target
endif
	endm
