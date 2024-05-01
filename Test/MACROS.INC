
CStr macro text:VARARG
local sym
	.const
sym db text,0
	.code
	exitm <offset sym>
endm

