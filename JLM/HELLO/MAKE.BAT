@echo off
rem
rem use JWasm & JWlink
rem
jwasm -nologo -coff -Fl=Release\Hello -Fo=Release\Hello -I..\..\Include Hello.asm
jwlink format win pe hx ru native file Release\Hello.obj name Release\Hello.exe op q,m=Release\Hello,stack=0x1000

rem use JWasm - since JWasm v2.19, cmdline option -pe supports several linker features;
rem also, stub JLSTUB.BIN may be added. Then the program can be launched simply by typing its name.
rem
rem jwasm -nologo -pe -DFMTPE -DSTUB=..\JLSTUB\Build\jlstub.bin -Fl=Release\Hello -Fo=Release\Hello -I..\..\Include Hello.asm
rem patchPE -x -s:0x1000 Release\Hello.exe

rem use Masm & Link
rem
rem ml -c -coff -FlRelease\Hello -FoRelease\Hello -I..\..\Include Hello.asm
rem link /NOLOGO Release\HELLO.OBJ /subsystem:native /FIXED:NO /map /out:Release\Hello.exe /ENTRY:_main /OPT:NOWIN98
rem \hx\bin\patchpe -s:0x4000 -x Release\Hello.exe
