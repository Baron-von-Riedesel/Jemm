
;--- assembly conditionals

?USEVCPIEXIT    equ 0		;std=0, 1=use VCPI ax=DE0Ch to return to v86-mode

;--- constants
;--- ?SYSLINEAR is from Jemm32.inc, value is ?SYSBASE+1000h (=0F8001000h)

?SYSTEMADDR 	equ ?SYSLINEAR +3FF000h	;linear address "system" region
?PRIVATEADDR 	equ 400000h	;linear address "private" region

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


