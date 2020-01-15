
;--- 16-bit initialization part
;--- to be assembled with JWasm or Masm v6.1+

	.MODEL SMALL
	.386
	option casemap:none
	option proc:private

CStr macro text:VARARG
local sym
	.const
sym db text,0
	.code
	exitm <offset sym>
	endm

FALSE equ 0
TRUE equ 1
NULL equ 0

?USEMEMSET equ 0

	include jemm.inc
	include jemm16.inc
	include debug.inc

NAMEGEN equ <"Jemm">

MAX_EMS_PAGES_ALLOWED equ 800h

PF16 TYPEDEF far16 ptr

ife ?INTEGRATED
REGS struct
union
struct
_eax  dd ?
_ebx  dd ?
_ecx  dd ?
_edx  dd ?
ends
struct
_ax  dw ?,?
_bx  dw ?,?
_cx  dw ?,?
_dx  dw ?,?
ends
ends
REGS ends
endif

	.data

jemmini JEMMINIT <>
XMSdriverAddress PF16 0
dwAllocatedBytes	DD 0;set by AllocAndInitMem()
xms_mem_largest	DD 0	;largest free block in kB
xms_mem_free	DD 0	;total free mem in kB

bVerbose	DB 0
if ?LOAD
bLoad	DB 0
endif
if ?INTEGRATED
xms_max	DD 4095*1024	;MAXEXT= value
xms_num_handles	DW 32	;XMSHANDLES= value
bNoE820	DB 0
bNoE801	DB 0
endif
bI15RsvdChk db 0

if ?INTEGRATED eq 0
xmsspec3	DW 0
endif
bFrameWanted DB 0   ;FRAME=XX00
ExcludeTest	DB 0	;X=TEST
IncludeTest	DB 0	;I=TEST
if ?SPLIT
SplitTest	DB 0
endif
MinRequest	DB 0	;MIN= has been found

	.const

if ?INTEGRATED

ENABLE_A20 equ 2
DISABLE_A20 equ 0

a20_methods label byte
	db 3,"kbc"		;0 (A20_KBC)
	db 3,"ps2"		;1 (A20_PS2)
	db 4,"bios" 	;2
	db 8,"alwayson" ;3
	db 4,"fast" 	;4
	db 6,"port92"	;5
	db 0

szKBC   db "KBC",0
szPS2   db "PS/2",0
szBIOS  db "BIOS",0
szAlwaysOn db "Always On",0
szFast  db "Fast",0
szPort92 db "Port 92",0

	even

;--- table order must match A20_ switch methods constants
A20procs label word
	dw disable_enable_a20_KBC	;A20_KBC
	dw disable_enable_a20_fast	;A20_PS2
	dw disable_enable_a20_BIOS	;A20_BIOS
	dw disable_enable_a20_dummy	;A20_ALWAYSON
	dw disable_enable_a20_fast	;A20_FAST
	dw disable_enable_a20_fast	;A20_PORT92

A20strings label word
	dw szKBC
	dw szPS2
	dw szBIOS
	dw szAlwaysOn
	dw szFast
	dw szPort92

endif

sig1        db 'EMMXXXX0',0
sig2        db 'EMMQXXX0',0 ; ID if NOEMS specified

szError		DB 'Error',  07H, 0
szWarning	DB 'Warning', 0
szOn		DB "On",0
szOff		DB "Off",0
szStartup	DB NAMEMOD, " v", @CatStr(!",%?VERSIONHIGH,!"), ".", @CatStr(!",%?VERSIONLOW,!")," [", @CatStr(!",%@Date,!"), "]", LF, 0
szCopyRight	DB NAMEMOD, '. Parts (c) tom ehlert 2001-2006 c''t/H. Albrecht 1990', LF, 0

szHelp label byte
	db "usage: either add a line to CONFIG.SYS: DEVICE=",NAMEEXE,".EXE [ options ]",LF
	db " or run it from the command line: C:\>",NAMEEXE," [ options ]",LF
	db "available options are:",LF
if ?A20XMS or ?A20PORTS
	db "+A20/NOA20     A20-disable emulation on/off (default on)",LF
endif
if ?INTEGRATED
	db " A20METHOD:m   set A20 switch method. Possible values for <m> are",LF
	db "               KBC, PS2, BIOS, FAST, PORT92 and ALWAYSON.",LF
endif
	db " ALTBOOT       use alternate reboot strategy", LF
	db " B=segm        specify lowest segment address for EMS banking (default=4000)",LF
	db " D=n           set DMA buffer size in kB (default=64, max is 128)",LF
if ?EMX
	db " EMX           increased EMX DOS extender compatibility",LF
endif
if ?FASTBOOT
	db " FASTBOOT      fast reboot. Requires ",NAMEMOD," to be loaded in CONFIG.SYS.",LF
endif
	db " FRAME=E000    set EMS page frame (FRAME=NONE disables frame). Any value",LF
	db "               between 8000 and E000 is accepted, but not all will work.",LF
if ?INTEGRATED
	db " HMAMIN=n      set minimum amount in Kb to allocate the HMA.",LF
endif
    db " I=start-end   force a region to be used for UMBs. Without this option",LF
    db "               range C000-EFFF is scanned for unused pages. May also be used",LF
    db "               to add (parts of) regions A000-BFFF or F000-F7FF as UMBs. Don't",LF
    db "               use this option if you don't know what you are doing!",LF
    db " I=TEST        scan ROMs for unused pages, include found regions as UMBs",LF
    db " [MAX=]n       limit for VCPI (and EMS if < 32M) memory in kB (default 120 MB)",LF
if ?INTEGRATED
    db " MAXEXT=n      limit extended memory usage to <n> kB",LF
endif
    db " MIN=n         reserve up to <n> kB for EMS/VCPI memory on init (default=0)",LF
    db " NOCHECK       disallow access to address space without RAM (MMIO)",LF
if ?INTEGRATED
    db " NOE801        don't use Int 15h, E801h to get amount of ext. memory",LF
    db " NOE820        don't use Int 15h, E820h to get amount of ext. memory",LF
endif
    db " NOEMS         disable EMS handling",LF
    db " NODYN         no dynamic XMS memory allocation (use MIN= to set fix amount)",LF
    db " NOHI          don't move resident part into first UMB",LF
    db " NOINVLPG      don't use INVLPG opcode",LF
if ?PGE
    db "+PGE/NOPGE     Page Global Enable feature usage on/off (default off)",LF
endif
    db " RAM/NORAM     try to supply UMBs on/off (default on)",LF
    db " S=start-end   assume Shadow-RAM activated by UMBPCI, include it as UMB",LF
if ?SB
    db " SB            SoundBlaster driver compatibility mode",LF
endif
if ?SPLIT
    db " SPLIT         regain partially used EPROM 4k pages for UMBs",LF
endif
    db "+VCPI/NOVCPI   VCPI Support on/off (default on)",LF
    db " VDS/NOVDS     Virtual DMA Services on/off (default on)",LF
if ?VME
    db "+VME/NOVME     V86-Mode Extensions on/off (default off)",LF
endif
    db " VERBOSE       display additional details during start (abbr: /V)",LF
    db " X=start-end   exclude region from being touched or used by ",NAMEMOD,LF
    db " X=TEST        scan memory region C000-EFFF for UMB exclusion",LF
if ?INTEGRATED
    db " X2MAX=n       max. value in Kb for XMS V2 free memory report (default=65535)",LF
    db " XMSHANDLES=n  number of available XMS handles (8<=n<=128, default=32)",LF
endif
    db LF
    db " '+': option can be set dynamically by running ",NAMEMOD," from the command line",LF
if ?LOAD
    db LF
    db "When invoked from the command line ",NAMEMOD," additionally will understand:",LF
    db " LOAD          install",LF
endif
if ?UNLOAD
    db " UNLOAD        uninstall",LF
endif
    db 0

	.data?

if ?INTEGRATED eq 0
xmsreg REGS <>
endif

;--- 256 entries for real-mode pages [00-FF]xxxh
;    'R' = RAM
;    'E' = EPROM
;    'S' = Shadow-RAM activated by UMBPCI
;    'G' = GRAPHICS region
;    'V' = VMWARE allocated, but possibly re-usable via I= (0e800-0ebffh)
;
;    'U' = possible UMB space, because nothing else found
;    'P' = PAGEFRAME
;    'I' = INCLUDE = forced from commandline
;    'X' = EXCLUDE = forbidden from commandline

SystemMemory DB 100H DUP (?)

	.code

strlen proc c uses di string:ptr BYTE

	mov cx,-1
	mov di,string
	push ds
	pop es
	mov al,0
	cld
	repnz scasb
	mov ax,cx
	inc ax
	not ax
	ret

strlen endp

handle_char proc

	mov dl,al
	cmp al,10
	jnz @F
	mov dl,13
	call @F
	mov dl,10
@@:
	mov ah,2
	int 21h
	ret

handle_char endp

;--- ltob(long n, char * s, int base);
;--- convert long to string

ltob PROC stdcall uses edi number:dword, outb:word, base:word

	mov ch,0
	movzx edi, base
	mov eax, number
	cmp di,-10
	jne @F
	mov di,10
	and eax,eax
	jns @F
	neg eax
	mov ch,'-'
@@:
	mov bx,outb
	add bx,10
	mov BYTE PTR [bx],0
	dec bx
@@nextdigit:
	xor edx, edx
	div edi
	add dl,'0'
	cmp dl,'9'
	jbe @F
	add dl,7+20h
@@:
	mov [bx],dl
	dec bx
	and eax, eax
	jne @@nextdigit
	cmp ch,0
	je @F
	mov [bx],ch
	dec bx
@@:
	inc bx
	mov ax,bx
	ret

ltob ENDP

;--- little printf() implementation.
;--- understands type %c, %x, %d, %i, u%, %s 
;--- and modifier l(ong)

printf PROC c uses si di fmt:ptr byte, args:VARARG

local size_:word
local flag:byte
local longarg:byte
local fill:byte
local szTmp[12]:byte

	push ds
	pop es
	lea di,[fmt+2]
@@L335:
	mov si,[fmt]
nextchar:
	lodsb
	or al,al
	je done
	cmp al,'%'
	je formatitem
	call handle_char
	jmp nextchar
done:
	xor ax,ax
	ret
formatitem:
	xor dx,dx
	mov [longarg],dl
	mov bl,1
	mov cl,' '
	cmp BYTE PTR [si],'-'
	jne @F
	dec bx
	inc si
