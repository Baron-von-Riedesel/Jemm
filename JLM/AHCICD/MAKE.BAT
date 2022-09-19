@echo off

jwasm -c -coff -nologo -Fl -Sg -I..\..\Include AHCICD.ASM
rem jwasm -coff -nologo -D_DEBUG -Fl -Sg -I..\..\Include AHCICD.ASM
jwlink format win pe hx dll ru native file AHCICD.obj name AHCICD.DLL op q,map
