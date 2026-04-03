
;--- assembly conditionals

;--- constants
;--- ?SYSBASE is from JSYSTEM.INC (=0F8000000h)

?SYSTEMADDR		equ ?SYSBASE+400000h;linear address "system" region
?PRIVATEADDR	equ 400000h			;linear address "private" region

?PMSTACK	equ 1	;1=alloc a 4 kB stack space; 0=use Jemm's stack

;--- communication structure 16-bit real-mode -> 32-bit protected-mode

VMMS	struc
		JLCOMM <?>
emx08	EMX08 <?>
hFile	dw ?    ;file handle of JLM
pszLdr	dw ?	;points to full path of JLOAD.EXE
pszJLM	dw ?	;points to JLM name parameter
pHdr	dw ?	;points to PE header
pBuffer	dw ?	;points to a 4 kB buffer in conv. memory
pDDB	dw ?	;points to DDB (if module is to be unloaded)
VMMS	ends