@@:
	mov [flag],bl
	cmp BYTE PTR [si],'0'
	jne @F
	mov cl,'0'
	inc si
@@:
	mov [fill],cl
	mov [size_],dx
	mov bx,dx
	jmp @@L358
@@FC250:
	cmp BYTE PTR [si],'9'
	jg	@@L362
	lodsb
	sub al,'0'
	cbw
	imul cx,bx,10		;cx = bx * 10
	add ax,cx
	mov bx,ax
@@L358:
	cmp BYTE PTR [si],'0'
	jge @@FC250
@@L362:
	mov [size_],bx
	cmp BYTE PTR [si],'l'
	jne @F
	mov [longarg],1
	inc si
@@:
	lodsb
	mov [fmt],si
	cbw
	cmp al,'x'
	je handle_x
	ja @@L359
	or al,al
	je done 	;\0?
	sub al,'X'
	je handle_x
	sub al,11
	je handle_c	;'c'
	dec al
	je handle_d	;'d'
	sub al,5
	je handle_i	;'i'
	sub al,10
	je handle_s	;'s'
	sub al,2
	je handle_u	;'u'
	jmp @@L359
handle_c:				;'c'
	mov ax,[di]
	add di,2
@@L359:
	call handle_char
	jmp @@L335

handle_s:				;'s'
	mov si,[di]
	add di,2
	jmp @@do_outputstring260

handle_x:				;'X' + 'x'
	mov bx,16
	jmp @@lprt262
handle_d:				;'d'
handle_i:				;'i'
	mov bx,-10
	jmp @@lprt262
handle_u:				;'u'
	mov bx,10
@@lprt262:
	mov ax,[di]
	add di,2
	sub dx,dx
	cmp bx,0		;signed or unsigned?
	jge @F
	cwd
@@:
	cmp [longarg],0
	je @F
	mov dx,[di]
	add di,2
@@:
	lea cx,[szTmp]
	invoke ltob, dx::ax, cx, bx
	mov si,ax
@@do_outputstring260:
	invoke strlen, si
	sub [size_],ax
	cmp BYTE PTR [flag],1
	jne @@L360
	mov bx,[size_]
	jmp @@L363
@@F270:
	mov al,[fill]
	call handle_char
	dec bx
@@L363:
	or bx,bx
	jg @@F270
	mov [size_],bx
	jmp @@L360

@@F273:
	mov al,[si]
	call handle_char
	inc si
@@L360:
	cmp BYTE PTR [si],0
	jne @@F273
	mov bx,[size_]
@@:
	or bx,bx
	jle @@L335
	mov al,[fill]
	call handle_char
	dec bx
	jmp @B

printf ENDP

if 0
memcpy proc c uses si di dst:ptr byte, src:ptr byte, len:word
	push ds
	pop es
	mov di,dst
	mov si,src
	mov cx,len
	rep movsb
	ret
memcpy endp
endif

if ?USEMEMSET
memset proc c uses di dest:ptr BYTE, value:WORD, len:WORD

	push ds
	pop es
	mov di,dest
	mov ax,value
	mov cx,len
	rep stosb
	ret

memset endp
endif

_memicmp proc c uses si di p1:ptr BYTE, p2:ptr BYTE, len:WORD

	mov cx,len
	mov si,p2
	mov di,p1
nextitem:
	lodsb
	mov ah,[di]
	inc di
	or al,20h
	or ah,20h
	sub al,ah
	loopz nextitem
	cbw
	ret

_memicmp endp

skipWhite PROC c src:ptr byte

	mov bx,src
nextitem:
	mov al,[bx]
	inc bx
	cmp al,' '
	je nextitem
	cmp al,9
	je nextitem
	dec bx
	mov ax,bx
	ret

skipWhite ENDP

;--- set memory type , but honour "EXCLUDE=" and "INCLUDE=" types
;--- address: paragraph

SetMemoryType PROC stdcall uses si address:word, mtype:byte

	mov si,address
	shr si,8
	add si,OFFSET SystemMemory
	mov al,mtype
	.if byte ptr [si] != 'I' || al == 'X'
		mov [si],al
	.endif
	ret

SetMemoryType ENDP

;--- TestForSystemRAM(void *, int, int *);
;--- 1. argument is "SystemMemory" array (256 * BYTE)
;--- 2. argument is index for "SystemMemory" where to start scan
;--- 3. argument is a pointer to WORD
;--- may change memory type from 'U' to 'R'

TestForSystemRAM proc c uses si di pv:ptr BYTE, index:WORD, pi:ptr WORD

local result:word

	xor di, di			;init return code
	mov result,di
	mov si, pv
	mov dx, index
	add si, dx
	mov cx, 100h
	sub cx, dx
	jbe @@done
@@nextpage:
	lodsb
	cmp al,'U'
	jz @F
	cmp al,'I'			;'I' is also tested, but not modified
	jnz @@skipitem		;so a warning can be displayed 
@@:
;--- test a page of conventional memory
	mov ax, dx
	shl ax, 8
	mov es, ax
	cli
	mov ax, es:[0]
	mov bx, ax
	xor ax, 055AAh
	mov es:[0], ax
	cmp ax, es:[0]
	jnz @@noram
	xor ax, 0AA55h
	mov es:[0], ax
	cmp ax, es:[0]
	jnz @@noram
	
	cmp byte ptr [si-1], 'U'
	jnz @F
	mov byte ptr [si-1], 'R'
@@:
	and di, di
	jnz @F
	mov di, es
@@:
	add result, 100h	;100h = 4kB in paragraphs
	jmp @@shared

@@noram:
	and di, di
	jz @@shared 	;skip test now, found a region
	mov cx,1		;stop scanning
@@shared:
	cmp bx, es:[0]
	jz @F
	mov es:[0],bx
@@:
	sti

@@skipitem:
	inc dx
	loop @@nextpage
@@done:
	mov bx, pi
	mov ax, result
	mov [bx], ax
	mov ax, di
	ret

TestForSystemRAM endp

;    ScanSystemMemory()
;    search memory for ROMS, adapters, graphics,...
;
;    builds SystemMemory map
;
;    the "checks" which are done are:
;
;    - memory range C000-EFFF is scanned for ROMs,
;      if one is found, and "I=TEST", it is checked if there are pages
;      filled with 0x00 or 0xFF.
;    - with option "X=TEST", memory range C000-EFFF is also tested if
;      content is 0x00 or 0xFF, anything else excludes page
;    - memory range C000-EFFF is also checked for RAM. if found pages are
;      regarded as "reserved" (must be explicitely included with I= or S=)

ScanSystemMemory PROC uses si di

local blksiz:word
local i:word
local romsize:word
local mem:word

;--- check for ROMs (should find VGA-Roms)
;--- also handles I=TEST
	mov mem,0c000h
	.repeat
		mov es,mem
		xor si, si
		.if ( word ptr es:[si] == 0AA55h )
			mov al, es:[si+2]
			sub ah,ah
			mov di,ax
			and ax,1
			cmp ax,1
			cmc
			sbb cx,cx
			and cx,5
			.if bVerbose
				mov ax,di
				shr ax,1
				invoke printf, CStr("EPROM at %X, size %u.%u kB", LF), es, ax, cx
			.endif
			mov i,di
			mov si,mem
			mov romsize,di

			.while i
				mov di, 200H
				mov bx,si
				mov bl,bh
				sub bh,bh
				.if SystemMemory[bx] != 'X'
					mov ax, i
					mov cx, si
					.if ( cl == 0 || ax == romsize )
						invoke SetMemoryType, si, 'E'
						mov cx, si
						.if IncludeTest && cl == 0
							mov di, 1000H
							.if WORD PTR i <= 7
								mov di,i
								shl di,9
							.endif
							mov blksiz,di
							mov es,si
							mov bx,0
							mov ah,es:[bx]
							inc bx
							.while bx < di
								.break .if al != es:[bx]
								inc bx
							.endw
							.if bx == di
								invoke SetMemoryType, si, 'I'
							.endif
						.endif
					.endif
				.endif
				mov ax,di
				shr di,4
				add si,di
				shr ax,9
				sub i,ax
			.endw

			mov ax,si
			mov bx,si
			mov bl,bh
			sub bh,bh
			.if SplitTest && al && SystemMemory[bx] == 'E'
				shr al,5
				add al,'0'
				invoke SetMemoryType, si, al
			.endif
			mov ax, romsize
			shl ax,5
			add ax, mem
			add ax, 07fh
			and al, 080h
			mov mem,ax
			.continue
		.endif
		add	mem,0080H	;add 128 paragraphs (=2 kB)
	.until mem >= 0F000h

if 1;?INTEGRATED
;--- don't scan for RAM if we called Int 15h ax=e820h
	cmp bI15RsvdChk,0
	jnz @F
endif

	mov si, 0C0h
	.repeat
		lea ax, mem
		invoke TestForSystemRAM, OFFSET SystemMemory, si, ax
		mov si,ax
		.if ax
			mov ax,mem
			add ax,si
			dec ax
			invoke printf,CStr("System memory found at %X-%X, region might be in use", LF), si, ax
			mov ax,mem
			add ax,si
			mov al,ah
			sub ah,ah
			mov si,ax
		.endif
	.until si == 0
@@:

;--- X=TEST ?
	.if ExcludeTest
		mov mem, 0a0H
		.while mem < 0f0H
			mov bx, mem
			.if SystemMemory[bx] == 'U'
				mov ah,BYTE PTR mem
				sub al,al
				mov es,ax
				sub cx,cx
				mov si,cx
				.while cx < 0fffH	;don't check the page's final byte!
					mov al, es:[si]
					.if al != 0 && al != 0ffh
						mov bx, mem
						mov SystemMemory[bx],'X'
						.break
					.endif
					inc cx
					inc si
				.endw
			.endif
			inc mem
		.endw
	.endif
	ret

ScanSystemMemory ENDP

;--- find a contiguous area of 64 KB for the EMS page frame.
;--- should handle commandline option like "FRAME=D000"

LocatePageFrame PROC uses di si

local page_:word
local bHardWanted:byte
local bSearching:byte
local bWarning:byte

	xor al,al
	mov bSearching,al
	mov bWarning,al
	mov bHardWanted,al

	.if bFrameWanted
		mov bHardWanted,1
	.else
		mov bFrameWanted,0e0h
	.endif

	xor si,si	;frame address
