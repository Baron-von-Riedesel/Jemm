@echo off

ml -c -coff -nologo -Fl -Sg -I..\..\Include AHCICD.ASM
link /nologo /subsystem:native /dll AHCICD.obj /OUT:AHCICD.DLL /MAP
