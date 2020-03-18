
;--- globals for jemm16.asm and init16.asm

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

if ?INTEGRATED
NAMEEXE equ <"JEMMEX">
NAMEMOD equ <"JemmEx">
else
NAMEEXE equ <"JEMM386">
NAMEMOD equ <"Jemm386">
endif

@XBDA     equ 40Eh
@MEM_SIZE equ 413h

;--- modes for mainex()
EXECMODE_SYS equ 0	;launched as dos device driver
EXECMODE_EXE equ 1	;launched as application

InitJemm proto c
IsJemmInstalled proto c
EmmInstallcheck proto c
XMSinit proto c
CheckIntHooks proto stdcall :WORD
UnloadJemm proto c
if ?RMDBG
VPRINTSTR proto
VDWORDOUT proto
VWORDOUT  proto
endif
if ?INTEGRATED
?PREDEFXMSHDLS equ 8	;free xms handles to be used for int 15h, ax=e820h
I15SetHandle proto c
I15AllocMemory proto stdcall :WORD, :DWORD
GetEMBBase proto stdcall: word
endif

mainex proto c :WORD, :ptr BYTE

printf proto c :ptr byte, :VARARG
strlen proto c :ptr BYTE
_memicmp proto c :ptr BYTE, :ptr BYTE, :WORD

externdef c jemmini:JEMMINIT
externdef c XMSdriverAddress:far16 ptr
externdef c sig1:BYTE
externdef c sig2:BYTE

if ?INTEGRATED
externdef c xms_num_handles:WORD
externdef c xms_max:dword
externdef c xms_mem_free:dword
externdef c xms_mem_largest:dword
externdef c xms_mem_highest:dword
endif
