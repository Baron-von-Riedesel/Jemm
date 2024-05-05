
; structure for VCPI switch from V86 to protected mode

V86TOPM  STRUCT
dwCR3       DD  ?   ; client's CR3 value
dwGDTOFFS   DD  ?   ; offset of client's GDTR value
dwIDTOFFS   DD  ?   ; offset of client's IDTR value
wLDTR       DW  ?   ; client's LDTR value
wTR         DW  ?   ; client's TR value
dfCSEIP     DF  ?   ; entry point in client
V86TOPM  ENDS

