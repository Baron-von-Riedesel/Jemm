@echo off
rem Assemble and link file for the XDMA32 JLM.
rem jwasm: option -zzs is needed for OW WLink v1.8!

jwasm -coff -nologo -Fl -I..\..\Include -Fo=XDMA32.OBJ XDMA32.ASM
jwlink format win pe hx dll ru native file xdma32.obj name xdma32.dll op q,map

rem MS tools
rem ml -c -coff -Fl -D_DEBUG -I..\..\Include XDMA32.ASM
rem link XDMA32.OBJ /NOLOGO /SUBSYSTEM:native /DLL /OUT:XDMA32.DLL /OPT:NOWIN98 /MAP /Entry:DllMain
