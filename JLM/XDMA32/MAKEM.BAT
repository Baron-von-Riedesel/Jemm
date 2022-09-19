@echo off
rem using MS tools
ml -c -coff -Fl -D_DEBUG -I..\..\Include XDMA32.ASM
link /NOLOGO /SUBSYSTEM:native /DLL XDMA32.obj /OUT:XDMA32.DLL /OPT:NOWIN98 /MAP