; Line 296
	mov al,bFrameWanted
	sub ah,ah
	mov di,ax

; Line 300
	xor bx,bx
	.repeat
		mov al, SystemMemory[bx][di]
;--- v5.76: 'I' is also ok
;		.if al == 'U'
		.if al == 'U' || al == 'I'
			;
		.elseif bHardWanted && di >= 80h && ( al == 'R' || al == 'G' )
			mov bWarning,1
		.else
			.break
		.endif
		inc bx
	.until bx == 16

	.if bx == 16
		.if ( di & 3 )         ;v5.78: warn if frame doesn't begin on a 16 kB
			mov bWarning,1     ;physical page
		.endif
		mov si,di
		jmp $frameset251
	.endif

	.if bHardWanted
		invoke printf, CStr("Selected page frame %02x00 not accepted, scanning for a valid one...", LF), bFrameWanted
	.endif

	mov bSearching,1

	mov di,0a0H
	.repeat
		xor bx,bx
		.repeat
;--- v5.78: 'I' is also ok
;			.break .if SystemMemory[bx][di] != 'U'
			.break .if SystemMemory[bx][di] != 'U' && SystemMemory[bx][di] != 'I'
			inc bx
		.until bx >= 16

		.if bx == 16
			mov si, di
		.endif

		add di,4        ;ensure that frame starts at an EMS "physical page"
	.until di > 0E8h

	.if si == 0
		invoke printf, CStr("%s: no suitable page frame found, EMS functions limited.", LF), addr szWarning
		mov jemmini.NoFrame,1
		xor ax,ax
		jmp exit
	.endif

$frameset251:

	.if bVerbose || bSearching
		invoke printf, CStr("Using page frame %02x00", LF), si
	.endif
	.if bWarning && (!bSearching)
		invoke printf, CStr("%s: page frame %02x00 might not work reliably", LF), OFFSET szWarning, si
	.endif

if ?USEMEMSET
	mov ax,offset SystemMemory
	add ax,si
	invoke memset, ax, 'P', 16
else
	push ds
	pop es
	mov di,offset SystemMemory
	add di,si
	mov cx,16
	mov al,'P'
	rep stosb
endif

	mov	ax,si
	mov	ah,al
	sub	al,al

exit:
	ret

LocatePageFrame ENDP

IsUMBMemory PROC stdcall pg:word

	cmp	jemmini.NoRAM,0
	jne	$L567
	mov	bx, pg
	mov al, SystemMemory[bx]
	cmp	al,'U'
	je	$I275
	cmp	al,'I'
	je	$I275
if ?SPLIT
	cmp	al,'0'
	jbe	@F
	cmp	al,'8'
	jb	$I275
@@:
endif
	cmp	jemmini.NoEMS,0
	jne	@F
	cmp	jemmini.NoFrame,0
	je	$L567
@@:
	cmp	al,'P'
	jne	$L567
$I275:
	mov	ax,1
$EX272:
	ret
$L567:
	xor	ax,ax
	jmp	$EX272

IsUMBMemory ENDP

UMBpageswanted PROC uses di si

	xor	di,di
	mov	si,0A0H
	.repeat
		invoke IsUMBMemory, si
		add di,ax
		inc	si
	.until si == 0F8h
	mov	ax,di
	ret

UMBpageswanted ENDP

if ?INTEGRATED eq 0

if 0

emmcall proc c uses si function:byte

	mov si,offset emmreg
	mov al,byte ptr [si].REGS._ax
	mov ah, function
	mov bx,[si].REGS._bx
	mov cx,[si].REGS._cx
	mov dx,[si].REGS._dx
	int 67h
	mov [si].REGS._ax,ax
	mov [si].REGS._bx,bx
	mov [si].REGS._cx,cx
	mov [si].REGS._dx,dx
	movzx ax,ah
	ret

emmcall endp

endif

xmscall proc stdcall uses si function:BYTE

	mov si,offset xmsreg
	mov ebx,[si].REGS._ebx
	mov edx,[si].REGS._edx
	mov ah, function
if ?XMSRMDBG
	@DbgOutS <"xms call: ax=">,1
	@DbgOutW ax,1
	@DbgOutS <" ebx=">,1
	@DbgOutD ebx,1
	@DbgOutS <" edx=">,1
	@DbgOutD edx,1
	@DbgOutS <10>,1
endif
	call [XMSdriverAddress]
	mov [si].REGS._eax,eax
	mov [si].REGS._ebx,ebx
	mov [si].REGS._ecx,ecx
	mov [si].REGS._edx,edx
if ?XMSRMDBG
	@DbgOutS <"xms ret : ax=">,1
	@DbgOutW ax,1
	@DbgOutS <" ebx=">,1
	@DbgOutD ebx,1
	@DbgOutS <" ecx=">,1
	@DbgOutD ecx,1
	@DbgOutS <" edx=">,1
	@DbgOutD edx,1
	@DbgOutS <10>,1
endif
	ret
xmscall endp

;--- get status of XMS memory
;--- sets global variables xms_mem_largest, xms_mem_free

XMSGetMemoryStatus PROC c usev3:word

	.if usev3
		invoke xmscall, 88h	;get total free memory (edx) and largest free block (eax)
		.if bl == 0	;BL must be 00
			mov xms_mem_largest, eax
			mov xms_mem_free, edx
			jmp ok
		.endif
	.endif
	mov xmsreg._bx,0
	invoke xmscall, 8	;get total free memory (dx) and largest free block (ax)
	.if bl == 0
		movzx eax, ax
		movzx edx, dx
		mov xms_mem_largest, eax
		mov xms_mem_free, edx
		jmp ok
	.endif
	xor ax,ax
	ret
ok:
	mov ax,1
	ret

XMSGetMemoryStatus ENDP

;--- alloc extended memory for monitor and preallocated page pool
;--- JEMM386 only

XMSAllocMemory PROC c usev3:word, dwSizeKB:dword

local xmshandle:word

	mov eax, dwSizeKB
	mov xmsreg._edx, eax
	.if eax >= 10000h || usev3
		invoke xmscall, 089h	;allocate ext. mem block
	.else
		invoke xmscall, 9		;allocate ext. mem block
	.endif
	.if ax
		mov ax, xmsreg._dx
	.endif
	@DbgOutS <"XMSAllocMemory: exit, ax=">,?INITRMDBG
	@DbgOutW ax,?INITRMDBG
	@DbgOutS <13,10>,?INITRMDBG
	ret

XMSAllocMemory ENDP

endif

E820MAP struct
baselow  dd ?
basehigh dd ?
lenlow   dd ?
lenhigh  dd ?
type_    dd ?
E820MAP ends

SMAP equ 534d4150h

I15CheckRsvdRegion proc uses si di
local mmap:E820MAP
	@DbgOutS <"I15CheckRsvdRegion: enter",13,10>,?INITRMDBG
nextitem:
	push ss
	pop es
	mov edx,SMAP
	mov ecx, sizeof E820MAP
	lea di,mmap
	xor eax,eax
	mov mmap.baselow,eax   ; insurance against buggy BIOS
	mov mmap.type_,eax
	mov mmap.lenlow,eax
	mov ax,0e820h
	int 15h
	cmp eax,SMAP
	jne done

	cmp ecx,sizeof E820MAP	; didn't return all the info needed, assume done
	jb done

	cmp mmap.type_,2	; reserved memory ?
	jne itemdone
	mov eax, mmap.baselow
	cmp eax, 0C0000h
	jb itemdone
	cmp eax,100000h
	jnc itemdone
	mov ecx, mmap.lenlow
	shr eax, 4
	shr ecx, 12
	mov si,ax
	.if bVerbose
		push cx
		push bx
		shl cx,2
		invoke printf, CStr(<"Int15, ax=E820: reserved region=%04X, size=%u kB",LF>), si, cx
		pop bx
		pop cx
	.endif
	.while cx
		invoke SetMemoryType, si, 'E'
		add si,100h
		dec cx
	.endw
itemdone:
	cmp ebx,0		;was this the last entry?
	jnz nextitem
	mov bI15RsvdChk,1
done:
	ret
I15CheckRsvdRegion endp

if ?INTEGRATED

;--- return size of free extended memory block in EAX
;--- may set global variables xms_mem_largest, xms_mem_free
;--- returns free memory in kB in EAX.
;--- called by AllocAndInitMem()

I15GetMemoryStatus proc stdcall uses si di

local maxvalue:DWORD
local mmap:E820MAP

	cmp [bNoE820],0    ; NOE820 option set?
	jne @@e801_check

	@DbgOutS <"I15GetMemoryStatus: get extended memory with int 15, E820",13,10>,?INITRMDBG

;--- try 0e820h first

	xor ebx, ebx
	mov si, 0
	mov maxvalue, ebx

e820_nextitem:

;--- ebx offset is updated with each successive int 15h

	push ss
	pop es
	mov edx,SMAP
	mov ecx, sizeof E820MAP
	lea di,mmap
	xor eax,eax
	mov mmap.baselow,eax   ; insurance against buggy BIOS
	mov mmap.type_,eax
	mov mmap.lenlow,eax
	mov ax,0e820h
	clc
	int 15h
	setc dl 		; keep carry flag status
	cmp eax,SMAP
	jne e820_bad	; failure
	cmp dl,1
	je e820_done	; CF doesn't have to signal fail, can just mean done

	cmp ecx,sizeof E820MAP	; didn't return all the info needed, assume done
	jb e820_done

	cmp mmap.type_,1	; memory available to OS?
	jne e820_itemdone

	cmp mmap.basehigh, 0;ignore memory beyond 4 GB for now
	jnz e820_itemdone

	mov edx, mmap.baselow
	cmp edx, 100000h ; has to live in extended memory
	jb e820_itemdone

	@DbgOutS <"I15GetMemoryStatus: available memory found at ">,?INITRMDBG
	@DbgOutD edx,?INITRMDBG
	@DbgOutS <13,10>,?INITRMDBG

	mov ecx, mmap.lenlow
	shr ecx, 10
	shr edx, 10
	call I15SetHandle	;set xms block, sizeK in ECX, baseK in EDX
	inc si
	cmp si,?PREDEFXMSHDLS	;reached max capacity of the static handle array?
	jz e820_done
e820_itemdone:
	cmp ebx,0		;was this the last entry?
	jnz e820_nextitem

