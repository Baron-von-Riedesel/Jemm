
;--- 16-bit part of JLoad
;--- JLoad loads a 32bit PE binary in Jemm's address space
;--- best viewed with TABSIZE 4

;--- these segment definitions must be BEFORE .model since alignment is 4

_TEXT segment dword public 'CODE'
_TEXT ends
_DATA segment dword public 'DATA'
_DATA ends

	.model tiny
	.dosseg

	.386

	option casemap:none
	option proc:private

	include jemm.inc
	include jemm32.inc
	include jlm.inc
	include jload.inc
	include debug.inc
	include macros.inc
	include winnt.inc

ENVIRON 		equ 2Ch

STATUS_OK       equ 0100h   ; driver is initialized and ok
STATUS_BAD      equ 8103h   ; driver couldn't be installed

CMD_INIT		equ 0		; init command (used when installed)

FMODE_LFN		equ 1		; fMode flags

FOPTION_QUIET	equ 1		; be quiet, don't display information texts

?MAXPATH		equ 260

cr				equ 0dh
lf				equ 0ah

?CATCHEXC06		equ 0		;std=0, 1=catch Exc 06 (pretty useless)

;*** define segments ***

	.code

; device driver header

	dd -1
	dw 8000h
	dw offset strategy
	dw offset interrupt
	db 'JLOAD$$$'
dwRequest dd 0
strategy:
	mov word ptr cs:[dwRequest+0],bx
	mov word ptr cs:[dwRequest+2],es
	retf

CCONST segment dword use16 public 'CODE'
CCONST ends
BEGDATA segment para use16 public 'CODE'
BEGDATA ends
_DATA segment dword use16 public 'DATA'
_DATA ends
_BSS segment dword use16 public 'BSS'
_BSS ends
STACK segment para use16 stack  'STACK'
	db 1024 dup (?)
stacktop label byte
STACK ends

DGROUP group _TEXT,CCONST,BEGDATA,_DATA,_BSS,STACK

;--- cpu descriptor

desc struc
  limit     dw ?       ; segment limit
  base00_15 dw ?       ; low word of base address
  base16_23 db ?       ; high byte of base address
            db ?       ; 93h = std ring 0 read/write segment
  attr      db ?       ; attributes, limit 16-19
  base24_31 db ?
desc ends

;--- DOS device driver request header

request_hdr struc
  req_size  db ?       ; number of bytes stored
  unit_id   db ?       ; unit ID code
  cmd       db ?       ; command code
  status    dw ?       ; status word
  rsvd      db 8 dup (?)   ; reserved
request_hdr ends

;--- DOS device driver request for INIT

init_strc struc
  init_hdr  db size request_hdr dup (?)
  units     db ?       ; number of supported units
  end_addr  dd ?       ; end address of resident part
  cmd_line  dd ?       ; address of command line
init_strc ends

;--- VCPI jump to protected mode structure

V862PM	STRUC
swCR3		DD ? ; client's CR3 value
swGDTOFFS	DD ? ; offset of client's GDTR value
swIDTOFFS	DD ? ; offset of client's IDTR value
swLDTR		DW ? ; client's LDTR value
swTR		DW ? ; client's TR value
swCSEIP 	DF ? ; entry point in client
V862PM	ENDS

;*** variables ***

_DATA segment

;--- GDT used for int 15h, ah=87h

i15tab  label desc
	desc <0,0,0,0,0,0>
	desc <0,0,0,0,0,0>
	desc <-1,0,0,93h,0CFh,0>
	desc <-1,0,0,93h,0CFh,0>
	desc <0,0,0,0,0,0>
	desc <0,0,0,0,0,0>

if ?USEVCPIEXIT
vcpigdt label desc
	desc <0,0,0,0,0,0>
	desc <0,0,0,0,0,0>
	desc <0,0,0,0,0,0>
endif

vcpisw	V862PM <0,0,0,0,0,0>

	align 4

vmms	VMMS <<0,0,0,<0>>,<0,0,0,0,0,0,0>,-1,offset szLdrPath, offset szPgmName, offset PE_Hdr, offset buffer, 0>
ddb		VxD_Desc_Block <?>

dwStack   dd 0			;phys page for protected-mode stack
dwPageTab dd 0			;phys page for VMM page table
dwVmmPage dd 0			;phys page for VMM code/data
dwBuffer  dd 0			;linear address of buffer
dwCmdLine dd 0
if ?CATCHEXC06
oldint06  dd 0
spsaved dw 0
endif
dfIDT	df 0
hJemm	dw -1
wRet	dw 0
fMode	db 0
fOption	db 0			;additional option from cmdline ("-q")

