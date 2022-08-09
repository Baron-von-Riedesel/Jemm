@echo off
rem ml -c -coff -D_DEBUG -Fl -I..\..\Include XCDROM32.ASM
rem ml -c -coff -Fl -I..\..\Include XCDROM32.ASM
rem -zzs is needed for OW WLink v1.8 only!
rem jwasm -coff -zzs -nologo -I..\..\Include -Fl -Fo=XCDROM32.OBJ XCDROM32.ASM
jwasm -coff -nologo -I..\..\Include -Fl -Fo=XCDROM32.OBJ XCDROM32.ASM
rem
rem polink XCDROM32.OBJ /DLL /out:XCDROM32.DLL /map:XCDROM32.MAP /subsystem:native /Fixed:no
rem link XCDROM32.OBJ /NOLOGO /DLL /out:XCDROM32.DLL /map:XCDROM32.MAP /subsystem:native /Fixed:no /Entry:DllMain
jwlink format win pe hx dll ru console file xcdrom32.obj name xcdrom32.dll op map