e820_bad:
e820_done:
	mov eax, xms_mem_largest
	and eax, eax
	jnz _ret

;--- try 0e801h, but set up the registers to fail status because not
;--- all BIOS's properly return the carry flag on failure

@@e801_check:
	cmp [bNoE801],0 ;NOE801 option set?
	jne @@try_88h

	@DbgOutS <"I15GetMemoryStatus: get extended memory with int 15, E801",13,10>,?INITRMDBG

	xor ax,ax
	mov bx,ax
	mov cx,ax
	mov dx,ax
	mov ax,0e801h
	clc
	int 15h
	jc @@try_88h
	mov ax,cx
	or ax,dx
	je @@try_88h

; if dx is > 0, then cx should be 3c00h since that's full 1-16M range
;  if cx != 3c00h use cx and not dx
	cmp cx,3c00h
	je @F
	cmp dx,0
	je @F
	xor dx,dx
@@:
	movzx edx,dx
	shl edx,6			; convert 64K blocks to 1K
	movzx eax,cx
	add eax,edx
	cmp eax,64		; only use if useful amount
	ja @@exit

@@try_88h:
;--- e801h didn't do the trick, fall back to old 88h with 64M max

	@DbgOutS <"I15GetMemoryStatus: get extended memory with int 15, 88",13,10>,?INITRMDBG

	clc
	mov ah,88h
	int 15h
	movzx eax,ax
	jnc @@exit
	xor ax,ax
@@exit:
	mov ecx, eax
	mov edx, 1024
	call I15SetHandle		; set xms block, sizeK in ECX, baseK in EDX
_ret:
	@DbgOutS <"I15GetMemoryStatus: exit, xms_mem_free=">,?INITRMDBG
	@DbgOutD xms_mem_free,?INITRMDBG
	@DbgOutS <13,10>,?INITRMDBG
	ret
I15GetMemoryStatus endp

;--- get A20 method

GetA20Method PROC stdcall cmdline:ptr BYTE

	push si
	push di
	mov si,[cmdline]
	mov di,offset a20_methods
	xor bx,bx
	push ds
	pop es
	cld
@@nextitem:
	mov cl,[di]
	mov ch,0
	jcxz @@done
	inc di
	pusha
@@nextchar:
	lodsb
	or al,20h
	scasb
	loopz @@nextchar
	popa
	jz @@found
	add di,cx
	inc bx
	jmp @@nextitem
@@found:
	mov di,si
	add si,cx
@@nextchar2:
	lodsb
	stosb
	and al,al
	jnz @@nextchar2
@@done:
	mov ax,bx
	pop di
	pop si
	ret

GetA20Method ENDP

;--- there are 3 A20 switch procs:
;--- 1. KBC (port 64h/60h)
;--- 2. fast, ps2, port92 (port 92h)
;--- 3. BIOS (int 15h, ax=240xh)

; try turning A20 on or off from current to see if it works
; KBC HIMEM method
; entry: ah == 0 A20 turn off, ah == 2 turn on, ax on stack

disable_enable_a20_KBC proc

	pushf
	cli 			; shut off interrupts while we twiddle

	call Sync8042	; check keyboard controller ready
	mov al,0D1h 	; Send D1h
	out 64h,al
	call Sync8042
	mov al,0ddh 	; or df=dd+2
	or al,ah	   ; disable/enable A20 command (DDh/DFh)
	out 60h,al
	call Sync8042

; wait up to 20 microseconds for A20 line to settle
	mov al,0FFh 	; pulse output port NULL
	out 64h,al
	call Sync8042
	popf
	ret

Sync8042:
	xor cx,cx
@@:
	in al,64h
	and al,2
	loopnz @B
	retn
disable_enable_a20_KBC endp

; the so-called 'fast' A20 method replacement code
; entry: ah == 0 A20 turn off, ah == 2 turn on, ax on stack

disable_enable_a20_fast proc
	pushf
	in al,92h
	or ah,ah
	jne deaf_on 	; turning on A20
	test al,2
	je deaf_done   ; already flagged off, don't do it again, might upset something
	and al,NOT 2	; set A20 bit off
	jmp deaf_out

; ah == 2
deaf_on:
	test al,ah
	jne deaf_done	; already flagged on
	or al,ah		; set A20 bit on

deaf_out:
	out 92h,al

; wait until it gets on or off, possibly superfluous, code opinion differs
	xor cx,cx
@@:
	in al,92h
	and al,2
	cmp al,ah
	loopne @B

deaf_done:
	popf
	ret
disable_enable_a20_fast endp

; BIOS A20 method
; entry: ah == 0 A20 turn off, ah == 2 turn on, ax on stack
; don't check for errors, assume BIOS works more than once on same call,
;  if it doesn't, not much we can do about it anyway
;
disable_enable_a20_BIOS proc
	pushf
	push dx
	sub sp,12	; give buggy BIOS some stack to chew on without causing problems
				; one word might suffice, but let's be really safe
	cli
	shr ah,1	; ah to 0 or 1
	mov al,24h
	xchg ah,al	; ax == 2400h to turn off, 2401h to turn on
	int 15h

	add sp,12	; restore potentially gnawed-on stack
	pop dx
	popf
	ret
disable_enable_a20_BIOS endp

disable_enable_a20_dummy proc
	or ah,ah
	ret
disable_enable_a20_dummy endp

get_a20_status proc
	push ds
	push es
	push cx
	push si
	push di
	mov cx,-1
	mov es,cx
	mov si,10h
	inc cx
	mov ds,cx
	mov di,20h
	mov cl,4
	repz cmpsd
	pop di
	pop si
	pop cx
	pop es
	pop ds
	ret
get_a20_status endp

; upon entry bx->disable/enable routine for a20 method being tested
; return carry set if failed, reset if success
;
test_A20_proc proc
	call get_a20_status
	setnz dl
	jz @F			; A20 disabled on entry
	mov ah,0
	call si 		; try to disable A20
	call get_a20_status
	jnz @@fail		; A20 not disabled
@@:

; try to enable A20 (always disabled at this point)

	mov ah,2
	call si
	call get_a20_status
	jz @@fail		; A20 not enabled
	or dl,dl
	jne @@ok		; A20 was enabled on entry, done
	mov ah,0
	call si
	call get_a20_status
	jnz @@fail		; A20 not disabled
@@ok:
	clc
	ret
@@fail:
	stc
	ret

test_A20_proc endp

; check if BIOS flags port 92h fast method supported

detect_fast proc
	stc
	mov ax,2403h
	int 15h
	jc @@fail
	or ah,ah
	jne @@fail
	test bl,2		;PS/2 supported?
	je @@fail
	mov si,OFFSET disable_enable_a20_fast
	call test_A20_proc
	ret
@@fail:
	stc
	ret
detect_fast endp

; check if BIOS flags PS/2 present, to try port 92h fast method used by PS/2's
;  shares enable/disable code with fast

detect_PS2 proc

	mov ah,0c0h 	; get system description vector
	stc
	int 15h
	jc @@fail		; not a PS/2

; test feature information byte 1, micro channel implemented bit
	test BYTE ptr es:[bx+5],2
	jz @@fail		; not micro channel

	mov si,OFFSET disable_enable_a20_fast
	call test_A20_proc
	ret

@@fail:
	stc
	ret

detect_PS2 endp

; check if port 92h fast method supported without BIOS or PS/2 test
;  shares enable/disable code with fast and PS/2

detect_port92 proc

	mov si,OFFSET disable_enable_a20_fast
	call test_A20_proc
	ret

detect_port92 endp


detect_BIOS proc
	stc 			; preset carry flag
	mov ax,2402h	; get gate status
	int 15h
	jc @@fail
	or ah,ah
	jne @@fail
;	mov cl,al		; save status

	mov si,OFFSET disable_enable_a20_BIOS
	call test_A20_proc
	ret
@@fail:
	stc
	ret

detect_BIOS endp


detect_KBC proc

	mov si,OFFSET disable_enable_a20_KBC
	call test_A20_proc
	ret

detect_KBC endp

;--- get the A20 proc to use
;--- in: AH = 0 -> ignore A20 current state

InitA20 proc c uses si

	mov al, jemmini.A20Method
	cmp al, -1
	jnz done
	call get_a20_status  ; check if the A20 line is on, if so assume it's always on
	mov al, A20_ALWAYSON
	jnz done

;--- not on, try other methods

	call detect_fast; see if port 92h (2403h BIOS call) handler supported	
	mov al, A20_FAST
	jnc done
	call detect_PS2 ; see if port 92h (PS/2 signature) handler supported
	mov al, A20_PS2
	jnc done
	call detect_KBC ; see if KBC handler supported
	mov al, A20_KBC
	jnc done

; try BIOS here, demoted from first in line because unreliable BIOS
;  versions of A20 control exist

	call detect_BIOS; see if BIOS A20 handler supported
	mov al, A20_BIOS
	jnc done

; see if fast port 92h handler supported without BIOS or PS/2 signature
;  leave this test until last because messing with port 92h is
;  reported to crash some machines which don't support that method

	call detect_port92
	mov al, A20_PORT92
	jnc done

	stc	; out of options to try, return error
	ret
done:
	clc
	ret

InitA20 endp

endif

;--- allocates and initializes extended memory for jemm;
;--- is called after the memory requirements have been calculated.
;--- will set jemmini values Monitorstart, TotalMemory, XMSControlHandle.

AllocAndInitMem PROC c uses esi di kbneeded:dword

local ulcalc:dword
local PotentialEmsVcpiMemory:dword
local dwMinOriginal:dword

	@DbgOutS <"AllocAndInitMem: enter",13,10>,?INITRMDBG
	mov eax, jemmini.MinMem16k
	mov dwMinOriginal, eax

;     the DMA buffer must be 64kb aligned. Since EMS pages *must* be
;     allocated from memory physically "behind" the DMA buffer, there may
;     be some space wasted, max 60-16=44 kB

	.if jemmini.DMABufferSize > 4
		.if jemmini.DMABufferSize > 64
			mov ax, 32
		.else
			mov ax,jemmini.DMABufferSize
			shr ax,1
		.endif
		movzx eax,ax
		add kbneeded,eax
		.if bVerbose
			invoke printf, CStr("%u kB to account for DMA buffer 64 kB alignment", LF), ax
		.endif
	.endif

if ?INTEGRATED
	invoke I15GetMemoryStatus
	.if !eax
		invoke printf, CStr("%s: can't get I15 memory status", LF), offset szError