_DATA ends

CCONST segment

dUsage  db "JLoad v",?VERSIONHIGH+'0',".",@CatStr(!",%?VERSIONLOW/10,%?VERSIONLOW mod 10,!")
		db " Copyright japheth 2008-2022",13,10
		db "JLoad loads JLMs (Jemm Loadable Modules) into Jemm's address space.",13,10
		db "It can be run as a DOS device driver or from the command line.",13,10
		db "usage:",13,10
		db "  [DEVICE=] JLOAD.EXE [options] name_of_JLM [arguments]",13,10
		db "  options:",13,10
		db "  -q: quiet",13,10
		db "  -u: unload a JLM",13,10
		db '$'
szErrExp db "' doesn't export a DDB",13,10,'$'

CCONST ends

_BSS segment

wVersion	dw ?			;DOS version major+minor

	align 4

szLdrPath	db ?MAXPATH dup (?)	;JLOAD full path

_edata	label byte

szPgmName	db ?MAXPATH dup (?)	;program name from command line

MZ_Hdr		db 40h dup (?)		;MZ header buffer (same memory as NE header
PE_Hdr		IMAGE_NT_HEADERS <?>

;--- the buffer should be last. thus it is an additional 4 kB if the default
;--- 1 kB stack is too small.

buffer		db 4096 dup (?) 	;4 kb buffer for copy operations

externdef _end:near

_BSS ends

CCONST segment

szLF	db lf,0

sig1	db 'EMMXXXX0',0
sig2	db 'EMMQXXX0',0	; ID if NOEMS specified

CCONST ends

_TEXT segment

	assume CS:DGROUP
	assume DS:DGROUP
	assume SS:DGROUP
	assume ES:DGROUP
    
	align 4

vmmcode label byte
%	include OUTD\JLoad32.inc
	align 4
        
SIZEVMM equ $ - offset vmmcode

_IsJemmInstalled proc

	@DbgOutS <"IsJemmInstalled enter",lf>,?RMDBG
	mov bx, -1
	mov dx, offset sig1
	mov ax, 3D00h
	int 21h
	jnc @@found
	mov dx, offset sig2
	mov ax, 3D00h
	int 21h
	jc @@nojemm
@@found:
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
	jc @@nojemm
	cmp ax,0028h	;this is JEMM!
	jnz @@nojemm
	mov ax,bx		;return the file handle
	clc
	ret
@@nojemm:
	cmp bx,-1
	jz @@noclose
	mov ah,3Eh
	int 21h
@@noclose:
	stc
	ret
_IsJemmInstalled endp

;*** read command line parameter
;*** RC: Carry if error
;***     NC: file to load in szPgmName
;--- modifies DS!

GetPgmParms proc

	@DbgOutS <"GetPgmParms enter",lf>,?RMDBG
	lds si,[dwCmdLine]
	sub cx,cx
	mov ah,0
nextws:
	lodsb
	cmp al,0
	jz error
	cmp al,13
	jz error
	cmp al,'/'
	jz @F
	cmp al,'-'
	jnz isnoopt
@@:
	mov ah,al
	jmp skipcharx
isnoopt:
	cmp al,' '			;skip spaces
	jnz parmfound
skipcharx:
	jmp nextws
error:
	stc
	ret
parmfound:
	and ah,ah			;option mode?
	jz nooption
	or al,20h
	cmp al,'q'
	jnz @F
	or es:[fOption], FOPTION_QUIET
	mov ah,0
	jmp skipcharx
@@:
	cmp al,'u'
	jnz @F
	or es:[vmms.wFlags], JLF_UNLOAD
	mov ah,0
	jmp skipcharx
@@:
	jmp error
nooption:
	dec si
	mov dl,0
	mov di,offset szPgmName
nextchar:
	lodsb
	cmp al,0
	jz copydone
	cmp al,13
	jz copydone
	cmp al,'"'
	jnz @F
	xor ah,1
	jmp skipchar
@@:
	test ah,1
	jnz @F
	cmp al,' '
	jz copydone	   ;copy is done
@@:
	cmp al,'.'
	jnz @F
	inc dl
@@:
	stosb
	cmp al,'/'
	jz @F
	cmp al,'\'
	jnz skipchar
@@:
	mov dl,0
skipchar:
	jmp nextchar
copydone:
	mov word ptr es:[dwCmdLine],si
	test ah,1
	jnz error
	mov al,00
	stosb
	clc
	ret
GetPgmParms endp

;--- get path of JLOAD.EXE
;--- DS not set yet

GetLdrPath proc uses es si di

	@DbgOutS <"GetLdrPath enter",lf>,?RMDBG
	cld
	mov ah,51h
	int 21h
	mov es,bx
	mov bx,es:[ENVIRON] ;get environment
	and bx,bx
	jz @@exit
	mov es,bx
	xor di,di
	or cx,-1
	xor ax,ax
@@:
	repnz scasb			;search end of environment
	scasb				;found?
	jnz @B				;no, continue
	inc di				;skip 0001
	inc di				;now comes current file name
	mov si,offset szLdrPath
@@:
	mov al,es:[di]
	mov cs:[si],al
	inc si
	inc di
	and al,al
	jnz @B
@@exit:
	ret
GetLdrPath endp

;--- openfile in DS:DX
;--- returns file handle in AX if NC

openfile proc uses si

	@DbgOutS <"openfile enter",lf>,?RMDBG

	test [fMode], FMODE_LFN
	jz nolfn
	mov si,dx
	MOV AX,716Ch
	mov dx,1		;action: fail if not exists
	xor bx,bx		;read only 
	xor cx,cx		;
	stc
	int 21h
	mov dx,si
	jnc done
	cmp ax,7100h
	stc
	jnz done
nolfn:
	MOV AX,3D00h 	;open a file for read
	int 21h
done:
	ret
openfile endp

;*** read MZ-Header + PE-Header
;*** Input: BX=file handle
;---        DS=DGROUP
;*** C + AX=szNotaPX if not PX format

ReadHdrs proc

	@DbgOutS <"ReadHdrs enter",lf>,?RMDBG

	mov cx,0040h
	mov dx,offset MZ_Hdr
	mov ah,3Fh			;read MZ hdr
	int 21h
	jc error1			;DOS read error
	cmp ax,cx			;could read 40h bytes?
	jnz error2
	mov ax,word ptr [MZ_Hdr]
	cmp ax,'ZM'
	jnz error3
	mov cx,word ptr [MZ_Hdr+3Eh]
	mov dx,word ptr [MZ_Hdr+3Ch]
	and dx,dx
	jz error4
	mov ax,4200h		;lseek PE hdr
	int 21h
	jc error5			;DOS lseek error, no PE binary

	mov cx,sizeof PE_Hdr
	mov dx,offset PE_Hdr
	mov ah,3Fh			;read
	int 21h
	jc error6			;DOS read error
	cmp ax,cx
	jnz error7
	cmp PE_Hdr.Signature,"XP"
	jnz error6
	cmp PE_Hdr.FileHeader.Machine, IMAGE_FILE_MACHINE_I386 
	jnz error8
	@DbgOutS <"ReadHdrs ok",lf>,?RMDBG
	clc
	ret
error4:
	@DbgOutS <"offset to new header is zero",lf>,?RMDBG
	@tracejmp @F
error2:
	@DbgOutS <"filesize less than 0x0040 Bytes",lf>,?RMDBG
	@tracejmp @F
error5:
	@DbgOutS <"lseek error",lf>,?RMDBG
	@tracejmp @F
error7:
	@DbgOutS <"PE-Header size too small",lf>,?RMDBG
	@tracejmp @F
error8:
	@DbgOutS <"not a 80386 binary",lf>,?RMDBG
	@tracejmp @F
error3:
	@DbgOutS <"cannot find 'MZ' Header",lf>,?RMDBG
	@tracejmp @F
error6:
	@DbgOutS <"PX not found",lf>,?RMDBG
	@tracejmp @F
error1:
	@DbgOutS <"read error (MZ)",lf>,?RMDBG
	@tracejmp @F
@@:
	mov cx,CStr(<"' isn't a PX binary",cr,lf,'$'>)
	stc
	ret

ReadHdrs endp

LoadSectionTable proc stdcall

;	mov dx,word ptr secpos+0
;	mov cx,word ptr secpos+2
;	mov ax,4200h
;	int 21h

	mov cx, PE_Hdr.FileHeader.NumberOfSections
	mov ax, sizeof IMAGE_SECTION_HEADER
	mul cx
	and dx,dx
	jnz error
	cmp ax,sizeof buffer
	ja error
	mov dx, offset buffer
	mov cx, ax
	mov ah,3Fh			;read section header
	int 21h
	jc error
	ret
error:
	stc
	ret

LoadSectionTable endp

;--- find section which contains requested RVA, then position file pointer

FindRVA proc stdcall uses si rva:dword

	mov si, offset buffer
	mov cx, PE_Hdr.FileHeader.NumberOfSections
	.while (cx)
		mov eax, [si].IMAGE_SECTION_HEADER.VirtualAddress
		mov edx, rva
		cmp edx,eax
		jc @F
		add eax, [si].IMAGE_SECTION_HEADER.SizeOfRawData
		cmp edx,eax
		cmc
		jnc found
@@:
		dec cx
		add si, sizeof IMAGE_SECTION_HEADER
	.endw
	stc
exit:
	ret
found:
	sub edx, [si].IMAGE_SECTION_HEADER.VirtualAddress
	add edx, [si].IMAGE_SECTION_HEADER.PointerToRawData
	push edx
	pop dx
	pop cx
	mov ax,4200h
	int 21h
	jc exit
	mov ax,si
	jmp exit

FindRVA endp

;--- read a module's DDB into ddb variable
;*** Input: BX=file handle

ReadDDB proc

local ddbadr:dword
local expdir:IMAGE_EXPORT_DIRECTORY

	cmp PE_Hdr.OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXPORT*sizeof IMAGE_DATA_DIRECTORY].VirtualAddress,0
	jz errexp

	invoke LoadSectionTable
	jc errexp

	invoke FindRVA, PE_Hdr.OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXPORT*sizeof IMAGE_DATA_DIRECTORY].VirtualAddress
	jc errexp

