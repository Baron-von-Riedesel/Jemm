@echo off
rem
rem JWasm v2.19: cmdline option -pe will create a JLM without external linker
rem
jwasm -nologo -pe -DFMTPE -Fl=Release\ -Fo=Release\KEYBGR.DLL -I..\..\Include KeybGr.asm
patchPE -x -s:0x1000 Release\KEYBGR.DLL
