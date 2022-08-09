
# NMake/WMake Makefile to create IOTRAP.DLL
#
#  tools                      alternatives
#----------------------------------------------------------
#  JWasm                      Masm v6.x
#  MS Link                    PoLink, WLink, ALink
#  PatchPE 
# 
# PatchPE: HX tool to patch a PE binary to PX

NAME = IOTRAP
OUTDIR=Release
AOPT=-c -coff -nologo -Fl$*.lst -Fo$*.obj -I..\..\Include
ASM=jwasm.exe
LINK=link.exe /NOLOGO /SUBSYSTEM:CONSOLE /DLL $*.obj /OUT:$*.DLL /MAP:$*.MAP /EXPORT:ddb /Entry:DllMain /OPT:NOWIN98
#LINK=polink /SUBSYSTEM:CONSOLE /DLL $*.obj /OUT:$*.DLL /MAP:$*.MAP /EXPORT:ddb
#LINK=wlink system nt_dll ru console file $*.obj name $*.DLL op MAP=$*.MAP export ddb.1

ALL: $(OUTDIR) $(OUTDIR)\$(NAME).DLL

$(OUTDIR):
	@mkdir $(OUTDIR)

$(OUTDIR)\$(NAME).DLL: $(OUTDIR)\$(NAME).obj Makefile
	@$(LINK)
	@..\patchpe $*.DLL

$(OUTDIR)\$(NAME).obj: $(NAME).asm
	@$(ASM) $(AOPT) $(NAME).asm