;--- RVA found, now read export directory

	lea dx,expdir
	mov cx,sizeof expdir
	mov ah,3Fh
	int 21h
	jc errexp

;--- now read first entry of IAT

	cmp expdir.NumberOfFunctions,1
	jc errexp
	invoke FindRVA, expdir.AddressOfFunctions
	jc errexp
	lea dx,ddbadr
	mov cx,sizeof ddbadr
	mov ah,3Fh
	int 21h
	jc errexp

;--- now position to ddb and read it

	invoke FindRVA, ddbadr
	jc errexp
	mov dx,offset ddb
	mov cx,sizeof ddb
	mov ah,3Fh
	int 21h
	jc errexp
	mov [vmms.pDDB],offset ddb
	ret
errexp:
	stc
	ret

ReadDDB endp

;--- copy memory to/from extended memory

CopyExtMem proc stdcall uses si dwDst:DWORD, dwSrc:DWORD, wSize:WORD

	@DbgOutS <"CopyExtMem dst=">,?RMDBG
	@DbgOutD dwDst,?RMDBG
	@DbgOutS <", src=">,?RMDBG
	@DbgOutD dwSrc,?RMDBG
	@DbgOutS <10>,?RMDBG

	mov si,offset i15tab
	mov ax, word ptr [dwSrc+0]
	mov [si+2*size desc].desc.base00_15,ax
	mov ax, word ptr [dwSrc+2]
	mov [si+2*size desc].desc.base16_23,al
	mov [si+2*size desc].desc.base24_31,ah
	mov ax, word ptr [dwDst+0]
	mov [si+3*size desc].desc.base00_15,ax
	mov ax, word ptr [dwDst+2]
	mov [si+3*size desc].desc.base16_23,al
	mov [si+3*size desc].desc.base24_31,ah
	mov cx,wSize
	shr cx,1
	mov ah,87h
	int 15h
	@DbgOutS <"CopyExtMem exit",lf>,?RMDBG
	ret
