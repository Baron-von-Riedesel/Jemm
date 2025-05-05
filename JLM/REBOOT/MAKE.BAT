@echo off
jwasm -nologo -pe  -Fl -Fo=REBOOT.DLL -I..\..\Include REBOOT.ASM 
jwasm -nologo -bin -Fl FASTBRM.ASM 
jwasm -nologo -pe  -Fl -Fo=FASTBOOT.DLL -I..\..\Include FASTBOOT.ASM 
