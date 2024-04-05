
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

dprintf   proto c :ptr, :vararg

ifdef _DEBUG

@dprintf macro bCond, fmt, args:vararg
 if bCond
  ifnb <args>
	invoke dprintf, CStr(fmt), args
  else
	invoke dprintf, CStr(fmt)
  endif
 endif
endm

else

@dprintf textequ <;>

endif

