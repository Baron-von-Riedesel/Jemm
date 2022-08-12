@echo off
set FASMINC=\fasm\Include
set JLMINC=..\..\Include
fasm JCLOCK.ASM
fasm JCLOCK2.ASM
\hx\bin\patchpe JCLOCK.DLL
\hx\bin\patchpe JCLOCK2.DLL
