
;--- constants used by Jemm & JLoad

?VERSIONHIGH    equ 5
?VERSIONLOW     equ 87

?BASE           EQU 110000h         ; base of Jemm 32bit code
?SYSBASE        EQU 0F8000000h      ; linear address system space
?PAGEDIR        EQU ?SYSBASE+1000h  ; linear address page dir
?PAGETABSYS     EQU 3000h           ; rel. offset (?SYSBASE) for system page table
;--- 3000 = 3 page tables ( pagedir, page tab0, system page tab )
?TOS            EQU ?SYSBASE+1000h+3000h+1000h  ;top of ring 0 stack

;--- this is the structure for a "Get VMM info" request
;--- v5.87: fields e08_pCallBack and e08_CallBackRM do now
;--- point to the *second* static breakpoint in Jemm32/Jemm16.
;--- Thus JLoad doesn't need to know anything about the breakpoint array.

EMX08 struct
e08_ServiceTable    dd ?	;linear address service table
e08_pCallBack       dd ?	;linear address callback BP in Jemm32
e08_CallBackRM      dd ?	;segment:offset of callback BP in Jemm16
e08_GDTR            df ?
e08_IDTR            df ?
e08_TR              dw ?
e08_FlatCS          dw ?
EMX08 ends

