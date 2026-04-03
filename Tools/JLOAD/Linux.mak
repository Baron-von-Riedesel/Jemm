
# makefile that creates JLOAD.EXE
# tools used:
#------------------------
# Assembler:    jwasm
# OMF linker:   jwlink
# COFF linker:  jwlink

# the 32-bit part of jload must be linked with base 0xF8400000;
#
# The source files contain include files references in lower case,
# but the name of the files are in upper case. So either store
# the project on NTFS/FAT or create appropriate symlinks!

ifndef DEBUG
DEBUG = 0
endif

ifeq (1,$(DEBUG))
OUTD = DEBUG
AOPTD=-Sg -D_DEBUG -D?PEDBG=1 -D?RMDBG=1 -D?INITDBG=1 -D?JLMDBG=1
#AOPTD=-Sg -D_DEBUG -D?V86HOOKDBG=1
else
OUTD = RELEASE
AOPTD=
endif

NAME  = JLOAD
NAME32= JLOAD32
VXD1  = VMM
VXD4  = VDMAD

ASM   = jwasm -c -nologo $(AOPTD) -I../../Include -DOUTD=$(OUTD)

LINK32=
INC32=JLOAD.INC JLOAD32.INC DEBUG.INC ../../Include/JSYSTEM.INC ../../Include/JLM.INC
INC16=JLOAD.INC             DEBUG.INC ../../Include/JSYSTEM.INC ../../Include/JLM.INC

ALL: $(OUTD) $(OUTD)/$(NAME).EXE

$(OUTD):
	@mkdir -p $(OUTD)

$(OUTD)/$(NAME).EXE: $(OUTD)/$(NAME).obj Linux.mak
	@jwlink format dos file $(OUTD)/$(NAME).obj name $@ op q,m=$(OUTD)/$(NAME)

$(OUTD)/$(NAME).obj: $(NAME).ASM $(OUTD)/$(NAME32).bin $(INC16)
	@$(ASM) -omf -D__UNIX__ -Fl$(OUTD)/ -Fo$@ $(NAME).ASM

$(OUTD)/$(NAME32).bin: $(OUTD)/$(NAME32).obj $(OUTD)/$(VXD1).obj $(OUTD)/$(VXD4).obj
	@jwlink format raw bin f { $(OUTD)/$(NAME32).obj $(OUTD)/$(VXD1).obj $(OUTD)/$(VXD4).obj } name $@ disable 1014 op q,map=$(OUTD)/$(NAME32),offset=0xF8400000,start=_start

$(OUTD)/$(NAME32).obj: $(NAME32).ASM $(INC32) Linux.mak
	@$(ASM) -coff -Fl$(OUTD)/ -Fo$@ $(NAME32).ASM

$(OUTD)/$(VXD1).obj: $(VXD1).ASM $(INC32) Linux.mak
	@$(ASM) -coff -Fl$(OUTD)/ -Fo$@ $(VXD1).ASM

$(OUTD)/$(VXD4).obj: $(VXD4).ASM $(INC32) Linux.mak
	@$(ASM) -coff -Fl$(OUTD)/ -Fo$@ $(VXD4).ASM

clean:
	@rm $(OUTD)/*.EXE
	@rm $(OUTD)/*.bin
	@rm $(OUTD)/*.obj
	@rm $(OUTD)/*.lst
	@rm $(OUTD)/*.map

