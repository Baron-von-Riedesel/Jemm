#
# builds JemmExL, the "legacy" variant of JemmEx, without support
# of XMS v3.5 ( super-extended memory )

NAME3=JEMMEXL

!ifndef DEBUG
DEBUG=0
!endif

# to create kernel debugger aware versions, add "kd=1" to nmake
!ifndef KD
KD=0
!endif

ASM=jwasm.exe

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

BUILD=build

!if $(DEBUG)
OUTD3=$(BUILD)\$(NAME3)D
COFFDEP3=$(COFFMODS:.\=build\JEMMEXLD\)
!else
OUTD3=$(BUILD)\$(NAME3)
COFFDEP3=$(COFFMODS:.\=build\JEMMEXL\)
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

{src\}.asm{$(OUTD3)}.obj:
	@$(ASM) -c -nologo -coff -D?INTEGRATED=1 -D?XMS35=0 $(AOPTD) -Fl$(OUTD3)\ -Fo$(OUTD3)\ $<

ALL: $(BUILD) $(OUTD3) $(OUTD3)\$(NAME3).EXE

$(BUILD) $(OUTD3):
	@mkdir $*

$(OUTD3)\$(NAME3).EXE: $(OUTD3)\jemm16.obj $(OUTD3)\init16.obj
	@cd $(OUTD3)
	@$(LINK16)
	@cd ..\..

$(OUTD3)\init16.obj: src\init16.asm src\jemm16.inc src\jemm.inc Makefile
	@$(ASM) -c -nologo -D?INTEGRATED=1 -D?XMS35=0 $(AOPTD) -Sg -Fl$(OUTD3)\ -Fo$(OUTD3)\ src\init16.asm

$(OUTD3)\jemm16.obj: src\jemm16.asm $(OUTD3)\jemm32.bin src\jemm.inc src\jemm16.inc src\debug.inc Makefile
	@cd $(OUTD3)
	@$(ASM) -c -nologo -D?INTEGRATED=1 -D?XMS35=0 $(AOPTD) -Fl ..\..\src\jemm16.asm
	@cd ..\..

$(OUTD3)\jemm32.bin: $(COFFDEP3)
	@cd $(OUTD3)
	@$(LINK32)
	@cd ..\..

$(COFFDEP3): $(32BITDEPS)

clean:
	@if exist $(OUTD3)\*.obj erase $(OUTD3)\*.obj
	@if exist $(OUTD3)\*.lst erase $(OUTD3)\*.lst
	@if exist $(OUTD3)\*.map erase $(OUTD3)\*.map
	@if exist $(OUTD3)\*.exe erase $(OUTD3)\*.exe
	@if exist $(OUTD3)\*.bin erase $(OUTD3)\*.bin
	@if exist $(OUTD3)\_jemm32.inc erase $(OUTD3)\_jemm32.inc

