
;--- macros:
;--- CStr()

ifndef CStr

;--- CStr() define a string in CCONST

CStr macro y:req, name
local sym,xxx
CCONST segment
ifnb <name>
  ifidni <y>,<"">
    name db 0
  else
    name db y,0
  endif
else
  ifidni <y>,<"">
    sym db 0
  else
    sym db y,0
  endif
endif
CCONST ends
ifnb <name>
	exitm <offset name>
else
	exitm <offset sym>
endif
	endm

endif