CopyExtMem endp

;--- get linear address of an offset

GetLinear proc stdcall wOfs:WORD
	mov ax,ds
	movzx eax,ax
	shl eax,4
	push ecx
	mov cx,wOfs
	movzx ecx,cx
	add eax,ecx
	pop ecx
	ret
GetLinear endp

;--- init VMM if JLOAD runs the first time (and a JLM is to be loaded)
;--- alloc 1 page for page table
;--- alloc 1 or 2 page(s) for VMM code (will be moved to ?SYSTEMADDR)
;--- returns AX==0 on failure

InitVMM proc uses di esi

	@DbgOutS <"InitVMM enter",lf>,?RMDBG

	invoke  GetLinear, offset buffer
	mov dwBuffer, eax
if SIZEVMM gt 1000h
	xor esi,esi
endif
	mov ecx,cr3
	invoke CopyExtMem, eax, ecx, 1000h	;copy page dir to buffer
	jnc @F
	mov dx,CStr(<"unable to read page directory",13,10,'$'>)
	jmp error
@@:
	mov edx,dword ptr [buffer+(?SYSTEMADDR shr 20)]
	and dx,0F000h
	mov [dwPageTab],edx
	cmp edx,0						;VMM installed already?
	jnz exit
	mov dx,CStr(<"no JLMs loaded",13,10,'$'>)

	test [vmms.wFlags],JLF_UNLOAD	;error if NO and "unload" mode
	jnz error
	
	mov ax,0DE04h					;get phys page for VMM page table
	int 67h
	and ah,ah
	jz @F
	mov dx,CStr(<"cannot allocate 4k page for page table",13,10,'$'>)
	jmp error
