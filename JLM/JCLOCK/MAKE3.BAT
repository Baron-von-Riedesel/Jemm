@echo off
rem make jclock3.dll - no link step required.
jwasm -pe -I..\..\Include -Fo=JCLOCK3.DLL JCLOCK3.ASM
