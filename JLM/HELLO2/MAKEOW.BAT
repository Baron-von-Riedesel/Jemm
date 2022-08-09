@echo off
rem uses Open Watcom C and WLink
rem OW needs a helper module: jlmw.obj
wcc386 -mf -zl -zls -s -I..\..\Include hello2w.c
jwlink format win nt hx file hello2w.obj, jlmw.obj name hello2w.exe option start=main_, map