@@:
	mov [dwPageTab],edx

	mov ax,0DE04h					;get page for VMM itself
	int 67h
	and ah,ah
	jz @F
scmemerr:
	mov dx,CStr(<"cannot allocate 4k page for system code",13,10,'$'>)
	jmp error
@@:
	mov [dwVmmPage],edx
if SIZEVMM gt 1000h
	mov ax,0DE04h					;get page for VMM itself
	int 67h
	and ah,ah
	jnz scmemerr
	mov esi,edx
endif
	mov edx, [dwPageTab]			;set PDE for VMM page table
	or dl,7
	mov dword ptr [buffer+(?SYSTEMADDR shr 20)],edx

	mov ecx,cr3 					;"write" updated page dir
	invoke CopyExtMem, ecx, [dwBuffer], 1000h
	mov dx,CStr(<"error setting content of page dir",13,10,'$'>)
	jc error

;--- clear (last) VMM page content

	mov di,offset buffer
	mov cx,1000h/4
	xor eax,eax
	rep stosd
if SIZEVMM gt 1000h
	invoke CopyExtMem, esi, [dwBuffer], 1000h
else
	invoke CopyExtMem, [dwVmmPage], [dwBuffer], 1000h
endif

;--- set PTE for VMM code/data in VMM page table

	mov byte ptr [buffer],6	;in case the first page is "reserved"
	mov edx, [dwVmmPage]
	or dl,3
	mov dword ptr [buffer+((?SYSTEMADDR and 03FFFFFh) shr 10)],edx
if SIZEVMM gt 1000h
	mov edx, esi
	or dl,3
	mov dword ptr [buffer+((?SYSTEMADDR and 03FFFFFh) shr 10)+4],edx
endif

;--- copy content of VMM page table to extended memory

	invoke CopyExtMem, [dwPageTab], [dwBuffer], 1000h
	mov dx,CStr(<"error setting content of system page table",13,10,'$'>)
	jc error

;--- copy VMM code to extended memory

if SIZEVMM le 1000h
	invoke GetLinear, offset vmmcode
	invoke CopyExtMem, [dwVmmPage], eax, SIZEVMM
else
	invoke GetLinear, offset vmmcode
	invoke CopyExtMem, [dwVmmPage], eax, 1000h
	invoke GetLinear, offset vmmcode+1000h
	invoke CopyExtMem, esi, eax, SIZEVMM-1000h
endif
exit:
	@DbgOutS <"InitVMM ok",lf>,?RMDBG
	mov ax,1
	ret
error:
	call errorout
	mov edx, [dwPageTab]
	and edx, edx
	jz @F
	mov ax,0DE05h
	int 67h
@@:
	mov edx, [dwVmmPage]
	and edx, edx
	jz @F
	mov ax,0DE05h
	int 67h
@@:
if SIZEVMM le 1000h
	mov edx, esi
	and edx, edx
	jz @F
	mov ax,0DE05h
	int 67h
@@:
endif
	xor ax,ax
	ret

InitVMM endp

;--- enter 32bit VMM code
;--- returns ax==0 on failure

RunVMM proc public

	@DbgOutS <"RunVMM enter",lf>,?RMDBG

;--- set (common) linear addresses in JLCOMM

	movzx eax, word ptr dwCmdLine+2
	movzx ecx, word ptr dwCmdLine+0
	shl eax,4
	add eax, ecx
	mov [vmms.lpCmdLine],eax

