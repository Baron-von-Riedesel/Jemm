@echo off
rem uses MS VC and PoLink
cl -c -I..\..\Include hello2.c
polink hello2.obj /subsystem:console /fixed:no /out:hello2.exe /entry:main
..\patchpe hello2.exe
