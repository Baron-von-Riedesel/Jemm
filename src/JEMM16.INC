
;--- globals for jemm16.asm and init16.asm

if ?INTEGRATED
NAMEEXE equ <"JEMMEX">
NAMEMOD equ <"JemmEx">
else
NAMEEXE equ <"JEMM386">
NAMEMOD equ <"Jemm386">
endif

;--- modes for mainex()
EXECMODE_SYS equ 0	;launched as dos device driver
EXECMODE_EXE equ 1	;launched as application

PF16 TYPEDEF far16 ptr

XMSPARAMS struct
Driver      PF16 0
mem_largest DD 0	;largest free block in kB
mem_free    DD 0	;total free mem in kB
mem_highest dd 0	;highest physical address; by XMS v3 (Jemm386) or Int15 (JemmEx)
if ?INTEGRATED
max         DD 4095*1024	;MAXEXT= value
 if ?XMS35
smax        DD 1023*4096*1024	;MAXSEXT= value
maxhigh     dd -1	; mask for upper memory address limit   
 endif
num_handles DW ?XMS_DEFHDLS	;XMSHANDLES= value
 if ?XMS35
smem_used   db 0	;set to 1 if any super-extended block is used
 endif
endif
XMSPARAMS ends

InitJemm        proto c
IsJemmInstalled proto c
EmmInstallcheck proto c
XMSinit         proto c
CheckIntHooks   proto stdcall :WORD
UnloadJemm      proto c
if ?INTEGRATED
?XMS_STATICHDLS equ 10	;free xms handles to be used for int 15h, ax=e820h
I15SetHandle    proto c
I15AllocMemory  proto stdcall :WORD, :DWORD
GetEMBBase      proto stdcall: word
endif
mainex          proto c :WORD, :ptr BYTE
printf          proto c :ptr byte, :VARARG
_memicmp        proto c :ptr BYTE, :ptr BYTE, :WORD

externdef c jemmini:JEMMINIT
externdef c xms:XMSPARAMS
externdef c sig1:BYTE
externdef c sig2:BYTE
externdef c bVerbose:byte

if ?INTEGRATED
 if ?XMS35
externdef c xms_smax_noe820:byte
?XMS_DEFHDLS equ 48
 else
?XMS_DEFHDLS equ 32
 endif
?XMS_MAXHDLS equ 128
endif
