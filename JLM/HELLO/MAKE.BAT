@echo off
rem JWasm, Masm and PoAsm are supported
rem
rem ml -c -coff -Fl -I..\..\Include hello.asm
rem poasm -I..\..\Include HELLO.ASM
rem polink HELLO.OBJ /subsystem:console /FIXED:NO /map /out:HELLO.EXE
rem
jwasm -nologo -coff -I..\..\Include HELLO.ASM
rem wlink creates a "dummy" import directory entry which jload doesnt like
rem wlink system nt file HELLO.OBJ name HELLO.EXE
link HELLO.OBJ /subsystem:console /FIXED:NO /map /out:HELLO.EXE /ENTRY:_main /OPT:NOWIN98
rem
..\patchpe HELLO.EXE
