#
# To build Jemm386 and JemmEx, you will need:
#
# Tool        Default (recommended) Alternatives
#-----------------------------------------------------------------
# Assembler   JWasm                 Masm v6.1 or better (+Bin2Inc)
# OMF Linker  JWlink                OW Wlink, MS Link (link16.exe)
# COFF Linker JWLINK                OW Wlink
# Make        MS Nmake              OW Wmake              
#
# note: OW Wmake must be used with the -ms option!
#
# note: WLink < v1.8 shouldn't be used as COFF linker. It contains a bug 
#       which might cause unexpected results in Jemm.
#
# Jemm consists of 2 parts. which are created separately: the 32-bit
# part is the true Jemm application ( the "v86-monitor" program ) -
# its sources are assembled and linked to Jemm32.bin. The 16-bit part
# is (mostly) used during the initialization phase and - except for a 
# small stub - not necessary to be kept in memory. As a result, the
# make process consists of:
#
#  1. assemble the 32-bit assembly sources
#  2. link 32-bit modules to Jemm32.bin (format is "raw").
#  3. assemble the 16-bit assembly sources; Jemm32.bin will be included,
#     either directly ( JWasm ) or indirectly via tool Bin2Inc ( Masm );
#     Bin2Inc can be found in the JWasm package.
#  4. link 16-bit modules (Jemm16.obj, Init16.obj) to Jemm386/JemmEx
#
# To enable (selective) debug displays, enter:
#   nmake debug=1 dbgopt=-D?VCPIDBG=1
# This will enable VCPI related displays. For more switches, see DEBUG.INC.

NAME1=JEMM386
NAME2=JEMMEX
NAME3=JEMMEXL

!ifndef DEBUG
DEBUG=0
!endif

# to create kernel debugger aware versions, run "nmake kd=1"
!ifndef KD
KD=0
!endif

# select assembler, JWasm or Masm, default is JWasm
!ifndef MASM
MASM=0
!endif

!if $(MASM)
ASM=ml.exe  
!else
ASM=jwasm.exe
!endif

# select 32-bit COFF linker, default JWLink

!ifndef JWLINK32
JWLINK32=0
!endif
!ifndef WLINK32
WLINK32=0
!endif
!ifndef MSLINK32
MSLINK32=0
!endif
!if $(JWLINK32)+$(WLINK32)+$(MSLINK32)==0
JWLINK32=1
!endif

# select 16-bit OMF linker, default JWLink

!ifndef JWLINK
JWLINK=0
!endif
!ifndef WLINK
WLINK=0
!endif
!ifndef MSLINK
MSLINK=0
!endif
!if $(JWLINK)+$(WLINK)+$(MSLINK)==0
JWLINK=1
!endif

!if $(DEBUG)
AOPTD=-D_DEBUG $(DBGOPT) -Sg
!else
AOPTD=
!endif

# list of 32bit modules
COFFMODS=.\jemm32.obj .\ems.obj .\vcpi.obj .\dev.obj .\xms.obj .\umb.obj .\vdma.obj .\i15.obj .\emu.obj .\vds.obj .\pool.obj .\init.obj .\debug.obj

!if $(DEBUG)
OUTD1=build\$(NAME1)D
OUTD2=build\$(NAME2)D
COFFDEP1=$(COFFMODS:.\=build\JEMM386D\)
COFFDEP2=$(COFFMODS:.\=build\JEMMEXD\)
!else
OUTD1=build\$(NAME1)
OUTD2=build\$(NAME2)
COFFDEP1=$(COFFMODS:.\=build\JEMM386\)
COFFDEP2=$(COFFMODS:.\=build\JEMMEX\)
!endif


!if $(JWLINK32)
LINK32=jwlink format raw bin file {$(COFFMODS:.\=)} name jemm32.bin option offs=0x110000, start=_start, map=jemm32.map, quiet
!elseif $(WLINK32)
LINK32= wlink format raw bin file {$(COFFMODS:.\=)} name jemm32.bin option offs=0x110000, start=_start, map=jemm32.map, quiet
!else
COFFOPT=/fixed /driver /subsystem:native /entry:start /base:0x100000 /align:0x10000 /MAP /nologo
# MS link (newer versions won't accept option FILEALIGN anymore)
LINK32=link.exe /FileAlign:0x200 $(COFFOPT) $(COFFMODS:.\=) /OUT:jemm32.bin 
!endif

!if $(JWLINK)
LINK16=jwlink.exe format dos file jemm16.obj,init16.obj name $(*B).EXE option map=$(*B).MAP, quiet
!elseif $(WLINK)
LINK16=wlink.exe format dos file jemm16.obj,init16.obj name $@.EXE option map=$@.MAP, quiet
#else
LINK16=link16.exe /NOLOGO/MAP:FULL/NOD /NOI jemm16.obj init16.obj,$@.EXE,$@.MAP;
!endif

32BITDEPS=src\jemm32.inc src\jemm.inc src\external.inc src\debug.inc Makefile

{src\}.asm{$(OUTD1)}.obj:
	@$(ASM) -c -nologo -coff -D?INTEGRATED=0 -D?KD=$(KD) $(AOPTD) -Fl$(OUTD1)\ -Fo$(OUTD1)\ $<

