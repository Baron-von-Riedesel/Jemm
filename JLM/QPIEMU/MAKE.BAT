@echo off
rem create QPIEMU.DLL
rem since jwasm v2.19, this can be done without using an (external) linker

rem Jemm's src directory has to be included since qpiemu needs ?PAGEDIR equate!

rem jwasm -c -pe -nologo -D?PE -FlRelease\QPIEMU.LST -FoRelease\QPIEMU.DLL -I..\..\Include QPIEMU.ASM
jwasm -c -pe -nologo -D?PE -I..\..\src -FlRelease\QPIEMU.LST -FoRelease\QPIEMU.DLL -I..\..\Include QPIEMU.ASM
patchpe Release\QPIEMU.DLL
