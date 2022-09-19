@echo off
rem Assemble and link file for the XDMA32 JLM.
rem jwasm: option -zzs is needed for OW WLink v1.8!

jwasm -coff -nologo -Fl -Sg -I..\..\Include -Fo=XDMA32.obj XDMA32.ASM
jwlink format win pe hx dll ru native file XDMA32.obj name XDMA32.DLL op q,map