;--- allocate a 4k page to be used for protected-mode stack

	mov ax,0DE04h
	int 67h
	and ah,ah
	jz @F
	mov dx,CStr(<"no memory for protected-mode stack",13,10,'$'>)
	call errorout
	xor ax,ax
	ret
@@:
	mov [dwStack], edx

;--- install a handler for "invalid opcodes"
;--- which is the Jemm method of telling that an error has occured

if ?CATCHEXC06
	push es
	mov ax,3506h
	int 21h
	mov word ptr [oldint06+0],bx
	mov word ptr [oldint06+2],es
	pop es
	mov dx,offset int06
	mov ax,2506h
	int 21h
endif

	@DbgOutS <"RunVMM: preparing switch to protected-mode",lf>,?RMDBG
if ?USEVCPIEXIT
	mov di,offset buffer
	mov si,offset vcpigdt
	mov ax,0DE01h
	int 67h
	mov ebp, ebx
endif

	mov eax, cr3
	mov vcpisw.swCR3, eax
	invoke GetLinear, offset vmms.emx08.e08_GDTR
	mov vcpisw.swGDTOFFS, eax
	invoke GetLinear, offset vmms.emx08.e08_IDTR
	mov vcpisw.swIDTOFFS, eax
	mov vcpisw.swLDTR, 0
	mov ax, vmms.emx08.e08_TR
	mov vcpisw.swTR, ax
	mov eax, ?SYSTEMADDR
	mov dword ptr vcpisw.swCSEIP, eax
	mov ax, vmms.emx08.e08_FlatCS
	mov word ptr vcpisw.swCSEIP+4, ax

	invoke GetLinear, offset szPgmName
	mov ebx,eax

	invoke GetLinear, offset vcpisw
	mov esi, eax

	invoke GetLinear, offset vmms
	mov ecx, eax

	mov edi, [dwStack]
if ?CATCHEXC06
	mov [spsaved],sp
endif
	@DbgOutS <"RunVMM: switch to protected-mode ...",lf>,?RMDBG
	mov ax,0DE0Ch
	int 67h
	sti
	@DbgOutS <"RunVMM: back in v86-mode",lf>,?RMDBG
	push dx
	mov edx,[dwStack]
	mov ax,0DE05h
	int 67h
if ?CATCHEXC06
	push ds
	lds dx,[oldint06]
	mov ax,2506h
	int 21h
	pop ds
endif
	pop ax
	ret
if ?CATCHEXC06
int06:
	push cs
	pop ds
	push cs
	pop es
	mov sp,[spsaved]
	mov dx,CStr(<"exception occured in protected-mode",13,10,'$'>)
	call errorout
	xor ax,ax
	jmp error_occured
endif

RunVMM endp

;--- display msg 'JLoad: <DX>'

errorout proc
	push dx
	mov dx, CStr(<"JLoad: ",'$'>)
	mov ah,9
	int 21h
	pop dx
	mov ah,9
	int 21h
	ret
errorout endp

;--- display an asciiz string

dispstr proc stdcall uses si pString:word
	mov si, pString
nextitem:
	lodsb
	and al,al
	jz done
	mov dl,al
	mov ah,2
	int 21h
	jmp nextitem
done:
	ret
dispstr endp

errorXout2:
	mov dx,CStr(<"'$">)

;--- display an error msg of format:
;--- JLoad: <dx><filename><cx>

errorXout proc
	push cx
	call errorout
	push offset szPgmName
	call dispstr
	pop dx
	mov ah,9
	int 21h
	ret
errorXout endp

;--- load a module and run its initialization code

LoadModule proc

	@DbgOutS <"LoadModule enter",lf>,?RMDBG

	mov dx,offset szPgmName
	call openfile
	jnc @F
	mov cx,CStr(<"' cannot be opened",13,10,'$'>)
	call errorXout2
	jmp exit
@@:
	mov vmms.hFile,ax
	mov bx,ax
	call ReadHdrs
	jnc @F
	call errorXout2
	jmp exit
@@:
	test PE_Hdr.FileHeader.Characteristics, IMAGE_FILE_RELOCS_STRIPPED
	jz @F
	mov cx,CStr(<"' isn't relocatable",13,10,'$'>)
	call errorXout2
	jmp exit
@@:
	cmp PE_Hdr.OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT*sizeof IMAGE_DATA_DIRECTORY].VirtualAddress,0
	jz @F
	mov cx,CStr(<"' has references to external modules",13,10,'$'>)
	call errorXout2
	jmp exit
