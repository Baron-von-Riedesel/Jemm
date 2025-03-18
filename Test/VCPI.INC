
desc struct
limit   dw ?
A0015   dw ?
A1623   db ?
attrib  db ?
lim_gr  db ?
A2431   db ?
desc ends

;--- VCPI structure for switch to protected mode

V86toPM struct
_CR3    dd ?	;CR3
_Gdtr   dd ?	;linear address PD for GDTR
_Idtr   dd ?	;linear address PD for IDTR
_Ldtr   dw ?	;LDTR
_Tr     dw ?	;TR
_Eip	dd ?	;EIP
_Cs     dd ?	;CS
V86toPM ends

IRETV86 struct
_Eip    dd ?
_Cs     dd ?
_Efl    dd ?
_Esp    dd ?
_Ss     dd ?
_Es     dd ?
_Ds     dd ?
_Fs     dd ?
_Gs     dd ?
IRETV86 ends

TSSSEG struct
dwLink	dd ?
dfStk0	df ?	;+04
		dw ?
dfStk1	df ?	;+0C
		dw ?
dfStk2	df ?	;+14
		dw ?
_CR3	dd ?	;+1C
_Eip	dd ?	;+20
_Efl	dd ?	;+24
_Eax	dd ?	;+28
_Ecx	dd ?	;+2C
_Edx	dd ?	;+30
_Ebx	dd ?	;+34
_Esp	dd ?	;+38
_Ebp	dd ?	;+3C
_Esi	dd ?	;+40
_Edi	dd ?	;+44
_ES		dd ?	;+48
_CS		dd ?	;+4C
_SS		dd ?	;+50
_DS		dd ?	;+54
_FS		dd ?	;+58
_GS		dd ?	;+5C
_LDT	dd ?	;+60
wFlags  dw ?	;+64
wOffs   dw ?	;+66
TSSSEG ends

