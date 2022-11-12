
;--- run "int 3" to wake up JemmDbg.

	.386
	.MODEL FLAT
	include jlm.inc
	.CODE

main proc c

	mov eax, 1
	int 3
	ret

main ENDP

	END main