@@:
	call ReadDDB
	.if (CARRY? && ([vmms.wFlags] & JLF_UNLOAD))
		mov cx,offset szErrExp	;doesn't export DDB
		call errorXout2
		stc
		jmp exit
	.endif

	call InitVMM	;init the VMM
	and ax,ax
	jz exit

	.if ([vmms.wFlags] & JLF_UNLOAD)
		push es
		mov ah,52h			;get start of driver chain
		int 21h
		add bx,22h
		movzx ebx,bx
		mov ax,es
		pop es
		movzx eax,ax
		shl eax,4
		add eax, ebx
		mov [vmms.lpDrivers],eax
	.endif

;--- set linear address 

	movzx eax,word ptr dwRequest+2
	movzx ecx,word ptr dwRequest+0
	shl eax,4
	add eax, ecx
	mov [vmms.lpRequest],eax

;--- run the VMM

	call RunVMM
error_occured:
	mov [wRet],ax
	and ax,ax
	jz @F
;	test byte ptr [vmms.wFlags],JLF_DRIVER
;	jz @@nodispsuccess
	test [fOption],FOPTION_QUIET
	jnz @@nodispsuccess
@@:
	.if ([vmms.wFlags] & JLF_UNLOAD)
		.if (ax)
			mov cx,CStr(<"' unloaded successfully.",13,10,'$'>)
		.else
			.if (cl == 2)
				mov cx,CStr(<"' isn't loaded.",13,10,'$'>)
			.else
				mov cx,CStr(<"' failed to unload.",13,10,'$'>)
			.endif
		.endif
	.else
		.if (ax)
			mov cx,CStr(<"' loaded successfully.",13,10,'$'>)
		.else
			.if (cl == 0B7h)
				mov cx,CStr(<"' already loaded.",13,10,'$'>)
			.else
				mov cx,CStr(<"' failed to load.",13,10,'$'>)
			.endif
		.endif
	.endif
	call errorXout2
@@nodispsuccess:
exit:
	mov bx,vmms.hFile
	cmp bx,-1
	jz @F
	mov ah,3Eh
	int 21h
@@:
	ret

LoadModule endp

;--- common main for .EXE and device driver

main proc
	push cs
	pop ds
	push cs
	pop es
	mov ax,ss
	mov bx,sp
	push ds
	pop ss
	mov sp,offset stacktop-2
	push ax
	push bx
	mov di,offset _edata	; clear BSS segment
	mov cx,offset _end
	sub cx,di
	shr cx,1
	xor ax,ax
	cld
	rep stosw
	@DbgOutS <"JLoad main enter",lf>,?RMDBG
if 0
	mov dx,CStr("JLoad full path: '$")
	mov ah,9
	int 21h
	push offset szLdrPath
	call dispstr
	mov dx,CStr(<"'",13,10,'$'>)
	mov ah,9
	int 21h
endif
	mov ah,30h
	int 21h
	mov [wVersion],ax

	mov [vmms.wLdrCS],cs
							   ;detect if lfn is installed
	mov ax,7147h
	mov si,offset szPgmName
	mov dl,0
	stc
	int 21h
	jc @F
	or fMode, FMODE_LFN
@@:
	push ds
	push si
	push di
	call GetPgmParms
	pop di
	pop si
	pop ds
	jnc @F
	mov dx,offset dUsage
	mov ah,9
	int 21h
	jmp exit
@@:
	call _IsJemmInstalled
	jnc @F
	mov dx,CStr(<"Jemm not installed",13,10,'$'>)
	call errorout
	jmp exit
@@:
	mov hJemm, ax
	mov bx, ax
	push 2			;read version
	mov cx,2		;returns 1 word
	mov dx, sp
	mov ax,4402h	;read ioctl
	int 21h
	pop ax
	cmp ax,?VERSIONHIGH + 256 * ?VERSIONLOW
	jz @F
	mov dx,CStr(<"versions of Jemm and JLoad don't match",13,10,'$'>)
	call errorout
	jmp exit
@@:
	mov dx, offset vmms.emx08
	mov byte ptr [vmms.emx08],8  ;read VMM info
	mov cx,size EMX08
	mov ax,4402h	;read ioctl
	int 21h
	jnc @F
	mov dx,CStr(<"no support for protected mode API",13,10,'$'>)
	call errorout
	jmp exit