$L569:
		xor ax,ax
		ret
	.endif
else
	invoke XMSGetMemoryStatus, xmsspec3
	.if !ax
		invoke printf, CStr("%s: can''t get XMS memory status", LF), offset szError
$L569:
		xor ax,ax
		ret
	.endif
endif
	.if bVerbose
if ?INTEGRATED
		invoke printf, CStr("I15: largest free block %lu kB, free memory %lu kB", LF), xms_mem_largest, xms_mem_free
else
		invoke printf, CStr("XMS: largest free block %lu kB, free memory %lu kB", LF), xms_mem_largest, xms_mem_free
endif
	.endif

;--- if pool sharing is disabled (option NODYN ;no XMS handle table for jemm386)
;--- AND option MIN= is not given:
;--- calculate a value for MIN= which will be preallocated.

	.if jemmini.NoPool && (!MinRequest)
		.if word ptr xms_mem_largest+2 > 0	;more than 64 MB?
			mov ax, 8000H				;then use 32 MB
		.else
			mov ax,WORD PTR xms_mem_largest+0
			shr ax,1
		.endif
		shr ax,4
		movzx eax,ax
		mov jemmini.MinMem16k,eax
		.if bVerbose
			invoke printf, CStr("default preallocated memory=%lu 16k-pages", LF), jemmini.MinMem16k
		.endif
	.endif

;--- reality check to throttle requests far beyond available XMS, later actual
;--- adjustments are small and need not be compensated for here

	.if jemmini.MinMem16k
		mov eax,jemmini.MinMem16k
		shl eax,4
		add eax,[kbneeded]
		mov ecx, kbneeded
		mov edx, xms_mem_largest
		.if eax > edx && ecx < edx
			sub edx,kbneeded
			shr edx, 4
			mov jemmini.MinMem16k,edx
		.endif

;--- leave a little extended memory, if possible, for programs that want some XMS

		mov edx, xms_mem_largest
		mov eax, kbneeded
		add eax, 384

		mov ecx,jemmini.MinMem16k
		shl ecx,4
		add ecx,384
		add ecx, kbneeded

		.if edx > eax && edx < ecx
			mov eax, xms_mem_largest
			sub eax, [kbneeded]
			sub eax,384
			shr eax,4
			mov jemmini.MinMem16k,eax
		.endif
	.endif

;--- default is: all memory

	mov eax, xms_mem_free
	.if eax > kbneeded
		sub eax, kbneeded
	.else
		xor eax,eax
	.endif
	mov PotentialEmsVcpiMemory, eax

	.if jemmini.NoPool	;/* Pool sharing off? */
		mov eax, jemmini.MinMem16k
		shl eax, 4
		.if eax < xms_mem_free
			mov eax, jemmini.MinMem16k
			shl eax, 4
			mov PotentialEmsVcpiMemory, eax
		.endif
	.endif

;   /* MIN= has higher priority than MAX= */
	mov eax, jemmini.MinMem16k
	.if  eax > jemmini.MaxMem16k
		mov jemmini.MaxMem16k,eax
	.endif

;   /* MaxMem16k may have been set by MAX=, and above the limit */
	mov eax,jemmini.MaxMem16k
	shl eax,4
	.if eax > [PotentialEmsVcpiMemory]
		mov eax,[PotentialEmsVcpiMemory]
		shr eax,4
		mov jemmini.MaxMem16k,eax
	.endif

;   /* MaxMem16k may have been set by MAX=, and below 32 MB! */
;   /* this is valid, but then adjust max EMS pages as well */
	movzx eax,jemmini.MaxEMSPages
	.if  jemmini.MaxMem16k < eax
		mov ax,WORD PTR jemmini.MaxMem16k
		mov jemmini.MaxEMSPages,ax
	.endif

;   /* if MIN= has been set adjust max. EMS pages */
	movzx eax,jemmini.MaxEMSPages
	.if jemmini.MinMem16k > eax
		.if jemmini.MinMem16k > MAX_EMS_PAGES_POSSIBLE
			mov ax, MAX_EMS_PAGES_POSSIBLE
		.else
			mov ax, word ptr jemmini.MinMem16k+0
		.endif
		mov jemmini.MaxEMSPages, ax
	.endif

	.if bVerbose
		mov eax,jemmini.MaxMem16k
		shl eax,4
		invoke printf, CStr("potential/max. VCPI memory: %lu/%lu kB", LF), PotentialEmsVcpiMemory, eax
	.endif

;   the memory pooling need ((XMS total / 1.5M) + 1) * 64 bytes
;   for pool allocation table entries
;   1.5M is pool allocation maximum memory control,
;   64 is pool block size,
;   if dynamic XMS allocation is on, 128 more items are needed,
;   which represent the maximum number of XMS handles

	mov eax, jemmini.MaxMem16k
	shl eax,4
	mov ecx,1536	;00000600H
	xor edx,edx
	div ecx
	add eax,2
	mov ulcalc,eax

	.if !jemmini.NoPool
		add [ulcalc],128
	.endif

	mov eax,ulcalc
	shl eax,6
	mov ulcalc,eax

;   /* 4+1 bytes for each EMS page needed */
;   /* 255*4 bytes for EMS handle table */
;   /* 255*8 bytes for EMS name table */
;   /* 64*16 bytes for EMS save status table (EMS_MAXSTATE) */

	movzx eax, jemmini.MaxEMSPages
	imul eax, 5
	add eax,255*4+255*8+64*4
	add ulcalc,eax

	mov eax,ulcalc	;/* convert bytes back to K */
	add eax,1023
	shr eax, 10

	add eax,3	;/* 4k page align */
	and al,0FCh
	mov ulcalc,eax

	.if bVerbose
		invoke printf, CStr("%lu kB needed for VCPI and EMS handling", LF), eax
	.endif

	mov eax, ulcalc
	add kbneeded, eax

	mov eax,jemmini.MinMem16k
	shl eax, 4
	add eax, kbneeded
	mov esi, eax
if ?INTEGRATED eq 0
	invoke XMSAllocMemory, xmsspec3, eax
	.if !ax
		invoke printf, CStr("%s: can't allocate enough XMS memory(%lu kB)", LF), offset szError, esi
		jmp $L569	;exit with error
	.endif
	mov jemmini.XMSControlHandle, ax

	mov xmsreg._dx, ax
	invoke xmscall, 12	;lock extended memory block (returns phys address)
	.if !ax
		invoke printf, CStr("%s: can't lock XMS memory", LF), offset szError
		invoke xmscall, 10	;free memory block
		jmp $L569	;exit with error
	.endif

else
	invoke I15AllocMemory, 0, esi
	.if !ax
		invoke printf, CStr("%s: can't allocate enough I15 memory(%lu kB)", LF), offset szError, esi
		jmp $L569	;exit with error
	.endif
	mov jemmini.XMSControlHandle, ax
endif
	mov eax,jemmini.MinMem16k
	.if eax < dwMinOriginal
		shl eax, 4
		invoke printf, CStr("%s: MIN has been reduced to %lu kB", LF), offset szWarning, eax
	.endif

	mov eax, esi
	shl eax, 10
	mov dwAllocatedBytes, eax

if ?INTEGRATED eq 0

;--- xmsreg contains the locked physical address
	mov ax,xmsreg._bx
	mov dx,xmsreg._dx
	mov WORD PTR jemmini.MonitorStart+0,ax
	mov WORD PTR jemmini.MonitorStart+2,dx
else
	invoke GetEMBBase, jemmini.XMSControlHandle
	mov jemmini.MonitorStart, eax
endif
	mov ecx, xms_mem_free
	shl ecx, 10				;convert kB to bytes
	add ecx, jemmini.MonitorStart
	mov jemmini.TotalMemory, ecx

	mov ax,1
	@DbgOutS <"AllocAndInitMem: exit, MonitorStart=">,?INITRMDBG
	@DbgOutD jemmini.MonitorStart,?INITRMDBG
	@DbgOutS <", Totalmemory=">,?INITRMDBG
	@DbgOutD jemmini.TotalMemory,?INITRMDBG
	@DbgOutS <13,10>,?INITRMDBG
	ret

AllocAndInitMem ENDP

;--- toupper(char) returns uppercase character

toupper PROC
	pop cx
	pop ax
	push cx
	cmp al,'a'
	jb @F
	cmp al,'z'
	ja @F
	sub al,20h
@@:
	ret

toupper ENDP

NotInstalled proc
	MOV DX,CStr( NAMEGEN," is not installed. (Enter ",NAMEEXE," -? for help)",CR,LF,'$' )
	MOV AH,9
	INT 21H
	ret
NotInstalled endp

;--- check if there's an installed Jemm386/JemmEx monitor program

IsJemmInstalled proc c
	@DbgOutS <"IsJemmInstalled enter",10>,?EMXRMDBG
	mov dx, offset sig1
	mov ax, 3D00h
	int 21h
	jnc @F
	mov dx, offset sig2
	mov ax, 3D00h
	int 21h
	jc @@nojemm1
@@:
	@DbgOutS <"EMM device found",10>,?EMXRMDBG
	mov bx,ax
	xor ax,ax
	push ax
	push ax
	push ax
	mov cx,6		;read 6 bytes
	mov dx,sp
	mov ax,4402h	;read ioctl
	int 21h
	pop ax			;version
	pop cx			;API entry offs
	pop cx			;API entry segm
	jc @@nojemm2
	cmp ax,0028h	;this is JEMM!
	jnz @@nojemm2
	mov ax,bx		;return the file handle
	@DbgOutS <"Jemm found",10>,?EMXRMDBG
	clc
	ret
@@nojemm2:
	@DbgOutS <"Jemm not found",10>,?EMXRMDBG
	mov ah,3Eh
	int 21h
@@nojemm1:
	stc
	ret
IsJemmInstalled endp

if ?UNLOAD

;--- try to unload Jemm386

TryUnload proc c uses di si

