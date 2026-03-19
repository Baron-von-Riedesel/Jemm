
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
# the project on NTFS/FAT or rename the include files appropriately!

ifndef DEBUG
DEBUG = 0
endif

ifeq (1,$(DEBUG))
OUTD = DEBUG
AOPTD=-D_DEBUG -D?PEDBG=1 -D?RMDBG=1 -D?INITDBG=1 -D?JLMDBG=1
#AOPTD=-D_DEBUG -D?V86HOOKDBG=1
else
OUTD = RELEASE
AOPTD=
endif

NAME  = JLOAD
NAME32= JLOAD32
VXD1  = VMM
VXD4  = VDMAD
LIBS  = 

ASM   = jwasm -c -nologo -Fl$(OUTD)/ -Sg $(AOPTD) -I../../Include -I../../src -DOUTD=$(OUTD)
ASM32 = jwasm -c -nologo -Fl$(OUTD)/ -Sg $(AOPTD) -I../../Include -I../../src -DOUTD=$(OUTD)

LINK32=
INC32=jload.inc jload32.inc debug.inc ../../src/Jemm32.inc                    ../../Include/jlm.inc
INC16=jload.inc             debug.inc ../../src/Jemm32.inc ../../src/Jemm.inc ../../Include/jlm.inc

ALL: $(OUTD) $(OUTD)/$(NAME).EXE

$(OUTD):
	@mkdir -p $(OUTD)

$(OUTD)/$(NAME).EXE: $(OUTD)/$(NAME).obj Linux.mak
	@jwlink format dos file $(OUTD)/$(NAME).obj name $@ op q,m=$(OUTD)/$(NAME)

$(OUTD)/$(NAME).obj: $(NAME).ASM $(OUTD)/$(NAME32).bin $(INC16)
	@$(ASM) -omf -D__UNIX__ -Fo$@ $(NAME).ASM

$(OUTD)/$(NAME32).bin: $(OUTD)/$(NAME32).obj $(OUTD)/$(VXD1).obj $(OUTD)/$(VXD4).obj
	@jwlink format raw bin f { $(OUTD)/$(NAME32).obj $(OUTD)/$(VXD1).obj $(OUTD)/$(VXD4).obj } name $@ op q,map=$(OUTD)/$(NAME32),offset=0xF8400000,start=_start

$(OUTD)/$(NAME32).obj: $(NAME32).ASM $(INC32) Linux.mak
	@$(ASM32) -coff -Fo$@ $(NAME32).ASM

$(OUTD)/$(VXD1).obj: $(VXD1).ASM $(INC32) Linux.mak
	@$(ASM32) -coff -Fo$@ $(VXD1).ASM

$(OUTD)/$(VXD4).obj: $(VXD4).ASM $(INC32) Linux.mak
	@$(ASM32) -coff -Fo$@ $(VXD4).ASM

clean:
	@rm $(OUTD)/*.EXE
	@rm $(OUTD)/*.bin
	@rm $(OUTD)/*.obj
	@rm $(OUTD)/*.lst
	@rm $(OUTD)/*.map