@@:
	sidt [dfIDT]
	mov eax,dword ptr [dfIDT+2]
	cmp eax,dword ptr vmms.emx08.e08_IDTR+2
	jz @F
	mov dx,CStr(<"virtualized environment detected",13,10,'$'>)
	call errorout
@@:
	mov ax,0DEF0h
	int 67h
	and ah,ah
	setz al
	shl al,JLF_R0DEBUG_BIT
	or byte ptr [vmms.wFlags],al

	call LoadModule		;load / unload module!
exit:
	mov bx,hJemm
	cmp bx,-1
	jz @F
	mov ah,3Eh
	int 21h
@@:
	cmp [wRet],0
	setz al
	mov ah,0
	@DbgOutS <"JLoad main exit",lf>,?RMDBG
	pop cx
	pop ss
	mov sp,cx
	ret
main endp

if 0

;--- bin to ascii conversion
;--- es:di -> output buffer

DWORDOUT:
	push eax
	shr eax, 16
	call WORDOUT
	pop eax
WORDOUT:			;<-- bin2ascii(WORD in AX) (-> ES:DI)
	push ax
	mov al,ah
	call BYTEOUT
	pop ax
BYTEOUT:
	mov ah,al
	shr al,4
	call NIBOUT
	mov al,ah
NIBOUT:
	and al,0Fh
	add al,'0'
	cmp al,'9'
	jle @F
	add al,07h
@@:
	stosb
	ret
endif

if ?RMDBG

VPRINTSTR PROC
	push bp
	mov bp,sp
	XCHG BX,[bp+2]
	PUSHF
	PUSH AX
@@NEXTCHAR:
	MOV AL,CS:[BX]
	INC BX
	CMP AL,0
	JZ @@DONE
	push bx
	mov bx,0007h
	cmp al,LF
	jnz @@isnotlf
	mov ax,0E0Dh
	int 10h
	mov al,LF
@@isnotlf:
	mov ah,0Eh
	int 10h
	pop bx
	JMP @@NEXTCHAR
@@DONE:
	POP AX
	POPF
	XCHG BX,[bp+2]
	pop bp
	RET
VPRINTSTR ENDP

;--- display (d)word in (e)AX
;--- preserves registers and flags

VDWORDOUT proc near
	push eax
	shr eax,16
	call VWORDOUT
	pop eax
VDWORDOUT endp
VWORDOUT proc near
	push ax
	mov al,ah
	call VBYTEOUT
	pop ax
VWORDOUT endp
VBYTEOUT proc near
	pushf
	push ax
	mov ah,al
	shr al,4
	call vnibout
	mov al,ah
	call vnibout
	pop ax
	popf
	ret
vnibout:
	and al,0Fh
	cmp al,10
	sbb al,69H
	das
	push bx
	push ax
	mov bx,0007
	mov ah,0Eh
	int 10h
	pop ax
	pop bx
	ret
VBYTEOUT endp

endif

;--- entry for driver

interrupt proc far
	pushad
	push es
	push ds
	les di, cs:[dwRequest]
	mov es:[di].request_hdr.status,STATUS_OK		; we're alright
	cmp es:[di].request_hdr.cmd,CMD_INIT
	jne @@done
	mov word ptr es:[di+0].init_strc.end_addr,0
	mov word ptr es:[di+2].init_strc.end_addr,cs
	lds si,es:[di].init_strc.cmd_line
	push cs
	pop es
	cld
	mov di, offset szLdrPath
	.while (byte ptr [si] > ' ')
		movsb
	.endw
	mov al,0
	stosb
	mov word ptr cs:[dwCmdLine+0],si
	mov word ptr cs:[dwCmdLine+2],ds
	or byte ptr cs:[vmms.wFlags],JLF_DRIVER
	call main
@@done:
	pop ds
	pop es
	popad
	ret
interrupt endp

;--- entry for .EXE
;--- if the module returns with dwRequest != 0,
;--- the loader will terminate with ah=31h (stay resident)

start:
	cld
	mov si,80h
	lodsb
	mov bl,al
	mov bh,0
	mov byte ptr [si+bx],0
	mov word ptr cs:[dwCmdLine+0],si
	mov word ptr cs:[dwCmdLine+2],ds
	call GetLdrPath
	call main
	mov ah,4Ch
	test [vmms.wFlags], JLF_UNLOAD
	jnz @F
	mov dx,word ptr [vmms.lpRequest]
	and dx,dx
	jz @F
	mov ah,31h
@@:
	int 21h

_TEXT ends

	end  start

