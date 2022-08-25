@echo off
rem uses MS VC and MS Link
\msvc71\bin\cl -c -I..\..\Include hello2.c
link /LIBPATH:\msvc71\lib hello2.obj /subsystem:native /fixed:no /out:hello2.exe /entry:main
\hx\bin\patchpe hello2.exe
