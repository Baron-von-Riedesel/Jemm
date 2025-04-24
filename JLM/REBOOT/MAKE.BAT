@echo off
rem
jwasm -Fl -q -I..\..\Include REBOOT.ASM 
jwlink format win pe hx dll ru native file REBOOT.obj name REBOOT.DLL op map,quiet export _ddb.1
rem
jwasm -bin -Fl -q fastbrm.asm 
jwasm      -Fl -q -I..\..\Include FASTBOOT.ASM 
jwlink format win pe hx dll ru native file FASTBOOT.obj name FASTBOOT.DLL op map,quiet export _ddb.1
rem
jwasm -bin -Fl -DBOOTDBG -q fastbrm.asm 
jwasm      -Fl -DBOOTDBG -q -I..\..\Include FASTBOOT.ASM 
jwlink format win pe hx dll ru native file FASTBOOT.obj name FASTBDBG.DLL op map,quiet export _ddb.1
