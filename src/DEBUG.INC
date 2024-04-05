
@dbgdef macro name_
ifndef name_
name_ equ 0
endif
endm

@dbgdef ?V86DBG  ;1=enable displays in V86 monitor
@dbgdef ?V86XDBG ;1=enable more displays in V86 monitor (IRQs!)
@dbgdef ?DMADBG  ;1=enable DMA related displays
@dbgdef ?VDSDBG  ;1=enable VDS related displays
@dbgdef ?EMSDBG  ;1=enable EMS related displays
@dbgdef ?UMBDBG  ;1=enable UMB related displays
@dbgdef ?A20DBG  ;1=enable A20 related displays
@dbgdef ?EMBDBG  ;1=enable EMB related displays (?INTEGRATED only)
@dbgdef ?EMUDBG  ;1=enable opcode emulation related displays 
@dbgdef ?I15DBG  ;1=enable INT 15h, AH=87h related displays
@dbgdef ?VCPIDBG ;1=enable VCPI related displays
@dbgdef ?VCPIXDBG;1=enable VCPI mode switch displays
@dbgdef ?EMXDBG  ;1=enable EMMXXXX0 related displays 
@dbgdef ?POOLDBG ;1=enable memory pool related displays
@dbgdef ?INITDBG ;1=enable displays in protected-mode initialisation
@dbgdef ?HLTDBG  ;1=enable displays for true HLT emulation
@dbgdef ?UNLDBG  ;1=enable display for "unload"
@dbgdef ?RBTDBG  ;1=enable reboot debug
@dbgdef ?EXCDBG  ;1=enable displays in exception handler
@dbgdef ?PHYSDBG ;1=enable displays in physical memory handling
@dbgdef ?MAPDBG  ;1=enable mapping handling

?BUFFERED equ 0 ;1=buffer output in a XMS memory block
?USEMONO equ 0  ;1=use monochrome monitor for dbg displays

?DBGOUT  equ ?V86DBG + ?DMADBG + ?VDSDBG + ?EMSDBG + ?UMBDBG + ?A20DBG + ?EMBDBG + ?EMUDBG + ?I15DBG + ?VCPIDBG + ?USEMONO + ?POOLDBG + ?INITDBG + ?HLTDBG + ?UNLDBG + ?RBTDBG + ?EXCDBG + ?PHYSDBG + ?MAPDBG

CStr macro text:vararg
local sym
.text$03s segment byte flat 'CODE'
sym db text,0
.text$03s ends
	exitm <offset sym>
endm

@WaitKey macro keycode, bCond
local sm1
if bCond
        pushfd
        push    eax
sm1:
        in      al,64h      ;data from keyboard controller?
        test    al,1
        jz      sm1
        mov     ah,al
        in      al,60h
        test    ah,20h      ;mouse device?
        jnz     sm1
        cmp     al,keycode+80h  ;wait for key released
        jnz     sm1
        pop     eax
        popfd
endif
endm

;--- formatted output ( since v5.83 )
ifdef _DEBUG

dprintf proto c :ptr, :vararg

@dprintf macro bCond, fmt, args:vararg
 if bCond
  ifnb <args>
	invoke dprintf, CStr(fmt), args
  else
	invoke dprintf, CStr(fmt)
  endif
 endif
endm
else
@dprintf textequ <;>
endif

@DebugBreak macro
ifdef _DEBUG
        int 3
endif
endm

@CheckBlockIntegrity macro
if ?POOLDBG
        call CheckBlockIntegrity
endif
endm

