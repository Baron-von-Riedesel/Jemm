
ifndef ?INITRMDBG
?INITRMDBG  equ 0   ;log real-mode init
endif
ifndef ?XMSRMDBG
?XMSRMDBG   equ 0   ;log XMS calls
endif
ifndef ?EMXRMDBG
?EMXRMDBG   equ 0   ;log EMMXXXX0 calls
endif
ifndef ?UNLRMDBG
?UNLRMDBG   equ 0   ;log unload
endif
?RMDBG      equ ?INITRMDBG + ?XMSRMDBG + ?EMXRMDBG + ?UNLRMDBG  ; debug displays in real-mode

?USEMONO equ 0  ;1=use monochrome monitor for dbg displays

ifdef _DEBUG

dprintf proto c :ptr, :vararg

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
