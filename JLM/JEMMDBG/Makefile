
# create JemmDbg.exe
# tools used: jwasm & jwlink & nmake (from MS MS-DOS 4.0 sources)
# needs Debug/X's DebugR/DebugRV variants ( see DEBUGRDIR below ).

# video and keyboard i/O may be selected by:
# run "nmake vio=1"        for a variant that uses low-level vio output.
# run "nmake kbd=1"        for a variant that uses low-level kbd access.

# kbd=1 needs a language ( US and GR are supplied ):
# run "nmake kbd=1 klang=gr" ; for low-level kbd access, German translation.

# to select DebugR (non v86-mode variant) instead of DebugRV:
# run "nmake v86=0"

# jwasm's option -pe cannot be used, since the DDB cannot be exported then;
# so jwlink is necessary ( it may create slightly larger binaries ).

!ifndef DEBUG
DEBUG=0
!endif

!ifndef V86
V86=1
!endif

!if $(V86)
DEBUGR=DebugRV.bin
!else
DEBUGR=DebugR.bin
!endif

DEBUGRDIR=\projects\debug\build

!ifndef AUX
AUX=1
!endif
!ifndef VIO
VIO=1
!endif
!ifndef KBD
KBD=1
!endif
!ifndef KLANG
KLANG=GR
!endif

!if $(AUX)
AOPT=-DAUXIO=1
srcdep=$(srcdep) auxio.inc
!else
AOPT=-DAUXIO=0
!endif

!if $(VIO)
AOPT=-DVIOOUT=1
srcdep=$(srcdep) vioout.inc
!endif
!if $(KBD)
AOPT=$(AOPT) -DKBDIN=1 -DKEYS=KBD_$(KLANG)
srcdep=$(srcdep) kbdinp.inc
!endif

!if $(DEBUG)
AOPTD=-D_DEBUG
srcdep=$(srcdep) dprintf.inc
!else
AOPTD=
!endif

OUTD=Build

ALL: $(OUTD) $(OUTD)\JemmDbg.exe

$(OUTD):
	@if not exist $(OUTD)\NUL @mkdir $(OUTD)

$(OUTD)\JemmDbg.exe: $(OUTD)\JemmDbg.obj $(OUTD)\jlstub.bin
	@jwlinkd.exe @jemmdbg.lnk

$(OUTD)\JemmDbg.obj: JemmDbg.asm $(OUTD)\$(DEBUGR) $(srcdep)
	@jwasmd.exe -coff -nologo -DV86=$(V86) $(AOPT) $(AOPTD) -Fl$(OUTD)\ -Fo$(OUTD)\ -Sg -I..\..\Include JemmDbg.asm 

$(OUTD)\jlstub.bin: ..\JLSTUB\Build\JLSTUB.BIN
	@copy ..\JLSTUB\Build\JLSTUB.BIN $(OUTD)\

$(OUTD)\$(DEBUGR): $(DEBUGRDIR)\$(DEBUGR)
	@copy $(DEBUGRDIR)\$(DEBUGR) $(OUTD)\

clean:
	@del $(OUTD)\*.exe
	@del $(OUTD)\*.bin
	@del $(OUTD)\*.lst
	@del $(OUTD)\*.map
	@del $(OUTD)\*.obj
