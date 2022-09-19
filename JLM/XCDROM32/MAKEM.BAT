@echo off
rem add -D_DEBUG to create a debug version
rem using MS tools
ml -c -coff -Fl -I..\..\Include XCDROM32.ASM
link XCDROM32.OBJ /NOLOGO /DLL /out:XCDROM32.DLL /map:XCDROM32.map /subsystem:native /Fixed:no