{src\}.asm{$(OUTD2)}.obj:
	@$(ASM) -c -nologo -coff -D?SAFEKBD=1 -D?INTEGRATED=1 -D?KD=$(KD) $(AOPTD) -Fl$(OUTD2)\ -Fo$(OUTD2)\ $<

ALL: $(OUTD1) $(OUTD2) $(OUTD1)\$(NAME1).EXE $(OUTD2)\$(NAME2).EXE

$(OUTD1):
	@mkdir $(OUTD1)

$(OUTD2):
	@mkdir $(OUTD2)

$(OUTD1)\$(NAME1).EXE: $(OUTD1)\jemm16.obj $(OUTD1)\init16.obj
	cd $(OUTD1)
	@$(LINK16)
	cd ..\..

$(OUTD2)\$(NAME2).EXE: $(OUTD2)\jemm16.obj $(OUTD2)\init16.obj
	cd $(OUTD2)
	@$(LINK16)
	cd ..\..

$(OUTD1)\init16.obj: src\init16.asm src\jemm16.inc src\jemm.inc Makefile
	@$(ASM) -c -nologo -D?INTEGRATED=0 -D?KD=$(KD) $(AOPTD) -Sg -Fl$(OUTD1)\ -Fo$(OUTD1)\ src\init16.asm

$(OUTD2)\init16.obj: src\init16.asm src\jemm16.inc src\jemm.inc Makefile
	@$(ASM) -c -nologo -D?INTEGRATED=1 -D?KD=$(KD) $(AOPTD) -Sg -Fl$(OUTD2)\ -Fo$(OUTD2)\ src\init16.asm

!if $(MASM)
$(OUTD1)\jemm16.obj: src\jemm16.asm $(OUTD1)\_jemm32.inc src\jemm.inc src\jemm16.inc src\debug.inc Makefile
	@$(ASM) -c -nologo -D?INTEGRATED=0 -D?KD=$(KD) $(AOPTD) -Fl$(OUTD1)\ -Fo$(OUTD1)\ -I$(OUTD1) src\jemm16.asm

$(OUTD2)\jemm16.obj: src\jemm16.asm $(OUTD2)\_jemm32.inc src\jemm.inc src\jemm16.inc src\debug.inc Makefile
	@$(ASM) -c -nologo -D?INTEGRATED=1 -D?KD=$(KD) $(AOPTD) -Fl$(OUTD2)\ -Fo$(OUTD2)\ -I$(OUTD2) src\jemm16.asm

$(OUTD1)\_jemm32.inc: $(OUTD1)\jemm32.bin
	@bin2inc.exe -q $(OUTD1)\jemm32.bin $(OUTD1)\_jemm32.inc

$(OUTD2)\_jemm32.inc: $(OUTD2)\jemm32.bin
	@bin2inc.exe -q $(OUTD2)\jemm32.bin $(OUTD2)\_jemm32.inc

!else
$(OUTD1)\jemm16.obj: src\jemm16.asm $(OUTD1)\jemm32.bin src\jemm.inc src\jemm16.inc src\debug.inc Makefile
	@$(ASM) -c -nologo -D?INTEGRATED=0 -D?KD=$(KD) $(AOPTD) -Fl$(OUTD1)\ -Fo$(OUTD1)\ -I$(OUTD1) src\jemm16.asm

$(OUTD2)\jemm16.obj: src\jemm16.asm $(OUTD2)\jemm32.bin src\jemm.inc src\jemm16.inc src\debug.inc Makefile
	$(ASM) -c -nologo -D?INTEGRATED=1 -D?KD=$(KD) $(AOPTD) -Sg -Fl$(OUTD2)\ -Fo$(OUTD2)\ -I$(OUTD2) src\jemm16.asm

!endif

$(OUTD1)\jemm32.bin: $(COFFDEP1)
	cd $(OUTD1)
	@$(LINK32)
	cd ..\..

$(OUTD2)\jemm32.bin: $(COFFDEP2)
	cd $(OUTD2)
	@$(LINK32)
	cd ..\..

$(COFFDEP1): $(32BITDEPS)

$(COFFDEP2): $(32BITDEPS)

clean:
	@if exist $(OUTD1)\*.obj erase $(OUTD1)\*.obj
	@if exist $(OUTD1)\*.lst erase $(OUTD1)\*.lst
	@if exist $(OUTD1)\*.map erase $(OUTD1)\*.map
	@if exist $(OUTD1)\*.exe erase $(OUTD1)\*.exe
	@if exist $(OUTD1)\*.bin erase $(OUTD1)\*.bin
	@if exist $(OUTD1)\_jemm32.inc erase $(OUTD1)\_jemm32.inc
	@if exist $(OUTD2)\*.obj erase $(OUTD2)\*.obj
	@if exist $(OUTD2)\*.lst erase $(OUTD2)\*.lst
	@if exist $(OUTD2)\*.map erase $(OUTD2)\*.map
	@if exist $(OUTD2)\*.exe erase $(OUTD2)\*.exe
	@if exist $(OUTD2)\*.bin erase $(OUTD2)\*.bin
	@if exist $(OUTD2)\_jemm32.inc erase $(OUTD2)\_jemm32.inc
