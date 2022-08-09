@echo off
set FASMINC=\fasm\Include
set JLMINC=..\..\Include
fasm JCLOCK.ASM
fasm JCLOCK2.ASM
..\patchpe JCLOCK.DLL
..\patchpe JCLOCK2.DLL
