@echo off
rem add -D_DEBUG to create a debug version
jwasm -coff -nologo -Fl -I..\..\Include XCDROM32.ASM
jwlink format win pe hx dll ru native file XCDROM32.obj name XCDROM32.DLL op q,map
