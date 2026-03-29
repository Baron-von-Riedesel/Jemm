#
# To build Jemm386 and JemmEx on Linux, you will need:
#
# Tool
#---------------------------
# Assembler:   JWasm
# OMF Linker:  JWlink
# COFF Linker: JWlink
# Make:        GNU make
#
# since v5.87, JWasm must be v2.21+ (with fixed "negative offset"-bug)
#
# Important: all include files are referenced in the source with names
# in lowercase, but the corresponding file names are uppercase. To fix
# this either store the project on a FAT/NTFS file system, or create
# according symlinks!
#
# Jemm consists of 2 parts. which are created separately: the 32-bit
# part is the true Jemm application ( the "v86-monitor" program ) -
# its sources are assembled and linked to jemm32.bin. The 16-bit part
# is (mostly) used during the initialization phase and - except for a 
# small stub - not necessary to be kept in memory. As a result, the
# make process consists of:
#
#  1. assemble the 32-bit assembly sources.
#  2. link 32-bit modules to jemm32.bin (format is "raw").
#  3. assemble the 16-bit assembly sources; jemm32.bin will be included.
#  4. link 16-bit modules (JEMM16.obj, INIT16.obj) to Jemm386/JemmEx.
#
# To enable (selective) debug displays, enter:
#   make DEBUG=1 DBGOPT=-D?VCPIDBG=1
# This will enable VCPI related displays. For more switches, see DEBUG32.INC.

NAME1=JEMM386
NAME2=JEMMEX

ifndef DEBUG
DEBUG=0
endif

# to create kernel debugger aware versions, run "make KD=1"
ifndef KD
KD=0
endif

ASM=jwasm

ifeq ($(DEBUG),1)
AOPTD=-D_DEBUG $(DBGOPT) -Sg
else
AOPTD=
endif

# list of 32bit modules
COFFMODS=OUTD/JEMM32.obj OUTD/EMS.obj OUTD/VCPI.obj OUTD/DEV.obj \
 OUTD/XMS.obj OUTD/UMB.obj OUTD/VDMA.obj OUTD/I15.obj \
 OUTD/EMU.obj OUTD/VDS.obj OUTD/POOL.obj OUTD/INIT.obj \
 OUTD/DEBUG.obj

OMFMODS=OUTD/JEMM16.obj OUTD/INIT16.obj

BUILD=build

ifeq ($(DEBUG),1)
outd_suffix=D
else
outd_suffix=
endif

OUTD1=$(BUILD)/$(NAME1)$(outd_suffix)
OUTD2=$(BUILD)/$(NAME2)$(outd_suffix)
COFFDEP1=$(subst OUTD,$(OUTD1),$(COFFMODS))
COFFDEP2=$(subst OUTD,$(OUTD2),$(COFFMODS))
OMFDEP1=$(subst OUTD,$(OUTD1),$(OMFMODS))
OMFDEP2=$(subst OUTD,$(OUTD2),$(OMFMODS))
AOPT16=-c -nologo -omf

LOPT32=format raw bin name $@ disable 1014 op q, offs=0x110000, start=_start

32BITDEPS=src/JEMM.INC src/JEMM32.INC src/DEBUG32.INC src/EXTERN32.INC
16BITDEPS=src/JEMM.INC src/JEMM16.INC src/DEBUG16.INC

$(OUTD1)/%.obj: src/%.ASM
	@$(ASM) -c -nologo -coff -D?INTEGRATED=0 -D?KD=$(KD) $(AOPTD) -Fl$(OUTD1)/ -Fo$@ $<

$(OUTD2)/%.obj: src/%.ASM
	@$(ASM) -c -nologo -coff -D?INTEGRATED=1 -D?KD=$(KD) $(AOPTD) -Fl$(OUTD2)/ -Fo$@ $<

ALL: $(OUTD1) $(OUTD2) $(OUTD1)/$(NAME1).EXE $(OUTD2)/$(NAME2).EXE

$(OUTD1) $(OUTD2):
	@mkdir -p $@

$(OUTD1)/$(NAME1).EXE: $(OMFDEP1)
	@jwlink format dos file {$(OMFDEP1)} name $@ option q, m=$(OUTD1)/$(NAME1).map

$(OUTD2)/$(NAME2).EXE: $(OMFDEP2)
	@jwlink format dos file {$(OMFDEP2)} name $@ option q, m=$(OUTD2)/$(NAME2).map

$(OUTD1)/INIT16.obj: src/INIT16.ASM $(16BITDEPS) Linux.mak
	@$(ASM) $(AOPT16) -D?INTEGRATED=0 -D?KD=$(KD) $(AOPTD) -Sg -Fl$(OUTD1)/ -Fo$@ src/INIT16.ASM

$(OUTD2)/INIT16.obj: src/INIT16.ASM $(16BITDEPS) Linux.mak
	@$(ASM) $(AOPT16) -D?INTEGRATED=1 -D?KD=$(KD) $(AOPTD) -Sg -Fl$(OUTD2)/ -Fo$@ src/INIT16.ASM

$(OUTD1)/JEMM16.obj: src/JEMM16.ASM $(OUTD1)/jemm32.bin $(16BITDEPS) Linux.mak
	@$(ASM) $(AOPT16) -D?INTEGRATED=0 -D?KD=$(KD) $(AOPTD) -Sg -Fl$(OUTD1)/ -Fo$@ -I$(OUTD1) src/JEMM16.ASM

$(OUTD2)/JEMM16.obj: src/JEMM16.ASM $(OUTD2)/jemm32.bin $(16BITDEPS) Linux.mak
	@$(ASM) $(AOPT16) -D?INTEGRATED=1 -D?KD=$(KD) $(AOPTD) -Sg -Fl$(OUTD2)/ -Fo$@ -I$(OUTD2) src/JEMM16.ASM

$(OUTD1)/jemm32.bin: $(COFFDEP1)
	@jwlink $(LOPT32) file {$(COFFDEP1)} op map=$(OUTD1)/jemm32.map

$(OUTD2)/jemm32.bin: $(COFFDEP2)
	@jwlink $(LOPT32) file {$(COFFDEP2)} op map=$(OUTD2)/jemm32.map

$(COFFDEP1): $(32BITDEPS)

$(COFFDEP2): $(32BITDEPS)

clean:
	@rm $(OUTD1)/*.obj
	@rm $(OUTD1)/*.lst
	@rm $(OUTD1)/*.map
	@rm $(OUTD1)/$(NAME1).EXE
	@rm $(OUTD1)/jemm32.bin
	@rm $(OUTD2)/*.obj
	@rm $(OUTD2)/*.lst
	@rm $(OUTD2)/*.map
	@rm $(OUTD2)/$(NAME2).EXE
	@rm $(OUTD2)/jemm32.bin