local handle:word
local resparm[2]:word
if UMB_MAX_BLOCKS le 8
local buff[size UMBBLK * 8]:byte
else
local buff[size UMBBLK * UMB_MAX_BLOCKS]:byte
endif

	invoke IsJemmInstalled
	jc @@nojemm
	mov bx, ax		;EMMXXXX0 handle
	mov handle,ax
	@DbgOutS <"TryUnload, Jemm installed",10>,?UNLRMDBG
	mov byte ptr resparm,4	;call function 4
	lea dx,resparm
	mov cx,4		;returns 4 byte
	mov ax,4402h	;read ioctl (get monitor's resident segment/size)
	int 21h
	jc @@nojemm2

	invoke printf, CStr("found Jemm instance at segment %x", LF), resparm[0]

;--- check if any INT hooked by jemm has been stolen

	invoke CheckIntHooks, resparm[0]
	jc @@nouninst

	@DbgOutS <"TryUnload, no stolen ints detected",10>,?UNLRMDBG

;--- check if any UMB is allocated

	mov buff,7		;call "get umbs" function
	lea dx, buff
	mov cx,UMB_MAX_BLOCKS * size UMBBLK
	mov bx,handle
	mov ax,4402h	;read ioctl
	int 21h
	jc @@nouninst
	@DbgOutS <"TryUnload, got UMBs from Jemm",10>,?UNLRMDBG
	xor dx,dx
	mov cx,UMB_MAX_BLOCKS
	mov si,sp
@@:
	lodsw			;segment
	lodsw			;size + flag
	or dx,ax
	loop @B
	mov sp,si
	test dh,80h 	;any umb allocated?
	jnz @@nouninst
	@DbgOutS <"TryUnload, no allocated UMBs",10>,?UNLRMDBG

;-- close EMMXXXX0 handle

	mov ah,3Eh
	int 21h

if ?INTEGRATED

;-- get current XMS (must be Jemm386)

	invoke XMSinit
	les si, XMSdriverAddress
	cmp byte ptr es:[si],0EBh	;anyone hooked into XMS?
	jnz @@nouninst
	@DbgOutS <"TryUnload, no XMS hookers detected",10>,?UNLRMDBG

;-- check if any XMS memory is in use

	push ds
	lds si, jemmini.XMSHandleTable
	mov ax, ds
	or ax, si
	jz @@xmsused
	mov cx, [si].XMS_HANDLETABLE.xht_numhandles
	lds si, [si].XMS_HANDLETABLE.xht_pArray
	add si, size XMS_HANDLE ;dont check first entry (is Jemm itself)
	dec cx
nextitem:
	cmp [si].XMS_HANDLE.xh_flags, XMSF_USED
	jz @@xmsused
	add si, size XMS_HANDLE
	loop nextitem
@@xmsused:
	pop ds
	jz @@nouninst
	@DbgOutS <"TryUnload, no EMBs are used",10>,?UNLRMDBG
endif

;-- check if any EMS/VCPI memory is in use

	mov ah,4Bh		;get number of open handles (handle 0 is ok)
	int 67h
	cmp bx,01h		;any handle > 0000 allocated?
	ja @@nouninst
	@DbgOutS <"TryUnload, no EMS handles are used",10>,?UNLRMDBG

;-- todo: check VCPI

;-- ok to unload.

	mov ax,resparm[0]		;get current Emm386 segment 
	call UnloadJemm			;this will destroy contents of si and di
	jc @@nouninst
ife ?INTEGRATED
	mov dx,ax
	mov ah, 0Dh 	;unlock block
	call [XMSdriverAddress]
	mov ah, 0Ah 	;free block
	call [XMSdriverAddress]
else
	movzx bx, al
	add bx,bx
	mov ah,DISABLE_A20
	call A20procs[bx]
endif
	MOV DX, CStr( NAMEGEN," unloaded",CR,LF,'$' )
@@exit:
	MOV AH,9
	INT 21H
@@exit2:
	ret
@@nojemm2:
@@nojemm:
	call NotInstalled
	jmp @@exit2
@@nouninst:
	MOV DX, CStr( NAMEGEN, " cannot be unloaded.",CR,LF,'$' )
	jmp @@exit
TryUnload endp

endif

;--- display status of a running Jemm386/JemmEx

EmmStatus proc c uses di si

local handle:word
if UMB_MAX_BLOCKS le 8
local buff[size UMBBLK * 8]:byte
else
local buff[size UMBBLK * UMB_MAX_BLOCKS]:byte
endif

	mov handle,-1
	invoke IsJemmInstalled
	jc jemm_not_found
	mov handle,ax
	mov bx, ax
	lea dx, [buff]	;get version
	mov byte ptr [buff],2
	mov cx,2
	mov ax,4402h	;read ioctl (get version) [Emm386 compatible call]
	int 21h
	jc jemm_not_found
	movzx ax, byte ptr [buff+0]
	movzx cx, byte ptr [buff+1]
	invoke printf, CStr( NAMEMOD," v%u.%02u installed.",LF), ax, cx

;--- get EMS, VCPI, UMB, VME, A20 infos

	lea dx, [buff]
	mov byte ptr [buff],6
	mov cx,sizeof EMX06
	mov bx, handle
	mov ax,4402h	;read ioctl
	int 21h
	jc done
	@DbgOutS <"EmmStatus: read ioctl(6) ok",10>,?EMXRMDBG

	mov di, ax
	lea si, [buff]
	cmp [si].EMX06.e06_NoEMS, 0
	mov dx, offset szOff
	jnz @F
	mov dx, offset szOn
@@:
	invoke printf, CStr("EMS is %s"), dx

	cmp [si].EMX06.e06_NoEMS,0
	jnz @@nodispframe			;dont display FRAME status if no EMS

	mov ah,42h
	int 67h
	mov ax, dx
	sub ax, bx
	invoke printf, CStr(", %u of max. %u pages allocated"), ax, dx

	mov ax, CStr(", no Page Frame")
	mov cx, [si].EMX06.e06_Frame
	jcxz @F
	mov ax, CStr(", Page Frame at %04X")
@@:
	invoke printf, ax, cx
@@nodispframe:
	invoke printf,CStr(".", LF)

	cmp [si].EMX06.e06_NoVCPI, 0	;_NoVCPI flag
	jnz @F
	invoke printf, CStr("VCPI is On, %lu of max. %lu pages allocated.", LF), [si].EMX06.e06_VCPIUsed, [si].EMX06.e06_VCPITotal
	jmp @@vcpidone
@@:
	invoke printf, CStr("VCPI is Off.", LF)
@@vcpidone:

	mov ax, 64		;default DMA buffer size
	cmp di, 16		;could the DMA buffer size be read?
	jb @F
	mov ax, [si].EMX06.e06_DMASize
@@:
	mov ecx, [si].EMX06.e06_DMABuff
	invoke printf, CStr("DMA buffer at %08lX, size %u kB.", LF), ecx, ax

if ?A20PORTS or ?A20XMS
	mov ax, offset szOff
	cmp [si].EMX06.e06_NoA20, 0
	jnz @F
	mov ax, offset szOn
@@:
	invoke printf, CStr("A20 emulation is %s.", LF), ax
endif

if ?VME
	mov ax, offset szOff
	cmp [si].EMX06.e06_NoVME, 0
	jnz @F
	mov ax, offset szOn
@@:
	invoke printf, CStr("VME is %s.", LF), ax
endif

if ?PGE
	mov ax, offset szOff
	cmp [si].EMX06.e06_NoPGE, 0
	jnz @F
	mov ax, offset szOn
@@:
	invoke printf, CStr("PGE is %s.", LF), ax
endif

	lea dx, [buff]
	mov byte ptr [buff],7
	mov cx, UMB_MAX_BLOCKS * sizeof UMBBLK
	mov bx, handle
	mov ax,4402h	;read ioctl
	int 21h
	jc done
	@DbgOutS <"EmmStatus: read ioctl(7) ok",10>,?EMXRMDBG

	lea si,[buff]
	mov cx, UMB_MAX_BLOCKS
	.repeat
		mov ax, [si].UMBBLK.wSegm
		.break .if !ax
		push cx
		mov dx, [si].UMBBLK.wSize
		mov cx, CStr("allocated")
		test dh,80h
		jnz @F
		mov cx, CStr("free")
@@:
		and dh, 7Fh ;reset highest flag
		add dx, ax
		dec dx
		invoke printf, CStr("UMB supplied at %04X-%04X, %s.", LF), ax, dx, cx
		pop cx
		add si, size UMBBLK
	.untilcxz

done:
	mov bx, handle
	cmp bx, -1
	jz @F
	mov ah, 3Eh
	int 21h
@@:
	ret
jemm_not_found:
	@DbgOutS <"EmmStatus: Jemm not found",10>,?EMXRMDBG
	call NotInstalled
	jmp done
EmmStatus endp

;--- pass options to an already installed Jemm386/JemmEx monitor

CMD15 struct
cmd db ?	;=15
	EMX15W <>
CMD15 ends

EmmUpdate proc c uses di

local buff:CMD15

	@DbgOutS <"EmmUpdate enter",10>,?EMXRMDBG
	xor di,di
	invoke IsJemmInstalled
	jnc @F
	call NotInstalled
	jmp @@exit
@@:
	mov bx, ax       ;save file handle

;--- fill structure to be send to running Jemm386/JemmEx

	mov buff.cmd,15

if ?VME
	mov al, [jemmini.NoVME]
else
	mov al,-1
endif
	mov buff.e15_bVME,al
if ?A20PORTS or ?A20XMS
	mov al, [jemmini.NoA20]
else
	mov al,-1
endif
	mov buff.e15_bA20,al
	mov al, [jemmini.NoVCPI]
	mov buff.e15_bVCPI,al
if ?PGE
	mov al, [jemmini.NoPGE]
else
	mov al,-1
endif
	mov buff.e15_bPGE,al

	mov cx,sizeof CMD15
	lea dx,[buff]
	mov ax,4403h	;write ioctl
	int 21h
	jc @F
	@DbgOutS <"EmmUpdate: write ioctl(15) ok",10>,?EMXRMDBG
	inc di
@@:
	mov ah,3Eh	;close EMMXXXX0 handle
	int 21h
@@exit:
	@DbgOutS <"EmmUpdate exit",10>,?EMXRMDBG
	mov ax,di
	ret
EmmUpdate endp

;--- cpu is in protected-mode, check EMM status

IsEmmInstalled proc c
	invoke IsJemmInstalled
	mov dx, CStr( NAMEGEN,' already installed',CR,LF,'$' )
	jnc @F
	call EmmInstallcheck
	jc exit
	mov dx, CStr( "CPU in protected mode, loading aborted",CR,LF,07,'$' )
@@:
	mov ah,9
	int 21h
exit:
	ret
IsEmmInstalled endp

;--- GetValue()
;--- converts a string into a DWORD

GetValue PROC stdcall uses esi di cmdline:ptr BYTE, base:WORD, usesuffix:WORD

	xor esi, esi		;result
	mov bx, cmdline
@@nextitem:
	mov al,BYTE PTR [bx]
	push ax
	call toupper
	mov ah,al
	sub al,'0'
	jc @@FB316
	cmp al,9
	jbe @@I318
	sub al,7
	cmp al,0Ah
	jb @@FB316
	cmp al,0Fh
	ja @@FB316
@@I318:
	movzx ecx, base
	cmp cl,al
	jle @@FB316
	xchg eax,esi
	mul ecx
	xchg eax,esi
	movzx eax,al
	add esi,eax
	inc bx
	jmp @@nextitem

@@FB316:
	cmp BYTE PTR usesuffix, 0
	je @@I322
	mov al,ah
	cmp al,'M'
	je @@SC328
	ja @@I322
	sub al,'G'
	je @@SC327
	sub al,4
	je @@SC329 	;'K'?
	jmp @@I322
@@SC327:
	shl esi,10
@@SC328:
	shl esi,10
@@SC329:
	inc bx
@@I322:
	push esi
	mov si,bx
	mov di, cmdline
	push ds
	pop es
@@nextchar:
	lodsb
	stosb
	and al,al
	jnz @@nextchar
	pop eax		;result in EAX
	ret

GetValue ENDP

;--- FindCommand(searchstring) parses the command line
;--- for a specific command. If found, the command is removed and
;--- the address behind that command is returned. Else, 0 is returned
;--- SI=cmdline

FindCommand PROC stdcall uses di si searchstring:ptr BYTE

	mov di, searchstring
	invoke strlen, di 	;returns size in AX, sets ES=DS
	mov bx,ax		;searchlen = bx
nextcmp:
	xor ax,ax
	cmp BYTE PTR [si],al
	je done
	invoke _memicmp, si, di, bx   ;assumes that BX remains unchanged!
	inc si
	or ax,ax
	jne nextcmp
	dec si
	push si
	mov di,si
	add si,bx
nextitem:
	lodsb
	stosb
	and al,al
	jnz nextitem
	pop ax
done:
	ret

FindCommand ENDP

;--- VMware detection
;--- questionable, because Qemu "responds" similar to VMware

VMwareDetect proc c

	mov eax, 564D5868h	;magic number (="VMXh")
	mov cx, 000ah		;command number (000A=get VMware version)
	xor ebx,ebx 		;command specific parameter
	mov dx, 5658h		;VMware IO port (="VX")
	in eax,dx			;"returns" version number in EAX
	cmp ebx, 564D5868h	;and magic number in EBX (="VMXh")
	setz al
	mov ah,0
	ret

VMwareDetect endp

cprintf PROC c pszText:ptr byte

	.if bVerbose
		invoke printf, pszText
	.endif
	ret

cprintf ENDP

IsProtectedMode proc c
	SMSW AX
	AND AX,0001H	; PE-Bit (Protect Enable) set ?
	ret
IsProtectedMode ENDP

IsDPMI proc c uses si di
	mov ax,1687h
	int 2Fh
	and ax,ax
	setz al
	mov ah,0
	ret
IsDPMI ENDP

mainex PROC c public uses di si mode:word, cmdline:ptr BYTE

local rangestart:word
local rangestop:word
local found:word
local memtype:byte
local bOptionSet:byte
local bHelp:byte

	cld
	xor di,di		;bOptionSet
	mov bHelp,0

	mov si,cmdline
	.if mode != EXECMODE_EXE
		invoke printf, addr szStartup
		mov bLoad,1
if ?FASTBOOT
		invoke FindCommand, CStr("FASTBOOT")
		.if ax
			or jemmini.V86Flags, V86F_FASTBOOT
		.endif
endif
	.else
if ?UNLOAD
		invoke FindCommand, CStr("UNLOAD")
		.if ax
			invoke XMSinit
			invoke TryUnload
			jmp exit1
		.endif
endif
if ?LOAD
		invoke FindCommand, CStr("LOAD")
		.if ax
			mov bLoad,1
		.else
			mov al,0ffh
			mov jemmini.NoVCPI,al
if ?A20PORTS or ?A20XMS
			mov jemmini.NoA20,al
endif
if ?VME
			mov jemmini.NoVME,al
endif
if ?PGE
			mov jemmini.NoPGE,al
endif
		.endif
endif
		invoke FindCommand, CStr("/?")
		.if !ax
			invoke FindCommand, CStr("-?")
			.if !ax
				invoke FindCommand, CStr("/H")
				.if !ax
					invoke FindCommand, CStr("-H")
				.endif
			.endif
		.endif
		.if ax
			mov bHelp,1
		.endif
	.endif

	invoke FindCommand, CStr("NOVCPI")
	.if ax
		mov jemmini.NoVCPI,1
		inc di
	.endif
	invoke FindCommand, CStr("VCPI")
	.if ax
		mov jemmini.NoVCPI,0
		inc di
	.endif
if ?INTEGRATED
;--- /* must come before A20 option */
	invoke FindCommand, CStr("A20METHOD:")
	.if ax
		invoke GetA20Method, ax
		mov jemmini.A20Method,al
	.endif
endif
if ?A20PORTS or ?A20XMS
	invoke FindCommand, CStr("NOA20")
	.if ax
		mov jemmini.NoA20,1
		inc di
	.endif
	invoke FindCommand, CStr("A20")
	.if ax
		mov jemmini.NoA20,0
		inc di
	.endif
endif
if ?VME
;	mov jemmini.NoVME,1
	invoke FindCommand, CStr("NOVME")
	.if ax
		mov jemmini.NoVME,1
		inc di
	.endif
	invoke FindCommand, CStr("VME")
	.if ax
		mov jemmini.NoVME,0
		inc di
	.endif
endif
if ?PGE
	invoke FindCommand, CStr("NOPGE")
	.if ax
		mov jemmini.NoPGE,1
		inc di
	.endif

	invoke FindCommand, CStr("PGE")
	.if ax
		mov jemmini.NoPGE,0
		inc di
	.endif
endif

	and di,di
	setnz bOptionSet

if ?V86EXC0D
	invoke FindCommand, CStr("V86EXC0D")
	.if ax
		or jemmini.V86Flags,V86F_V86EXC0D
	.endif
endif

if ?INTEGRATED
	invoke FindCommand, CStr("HMAMIN=")
	.if ax
		invoke GetValue, ax, 10, 0
		.if ax > 63
			mov ax,63
		.endif
		mov jemmini.HmaMin, ax
	.endif
	invoke FindCommand, CStr("MAXEXT=")
	.if ax
		invoke GetValue, ax, 10, 1
		mov xms_max, eax
	.endif

	invoke FindCommand, CStr("NOE801")
	.if ax
		mov bNoE801,1
	.endif
	invoke FindCommand, CStr("NOE820")
	.if ax
		mov bNoE820,1
	.endif
	invoke FindCommand, CStr("XMSHANDLES=")
	.if ax
		invoke GetValue,ax, 10, 0
		.if ax < 8
			mov ax,8
		.elseif ( ax > 128 )
			mov ax, 128
		.endif
		mov xms_num_handles,ax
	.endif
	invoke FindCommand, CStr("X2MAX=")
	.if ax
		invoke GetValue, ax, 10, 1
		mov jemmini.X2Max, ax
	.endif
endif

	cmp bLoad,0
	je $I395

	invoke FindCommand, CStr("VERBOSE")
	.if !ax
		invoke FindCommand, CStr("/V")
	.endif
	.if ax
		mov bVerbose,1
	.endif

	invoke FindCommand, CStr("NODYN")
	.if ax
		mov jemmini.NoPool,1
	.endif
	invoke FindCommand, CStr("NOINVLPG")
	.if ax
		mov jemmini.NoInvlPg,1
	.endif

	invoke FindCommand, CStr("MIN=")
	.if ax
		invoke GetValue, ax, 10, 1
		shr eax, 4
		mov jemmini.MinMem16k,eax
		.if bVerbose
			shl eax, 4
			invoke printf, CStr("Wanted preallocated EMS/VCPI memory: %lu kB", LF), eax
		.endif
		mov MinRequest,1
	.endif

	invoke FindCommand, CStr("MAX=")
	.if ax
		invoke GetValue, ax, 10, 1
		shr eax,4
		mov jemmini.MaxMem16k+0,eax
	.endif
	invoke FindCommand, CStr("NOEMS")
	.if ax
		invoke cprintf, CStr("NOEMS: EMS disabled (mostly :-)", LF)
		mov jemmini.NoEMS,1
	.endif

	invoke FindCommand, CStr("NOVDS")
	.if ax
		mov jemmini.NoVDS,1
	.endif
	invoke FindCommand, CStr("VDS")
	.if ax
		mov jemmini.NoVDS,0
	.endif

	invoke FindCommand, CStr("FRAME=NONE")
	.if ax
		mov jemmini.NoFrame,1
	.else
		invoke FindCommand, CStr("FRAME=")
		.if !ax
			invoke FindCommand, CStr("/P")
		.endif
		.if ax
			invoke GetValue, ax, 16, 0
			.if al
				invoke printf, CStr("Rejected page frame=%x", LF), ax
			.else
				mov bFrameWanted, ah
				.if bVerbose
					invoke printf, CStr("Wanted page frame=%X", LF), ax
				.endif
			.endif
		.endif
	.endif

	invoke FindCommand, CStr("X=TEST")
	.if ax
		mov ExcludeTest,1
	.endif
	invoke FindCommand, CStr("I=TEST")
	.if ax
		mov IncludeTest,1
	.endif
if ?SB
	invoke FindCommand, CStr("SB")
	.if ax
		or jemmini.V86Flags, V86F_SB
	.endif
endif
if ?EMX
	invoke FindCommand, CStr("EMX")
	.if ax
		or jemmini.V86Flags, V86F_EMX
	.endif
endif
if ?SPLIT
	invoke FindCommand, CStr("SPLIT")
	.if ax
		mov SplitTest,1
	.endif
endif
	invoke FindCommand, CStr("NOCHECK")
	.if ax
		or jemmini.V86Flags, V86F_NOCHECK
	.endif

	invoke FindCommand, CStr("ALTBOOT")
	.if ax
		mov jemmini.AltBoot,1
	.endif
	invoke FindCommand, CStr("NOHI")
	.if ax
		mov jemmini.NoHigh,1
	.endif

;--- NOMOVEXBDA is a no-op, but helps MS EMM386 switch compatibility
	invoke FindCommand, CStr("NOMOVEXBDA")

	invoke FindCommand, CStr("NORAM")
	.if ax
		mov jemmini.NoRAM,1
	.endif

	invoke FindCommand, CStr("RAM")
	.if ax
		mov jemmini.NoRAM,0
	.endif

	invoke FindCommand, CStr("D=")
	.if ax
		invoke GetValue,ax, 10, 0
		mov di,ax
		.if ax <= 128
			lea ax,[di+3]
			and al,0FCh
			mov jemmini.DMABufferSize,ax
		.else
			mov jemmini.DMABufferSize,128
			invoke printf, CStr("%s: wanted DMA buffer size too large, set to 128 kB", LF), addr szWarning
		.endif
	.endif

	invoke FindCommand, CStr("B=")
	.if ax
		invoke GetValue, ax, 16, 0
		.if ax < 1000h
			mov ax, 1000h
		.endif
		mov jemmini.Border,ax
	.endif

;--- initialize conventional memory map
;--- 0000-9FFF: R(am)
;--- A000-BFFF: G(raphics)
;--- C000-EFFF: U(MB)
;--- F000-FFFF: E(PROM)

if ?USEMEMSET
	invoke memset, addr SystemMemory+000h, 'R', 160
	invoke memset, addr SystemMemory+0A0h, 'G', 32
	invoke memset, addr SystemMemory+0C0h, 'U', 48
	invoke memset, addr SystemMemory+0F0h, 'E', 16
else
	push ds
	pop es
	mov di, offset SystemMemory
	mov cx,160	;160*4 = 10*64 = 0000-9FFF
	mov al,'R'	;RAM
	rep stosb
	mov al,'G'	;graphics
	mov cl,32	;A000-BFFF
	rep stosb
	mov al,'U'	;possibly UMB
	mov cl,48	;C000-EFFF
	rep stosb
	mov al,'E'	;ROM
	mov cl,16	;F000-FFFF
	rep stosb
endif
	invoke I15CheckRsvdRegion

	invoke VMwareDetect
	.if ax
		mov dword ptr SystemMemory+0E8h, 'VVVV'
		mov dword ptr SystemMemory+0ECh, 'XXXX'
		invoke cprintf, CStr("VMware detected", LF)
	.endif

	.while 1
		mov memtype,'I'
		invoke FindCommand, CStr("I=")
		.if !ax
			mov memtype,'S'
			invoke FindCommand, CStr("S=")
			.if !ax
				mov memtype,'X'
				invoke FindCommand, CStr("X=")
				.break .if !ax
			.endif
		.endif
		mov di,ax
		invoke GetValue, ax, 16, 0
		mov rangestart,ax
		.if BYTE PTR [di] == '-'
			mov BYTE PTR [di],' '
			inc di
			invoke GetValue, di, 16, 0
			mov rangestop, ax
			mov cl, memtype
			sub ch,ch
			mov dx, rangestart
			.if dx < 0A000h || dx >= ax
				invoke printf, CStr("Rejected %c=%x..%x", LF), cx, dx, ax
			.else
				.if bVerbose
					invoke printf, CStr("Accepted %c=%x..%x", LF), cx, dx, ax
				.endif
				mov di, rangestart
				.while di < rangestop
					invoke SetMemoryType, di, memtype
					inc di
				.endw
			.endif
		.endif
	.endw

$I395:
	invoke skipWhite, si
	mov si,ax
	cmp BYTE PTR [si],'0'
	jb @F
	cmp BYTE PTR [si],'9'
	ja @F
	invoke GetValue, ax, 10, 1
	shr eax,4
	mov jemmini.MaxMem16k,eax
	invoke skipWhite, si
	mov si,ax
@@:
	.if BYTE PTR [si]
		invoke printf, CStr("* ignored commandline: '%s'", LF), si
		cmp mode,EXECMODE_EXE
		je exit1
	.endif

	.if bLoad == 0
		invoke printf, addr szStartup
		.if bHelp
			invoke printf, addr szCopyRight
			invoke printf, addr szHelp
		.else
			.if bOptionSet
				invoke EmmUpdate
				.if ax
					invoke printf, CStr("option(s) passed to installed instance of ", NAMEMOD, LF)
				.endif
			.else
				invoke EmmStatus
			.endif
		.endif
		jmp exit1
	.endif

; /******* options set, now process **********/

	invoke IsProtectedMode
	.if ax
		invoke IsEmmInstalled
		jmp exit1
	.endif
	invoke XMSinit

if ?INTEGRATED eq 0
	.if !ax
		invoke printf, CStr("%s: no XMM found, required", LF), offset szError
		jmp exit1
	.endif
else
	.if ax
		invoke printf, CStr("%s: XMM already installed", LF), offset szError
		jmp exit1
	.endif
endif

	invoke IsDPMI
	.if ax
		invoke printf, CStr("%s: DPMI host detected", LF), offset szError
		jmp exit1
	.endif

if ?INTEGRATED
	invoke InitA20
	.if (CARRY?)
		invoke printf, CStr("%s: No supported A20 method detected",LF), offset szError
		jmp exit1
	.endif
	mov jemmini.A20Method,al
	.if bVerbose
		movzx bx, al
		add bx, bx
		invoke printf, CStr("'%s' A20 method selected",LF), A20strings[bx]
	.endif
	movzx bx,jemmini.A20Method
	add bx,bx
	mov ah,ENABLE_A20
	call A20procs[bx]
else
	invoke xmscall, 0	;get version
	.if ax && xmsreg._ax >= 0300h
		mov xmsspec3,1
	.endif
	invoke xmscall, 5	;enable A20
	.if !ax
		invoke printf, CStr("%s: enable A20 failed", LF), offset szError
		jmp exit1
	.endif
endif

	.if jemmini.MaxMem16k == -1
		mov jemmini.MaxMem16k, MAXMEM16K_DEFAULT
	.endif
	.if jemmini.NoVCPI
		invoke cprintf, CStr("VCPI disabled", LF)
	.endif
	.if jemmini.NoVDS
		invoke cprintf, CStr("VDS disabled", LF)
	.endif
if ?INTEGRATED eq 0
;    /* if no int 2fh, function 4309h support, disable pool sharing */
	.if jemmini.XMSHandleTable == 0 && jemmini.NoPool == 0
		mov jemmini.NoPool,1
		invoke printf, CStr("%s: XMS host doesn''t provide handle array, dynamic memory allocation off!", LF), offset szWarning
	.endif
endif

	invoke ScanSystemMemory	;/* build up system memory map */

	.if  jemmini.NoEMS
		mov jemmini.NoFrame,1
	.endif
	.if jemmini.NoFrame == 0
		invoke LocatePageFrame
		mov jemmini.Frame,ax
	.endif

; allocate from XMS the memory we need
; this is memory for UMBs, including FF00
;
;  + 20kB for the monitor code, GDT, IDT, stack
;  + 12kB for page tables
;  + 12kB for TSS + IO-Bitmap (includes 3 kB reserve for rounding)
;  +  4kB for mapping FF000 page
;  + 64kB +-X for DMA buffering
;  + room for other control structures made inside function
;                               
;  + what the user wants for EMS

MONITORMIN equ 20+12+12+4

	invoke UMBpageswanted
	shl	ax,2
	mov	si,ax

	.if bVerbose
		invoke printf, CStr("Needed: %u kB for monitor, %u kB for UMBs, %u kB for DMA buffer", LF), MONITORMIN, ax, jemmini.DMABufferSize
	.endif

	.if jemmini.NoEMS
		mov ax, 512
	.else
		mov ax, MAX_EMS_PAGES_ALLOWED
	.endif
	mov jemmini.MaxEMSPages,ax

	add si,jemmini.DMABufferSize
	add si, MONITORMIN
	movzx esi,si
	invoke AllocAndInitMem, esi
	.if ax == 0
if ?INTEGRATED
		movzx bx,jemmini.A20Method
		add bx,bx
		mov ah,DISABLE_A20
		call A20procs[bx]
else
		invoke xmscall, 6 ; local disable A20
endif
		jmp exit1
	.endif

	mov eax, dwAllocatedBytes
	add eax, jemmini.MonitorStart
	mov jemmini.MonitorEnd,eax

	.if bVerbose
		invoke printf, CStr("XMS memory block for monitor: %lx-%lx, XMS highest=%lx", LF), jemmini.MonitorStart, eax, jemmini.TotalMemory
	.endif

	.if bVerbose
		invoke printf, CStr(<"Memory Map: (R=system ram, G=graphics, E=rom/rsvd, P=page frame, U/I=umb)",LF>)
		sub sp,64+4
		mov cx,4
		mov si,offset SystemMemory
		.while cx
			push cx
			movzx eax,si
			sub ax,offset SystemMemory
			shl eax,12
			invoke printf, CStr(<"%05lX: ">), eax
			push ss
			pop es
			mov al,' '
			mov di,sp
			add di,2
			push di
			movsd
			movsd
			movsd
			movsd
			stosb
			movsd
			movsd
			movsd
			movsd
			stosb
			movsd
			movsd
			movsd
			movsd
			stosb
			movsd
			movsd
			movsd
			movsd
			mov al,0
			stosb
			pop di
			invoke printf, CStr(<"%s",LF>), di
			pop cx
			dec cx
		.endw
		add sp,64+4
	.endif

	mov ax, ds
	movzx eax, ax
	shl eax, 4
	lea eax, [eax+offset SystemMemory]
	mov jemmini.PageMap, eax

	invoke InitJemm
	.if bVerbose
		invoke printf, CStr("Physical start address of EMS pages: %lX", LF), eax
		mov ah,42h
		int 67h
		.if ah == 0 
			movzx eax,bx
			movzx ecx,dx
			shl eax,4
			shl ecx,4
			invoke printf, CStr("Total/available EMS pages: %d/%d (= %lu(%lu) kB)",LF), dx, bx, ecx, eax
		.endif
	.endif
	invoke printf, CStr( NAMEMOD," loaded",LF )

if ?INTEGRATED eq 0
	invoke xmscall, 6	;local disable A20
endif
	xor	ax,ax
$EX338:
	ret
exit1:
	mov ax,1
	jmp $EX338

mainex ENDP

END
