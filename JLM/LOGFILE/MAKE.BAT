@echo off
jwasm -nologo -c -coff -nologo -Fl -Sg -I..\..\Include LOGFILE.ASM
jwlink format win nt hx dll ru native file LOGFILE.obj name LOGFILE.DLL op q,map=LOGFILE.MAP export _ddb.1
rem
jwasm -nologo -mz WRITELOG.ASM
