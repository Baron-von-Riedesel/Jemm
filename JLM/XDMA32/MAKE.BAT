@echo off
rem  Assemble and link file for the XDMA32 JLM.

rem ml -c -coff -Fl -D_DEBUG -I..\..\Include XDMA32.ASM
rem ml -c -coff -Fl -I..\..\Include XDMA32.ASM
rem -zzs is needed for OW WLink v1.8 only!
rem jwasm -coff -zzs -nologo -Fl -I..\..\Include -Fo=XDMA32.OBJ XDMA32.ASM
rem jwasm -coff -nologo -Fl -D_DEBUG -I..\..\Include -Fo=XDMA32.OBJ XDMA32.ASM
jwasm -coff -nologo -Fl -I..\..\Include -Fo=XDMA32.OBJ XDMA32.ASM

rem polink XDMA32.OBJ /SUBSYSTEM:native /DLL /OUT:XDMA32.DLL /OPT:NOWIN98 /MAP
rem link XDMA32.OBJ /NOLOGO /SUBSYSTEM:native /DLL /OUT:XDMA32.DLL /OPT:NOWIN98 /MAP /Entry:DllMain
jwlink format win pe hx dll file xdma32.obj name xdma32.dll op map
