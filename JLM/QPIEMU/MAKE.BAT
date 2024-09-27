@echo off
rem create QPIEMU.DLL
rem since jwasm v2.19, this can be done without using an (external) linker

jwasm -c -pe -nologo -D?PE -FlRelease\QPIEMU.LST -FoRelease\QPIEMU.DLL -I..\..\Include QPIEMU.ASM
patchpe Release\QPIEMU.DLL
