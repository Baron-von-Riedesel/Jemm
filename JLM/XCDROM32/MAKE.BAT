@echo off

rem add -D_DEBUG to create a debug version

jwasm -coff -nologo -Fl -I..\..\Include XCDROM32.ASM
jwlink format win pe hx dll ru native file xcdrom32.obj name xcdrom32.dll op q,map

rem MS tools
rem ml -c -coff -Fl -I..\..\Include XCDROM32.ASM
rem link XCDROM32.OBJ /NOLOGO /DLL /out:XCDROM32.DLL /map:XCDROM32.MAP /subsystem:native /Fixed:no /Entry:DllMain
