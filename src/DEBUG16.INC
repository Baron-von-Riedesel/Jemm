
@dbgdef macro name_
ifndef name_
name_ equ 0
endif
?DBGOUT = ?DBGOUT + name_
endm

?DBGOUT = 0
@dbgdef ?INITRMDBG  ;1=log real-mode init
@dbgdef ?XMSRMDBG   ;1=log XMS calls
@dbgdef ?EMXRMDBG   ;1=log EMMXXXX0 calls
@dbgdef ?UNLRMDBG   ;1=log unload

;?RMDBG      equ ?INITRMDBG + ?XMSRMDBG + ?EMXRMDBG + ?UNLRMDBG  ; debug displays in real-mode

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
