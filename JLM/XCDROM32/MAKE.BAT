@echo off

rem create variant with debug messages
rem jwasm -coff -nologo -D_DEBUG -Fl -Sg -I..\..\Include XCDROM32.ASM

rem std variant
jwasm -coff -nologo -Fl -I..\..\Include XCDROM32.ASM

jwlink format win pe hx dll ru native file XCDROM32.obj name XCDROM32.DLL op q,map
