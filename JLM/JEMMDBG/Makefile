
# create jemmdbg.exe and int3.exe
#
# jwasm's option -pe cannot be used, since the DDB cannot be exported then;
# so jwlink is necessary.
# jwasm -pe -nologo -Fl -Sg -I..\..\Include -Fo jemmdbg.dll jemmdbg.asm 
# patchpe -x -y:1 jemmdbg.dll

ALL: jemmdbg.exe int3.exe

jemmdbg.exe: jemmdbg.obj jlstub.bin
	@jwlink format win pe hx dll ru native f jemmdbg.obj n jemmdbg.exe op q,m,stub=jlstub.bin export _ddb.1

jemmdbg.obj: jemmdbg.asm debugj.bin
	@jwasm -coff -nologo -Fl -Sg -I..\..\Include jemmdbg.asm 

jlstub.bin: jlstub.asm
	@jwasm -nologo -mz -Fo=jlstub.bin jlstub.asm

debugj.bin: \projects\debug\build\debugj.bin
	@copy \projects\debug\build\debugj.bin

int3.exe: int3.asm
	@jwasm -nologo -coff -Fl -I..\..\Include int3.asm 
	@jwlink format win pe hx dll ru native f int3.obj n int3.exe op q,m,stub=jlstub.bin

clean:
	@del *.obj
	@del *.map
	@del *.lst
	@del *.bin
	@del *.exe
