@echo off
rem
rem JWasm/JWlink or Masm/Link are supported
rem
jwasm -nologo -coff -Fl=Release\Hello -Fo=Release\Hello -I..\..\Include Hello.asm
jwlink format win pe hx ru native file Release\Hello.obj name Release\Hello.exe op m=Release\Hello,q

rem using MS tools
rem ml -c -coff -FlRelease\Hello -FoRelease\Hello -I..\..\Include Hello.asm
rem link HELLO.OBJ /subsystem:nativee /FIXED:NO /map /out:Release\Hello.exe /ENTRY:_main /OPT:NOWIN98
rem \hx\bin\patchpe Release\Hello.exe
