
# create JemmDbg.exe and JDbgBrk.exe
# tools used: jwasm & jwlink
# needs Debug/X's DebugR variant ( see DEBUGRDIR below ).
#
# run "nmake aux=1"        for a variant that uses a serial connection. 
# run "nmake vio=1 kbd=1"  for a variant that uses low-level vio/kbd access.
#
# jwasm's option -pe cannot be used, since the DDB cannot be exported then;
# so jwlink is necessary ( it may create slightly larger binaries ).

!ifndef DEBUG
DEBUG=0
!endif

DEBUGRDIR=\projects\debug\build

!ifndef AUX
AUX=0
!endif
!ifndef VIO
VIO=0
!endif
!ifndef KBD
KBD=0
!endif
!ifndef KLANG
KLANG=US
!endif

!if $(AUX)
AOPT=-DAUXIO=1
srcdep=auxio.inc
!else
!if $(VIO)
AOPT=-DVIOOUT=1
srcdep=vioout.inc
!endif
!if $(KBD)
AOPT=$(AOPT) -DKBDIN=1 -DKEYS=KBD_$(KLANG)
srcdep=$(srcdev) kbdinp.inc
!endif
!endif

!if $(DEBUG)
AOPTD=-D_DEBUG
!else
AOPTD=
!endif

ALL: JemmDbg.exe JDbgBrk.exe

JemmDbg.exe: JemmDbg.obj jlstub.bin
	@jwlink format win pe hx dll ru native f JemmDbg.obj n JEMMDBG.EXE op q,m,stub=jlstub.bin export _ddb.1

JemmDbg.obj: JemmDbg.asm DebugR.bin $(srcdep)
	@jwasm -coff -nologo $(AOPT) $(AOPTD) -Fl -Sg -I..\..\Include JemmDbg.asm 

JDbgBrk.exe: JDbgBrk.asm jlstub.bin
!if 1
	@jwasm -nologo -coff -Fl -I..\..\Include JDbgBrk.asm 
	@jwlink format win pe hx ru native f JDbgBrk.obj n JDBGBRK.EXE op q,m,stub=jlstub.bin,stack=0x1000,heap=0x1000
!else
	@jwasm -nologo -pe -Fl -I..\..\Include JDbgBrk.asm 
	@pestub -n -s JDbgBrk.exe jlstub.bin
	@patchpe -x -y:1 -s:0x1000 -h:0x1000 JDbgBrk.exe
!endif

jlstub.bin: jlstub.asm
	@jwasm -nologo -mz -Fl -Fo=jlstub.bin jlstub.asm

DebugR.bin: $(DEBUGRDIR)\DebugR.bin
	@copy $(DEBUGRDIR)\DebugR.bin

clean:
	@del *.obj
	@del *.map
	@del *.lst
	@del *.bin
	@del *.exe
