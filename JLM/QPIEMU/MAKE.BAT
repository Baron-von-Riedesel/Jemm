@echo off
rem create QPIEMU.DLL without linker, requires jwasm v2.19+
rem Jemm's src directory has to be included since qpiemu needs ?PAGEDIR equate!
jwasm -c -pe -nologo -D?PE -I..\..\src -FlRelease\QPIEMU.LST -FoRelease\QPIEMU.DLL -I..\..\Include QPIEMU.ASM
