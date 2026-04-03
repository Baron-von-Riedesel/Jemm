
;*** debug macros and equates

?USEMONO equ 0	;1=use monochrome video mode

ifndef ?RMDBG
?RMDBG   = 0	;log real-mode
endif
ifndef ?INITDBG
?INITDBG = 0	;log init
endif
ifndef ?PEDBG
?PEDBG   = 0	;log PE loader
endif
ifndef ?IODBG
?IODBG   = 0	;log IO trapping
endif
ifndef ?PAGEDBG
?PAGEDBG = 0	;log page memory
endif
ifndef ?JLMDBG
?JLMDBG  = 0	;log jlm handling
endif
ifndef ?DMADBG
?DMADBG  = 0	;log DMA handling
endif
ifndef ?V86HOOKDBG
?V86HOOKDBG  = 0	;log v86 hook chain handling
endif
ifndef ?INT2FHOOKDBG
?INT2FHOOKDBG  = 0	;log Int2F hook handling
endif

ifdef _DEBUG
?LOG = ?INITDBG + ?PEDBG + ?IODBG + ?PAGEDBG + ?JLMDBG + ?DMADBG + ?V86HOOKDBG + ?INT2FHOOKDBG
else
?LOG = 0
endif

dprintf proto c :ptr, :vararg

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

