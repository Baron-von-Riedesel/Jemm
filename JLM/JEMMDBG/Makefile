
# create JemmDbg.exe and JDbgBrk.exe
#
# jwasm's option -pe cannot be used, since the DDB cannot be exported then;
# so jwlink is necessary.
# jwasm -pe -nologo -Fl -Sg -I..\..\Include -Fo jemmdbg.dll jemmdbg.asm 
# patchpe -x -y:1 jemmdbg.dll

ALL: JemmDbg.exe JDbgBrk.exe

JemmDbg.exe: JemmDbg.obj jlstub.bin
	@jwlink format win pe hx dll ru native f JemmDbg.obj n JEMMDBG.EXE op q,m,stub=jlstub.bin export _ddb.1

JDbgBrk.exe: JDbgBrk.asm jlstub.bin
#	@jwasm -nologo -coff -Fl -I..\..\Include JDbgBrk.asm 
#	@jwlink format win pe hx ru native f JDbgBrk.obj n JDBGBRK.EXE op q,m,stub=jlstub.bin,stack=0x1000,heap=0x1000
	@jwasm -nologo -pe -Fl -I..\..\Include JDbgBrk.asm 
	@pestub -n -s JDbgBrk.exe jlstub.bin
	@patchpe -x -y:1 -s:0x1000 -h:0x1000 JDbgBrk.exe

JemmDbg.obj: JemmDbg.asm debugR.bin
	@jwasm -coff -nologo -Fl -Sg -I..\..\Include JemmDbg.asm 

jlstub.bin: jlstub.asm
	@jwasm -nologo -mz -Fl -Fo=jlstub.bin jlstub.asm

debugR.bin: \projects\debug\build\debugR.bin
	@copy \projects\debug\build\debugR.bin

clean:
	@del *.obj
	@del *.map
	@del *.lst
	@del *.bin
	@del *.exe
