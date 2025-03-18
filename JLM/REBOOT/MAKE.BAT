@echo off
rem
jwasm -Fl -q -I..\..\Include reboot.asm 
jwlink format win pe hx dll ru native file reboot.obj name reboot.dll op map,quiet export _ddb.1
