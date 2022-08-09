@echo off
rem uses Open Watcom C and WLink
rem OW needs a helper module: jlmw.obj
wcc386 -mf -zl -zls -s -I..\..\Include hello2w.c
wlink system nt file hello2w.obj, jlmw.obj name hello2w.exe option start=main_, map
..\patchpe hello2w.exe
