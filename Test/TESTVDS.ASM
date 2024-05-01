
;--- VDS API test
;--- 8103/8104:      lock/unlock region
;--- 8107/8108/8109/810A: request/release DMA buffer, copy into/out of DMA buffer
;--- 8105/8106       scatter/gather lock/unlock

	.286
	.model small
	.stack 2048
	.dosseg
	.386

CStr macro text:vararg
local sym
	.const
sym db text,0
	.code
	exitm <offset sym>
endm

lf equ 10

DDS struct
dwSize	dd ?
dwOfs	dd ?
wSeg	dw ?
wID		dw ?
dwPhys	dd ?
DDS ends

EDDS struct
dwSize	dd ?
dwOfs	dd ?
wSeg	dw ?
		dw ?
numAvl	dw ?
numUsed dw ?	;after numUsed, PTEs are starting
EDDS ends

	.data
dds_	DDS <>
edds_	EDDS <>
		dd 64 dup (0)	;max 32 entries

	.code

	include printf.inc

RsvdFunction proc

;--- call reserved VDS function 8101

	mov dx,0
	mov ax,8101h
	stc
	int 4bh
	.if (CARRY?)
		cbw
		invoke printf, CStr("int 4B, ax=8101h failed - good, AL=%X",lf), ax
	.else
		invoke printf, CStr("int 4B, ax=8101h ok ? - bad",lf)
	.endif

;--- call reserved VDS function 810D

	mov dx,0
	mov ax,810Dh
	stc
	int 4bh
	.if (CARRY?)
		cbw
		invoke printf, CStr("int 4B, ax=810Dh failed - good, AL=%X",lf), ax
	.else
		invoke printf, CStr("int 4B, ax=810Dh ok ? - bad",lf)
	.endif
	ret
RsvdFunction endp

;--- 8103: lock a region
;--- 8104: unlock a region

LockUnlock proc

local bFail:byte

;--- 8103/8104: lock a region with size 1000h, not crossing a page boundary

	mov di,offset dds_
	mov dds_.dwSize,1000h
	mov dds_.dwOfs,0
	mov dds_.wSeg,0C000h
	mov dx,0
	mov ax,8103h	;lock region
	int 4bh
	lahf
	mov bFail,ah
	.if (CARRY?)
		cbw
		invoke printf, CStr("int 4B, ax=8103h, dx=0 [size=1000h, wSeg=C000] failed, AL=%X",lf), ax
	.else
		invoke printf, CStr("int 4B, ax=8103h, dx=0 [size=1000h, wSeg=C000] ok",lf)
	.endif
	invoke printf, CStr("DDS.dwPhys=%lX, DDS.wID=%X",lf), dds_.dwPhys, dds_.wID

	.if (!(bFail & 1))
		mov di,offset dds_
		mov dx,0
		mov ax,8104h	;unlock region
		int 4bh
		.if (CARRY?)
			cbw
			invoke printf, CStr("int 4B, ax=8104h [size=1000h, wSeg=C000] failed, AL=%X",lf), ax
		.else
			invoke printf, CStr("int 4B, ax=8104h [size=1000h, wSeg=C000] ok",lf)
		.endif
		invoke printf, CStr("DDS.dwPhys=%lX, DDS.wID=%X",lf), dds_.dwPhys, dds_.wID
	.endif

;--- 8103/8104: lock a region with size 8000h in UMB region

	mov di,offset dds_
	mov dds_.dwSize,8000h
	mov dds_.dwOfs,0
	mov dds_.wSeg,0CC00h
	mov dx,0
	mov ax,8103h	;lock region
	int 4bh
	lahf
	mov bFail,ah
	.if (CARRY?)
		cbw
		invoke printf, CStr("int 4B, ax=8103h, dx=0 [size=8000h, wSeg=CC00] failed, AL=%X",lf), ax
	.else
		invoke printf, CStr("int 4B, ax=8103h, dx=0 [size=8000h, wSeg=CC00] ok",lf)
	.endif
	invoke printf, CStr("DDS.dwPhys=%lX, DDS.wID=%X",lf), dds_.dwPhys, dds_.wID

	.if (!(bFail & 1))
		mov di,offset dds_
		mov dx,0
		mov ax,8104h	;unlock region
		int 4bh
		.if (CARRY?)
			cbw
			invoke printf, CStr("int 4B, ax=8104h [size=8000h, wSeg=CC00] failed, AL=%X",lf), ax
		.else
			invoke printf, CStr("int 4B, ax=8104h [size=8000h, wSeg=CC00] ok",lf)
		.endif
		invoke printf, CStr("DDS.dwPhys=%lX, DDS.wID=%X",lf), dds_.dwPhys, dds_.wID
	.endif

;--- 8104: unlock a region with an invalid buffer ID

	mov dds_.wID, -1
	mov dx,0
	mov ax,8104h	;unlock region
	int 4bh
	.if (CARRY?)
		invoke printf, CStr("int 4B, ax=8104h with buffer ID FFFF failed - good",lf)
	.else
		invoke printf, CStr("int 4B, ax=8104h with buffer ID FFFF ok ? - bad",lf)
	.endif

;--- 8103/8104: lock a UMB region with size 20000h - most likely fails

	mov di,offset dds_
	mov dds_.dwSize,20000h
	mov dds_.dwOfs,0
	mov dds_.wSeg,0C000h
	mov dx,4		;disable buffering
	mov ax,8103h	;lock region
	int 4bh
	lahf
	mov bFail, ah
	.if (CARRY?)
		cbw
		invoke printf, CStr("int 4B, ax=8103h dx=4 [dds.size=20000h, wSeg=C000] failed, AL=%X",lf), ax
	.else
		invoke printf, CStr("int 4B, ax=8103h dx=4 [dds.size=20000h, wSeg=C000] ok",lf)
	.endif

	invoke printf, CStr("DDS.dwSize=%lX",lf), dds_.dwSize
	invoke printf, CStr("DDS.dwOfs=%lX",lf), dds_.dwOfs
	invoke printf, CStr("DDS.wSeg=%X",lf), dds_.wSeg
	invoke printf, CStr("DDS.dwPhys=%lX",lf), dds_.dwPhys
	.if (!(bFail & 1))
		mov di,offset dds_
		mov dx,0
		mov ax,8104h	;unlock region
		int 4bh
		.if (CARRY?)
			cbw
			invoke printf, CStr("int 4B, ax=8104h failed, AL=%X",lf), ax
		.else
			invoke printf, CStr("int 4B, ax=8104h ok",lf)
		.endif
	.endif
	ret

LockUnlock endp

;--- 8107 - request a DMA buffer, size 32 kb
;--- 8108 - release DMA buffer
;--- 8109 - copy into DMA buffer
;--- 810A - copy out of DMA buffer

DMABuffer proc

local bFail:byte

	mov di,offset dds_
	mov dds_.dwSize,8000h
;	mov dds_.dwOfs,0		; needed if copy into buffer is requested
;	mov dds_.wSeg,0C000h	; needed if copy into buffer is requested
	mov dx,0		;don't copy into buffer
	mov ax,8107h	;request DMA buffer
	int 4bh
	lahf
	mov bFail, ah
	.if (CARRY?)
		cbw
		invoke printf, CStr("int 4B, ax=8107h dx=0 [dds.size=8000h] failed, AL=%X",lf), ax
	.else
		invoke printf, CStr("int 4B, ax=8107h dx=0 [dds.size=8000h] ok",lf)
	.endif
	invoke printf, CStr("DDS.wID=%X, DDS.dwPhys=%lX",lf), dds_.wID, dds_.dwPhys

	.if (!(bFail & 1))

if 0
		mov dx,0
		mov ax,8102h	;"get version" (buffer size in SI::DI)
		int 4bh
		invoke printf, CStr("maximum dma buffer size after Int 4B, ax=8107: %lX",lf), si::di
endif

		mov di,offset dds_
		mov dds_.dwSize,1000h
		mov dds_.dwOfs,0
		mov dds_.wSeg, ds
		mov dx,0		;must be 0
		xor bx,bx		;bx:cx == offset in buffer
		xor cx,cx
		mov ax,8109h	;copy into DMA buffer
		int 4bh
		.if (CARRY?)
			cbw
			invoke printf, CStr("int 4B, ax=8109h [size=1000h] failed, AL=%X",lf), ax
		.else
			invoke printf, CStr("int 4B, ax=8109h [size=1000h] ok",lf)
		.endif

		mov di,offset dds_
		mov dx,0		;must be 0
		xor bx,bx		;bx:cx == offset in buffer
		xor cx,cx
		mov ax,810Ah	;copy out of DMA buffer
		int 4bh
		.if (CARRY?)
			cbw
			invoke printf, CStr("int 4B, ax=810Ah [size=1000h] failed, AL=%X",lf), ax
		.else
			invoke printf, CStr("int 4B, ax=810Ah [size=1000h] ok",lf)
		.endif

		mov dx,0		;dont copy out of buffer
		mov ax,8108h	;release DMA buffer
		int 4bh
		.if (CARRY?)
			cbw
			invoke printf, CStr("int 4B, ax=8108h failed, AL=%X",lf), ax
		.else
			invoke printf, CStr("int 4B, ax=8108h ok",lf)
		.endif
	.endif
	ret
DMABuffer endp

;--- several variants of 8105/8106: scatter/gather lock

ScatterGather proc

;--- 8105/8106: scatter/gather lock with PTEs, sufficient entries

	mov di,offset edds_
	mov [di].EDDS.dwSize,10000h
	mov [di].EDDS.dwOfs,0h
	mov [di].EDDS.wSeg,0C800h
	mov [di].EDDS.numAvl,16
	mov dx,40h
	mov ax,8105h
	int 4bh
	.if (CARRY?)
		cbw
		invoke printf, CStr("int 4B, ax=8105h, dx=40h reg=C800:10000 failed, AL=%X, size=%lX, numUsed=%X",lf),ax, es:[di].EDDS.dwSize, es:[di].EDDS.numUsed
	.else
		invoke printf, CStr("int 4B, ax=8105h, dx=40h reg=C800:10000 ok",lf)
		mov cx, es:[di].EDDS.numUsed
		lea si,[di+sizeof EDDS]
		.while cx
			lodsd
			push cx
			invoke printf, CStr("%lX "), eax
			pop cx
			dec cx
		.endw
		invoke printf, CStr(lf)
		mov dx,0
		mov ax,8106h
		int 4bh
		.if (CARRY?)
			cbw
			invoke printf, CStr("int 4B, ax=8106h failed, AL=%X",lf), ax
		.else
			invoke printf, CStr("int 4B, ax=8106h ok",lf)
		.endif
	.endif

;--- 8105/8106: scatter/gather lock with PTEs, insufficient entries

	mov di,offset edds_
	mov [di].EDDS.dwSize,10000h
	mov [di].EDDS.dwOfs,0h
	mov [di].EDDS.wSeg,0C800h
	mov [di].EDDS.numAvl,9h
	mov dx,40h
	mov ax,8105h
	int 4bh
	.if (CARRY?)
		cbw
		invoke printf, CStr("int 4B, ax=8105h, dx=40h reg=C800:10000 failed [good], AL=%X, size=%lX, numused=%X",lf), ax, es:[di].EDDS.dwSize, es:[di].EDDS.numUsed
	.else
		invoke printf, CStr("int 4B, ax=8105h, dx=40h reg=C800:10000 ok [bad]",lf)
		mov cx, es:[di].EDDS.numUsed
		lea si,[di+sizeof EDDS]
		.while cx
			lodsd
			push cx
			invoke printf, CStr("%lX "), eax
			pop cx
			dec cx
		.endw
		invoke printf, CStr(lf)
		mov dx,0
		mov ax,8106h
		int 4bh
		.if (CARRY?)
			cbw
			invoke printf, CStr("int 4B, ax=8106h failed, AL=%X",lf), ax
		.else
			invoke printf, CStr("int 4B, ax=8106h ok",lf)
		.endif
	.endif

;--- 8105/8106: scatter/gather lock with PTEs, region size 0

	mov di,offset edds_
	mov [di].EDDS.dwSize,0
	mov [di].EDDS.dwOfs,0F000h
	mov [di].EDDS.wSeg,0C000h
	mov [di].EDDS.numAvl,4h
	mov dx,40h
	mov ax,8105h
	int 4bh
	.if (CARRY?)
		cbw
		invoke printf, CStr("int 4B, ax=8105h, dx=40h reg=CF000:0 failed, AL=%X, size=%lX, numUsed=%X",lf), ax, es:[di].EDDS.dwSize, es:[di].EDDS.numUsed
	.else
		invoke printf, CStr("int 4B, ax=8105h, dx=40h reg=CF000:0 ok",lf)
		mov cx, es:[di].EDDS.numUsed
		lea si,[di+sizeof EDDS]
		.while cx
			lodsd
			push cx
			invoke printf, CStr("%lX "), eax
			pop cx
			dec cx
		.endw
		invoke printf, CStr(lf)
		mov dx,0
		mov ax,8106h
		int 4bh
		.if (CARRY?)
			cbw
			invoke printf, CStr("int 4B, ax=8106h failed, AL=%X",lf), ax
		.else
			invoke printf, CStr("int 4B, ax=8106h ok",lf)
		.endif
	.endif

;--- 8105/8106: scatter/gather lock without PTEs, size 64 kB

	mov di,offset edds_
	mov [di].EDDS.dwSize,10000h
	mov [di].EDDS.dwOfs,00h
	mov [di].EDDS.wSeg,0C800h
	mov [di].EDDS.numAvl,8
	mov dx,0
	mov ax,8105h
	int 4bh
	.if (CARRY?)
		cbw
		invoke printf, CStr("int 4B, ax=8105h, dx=0 reg=C800:10000 failed, AL=%X",lf), ax
	.else
		invoke printf, CStr("int 4B, ax=8105h, dx=0 reg=C800:10000 ok",lf)
		mov cx, es:[di].EDDS.numUsed
		lea si,[di+sizeof EDDS]
		.while cx
			lodsd
			mov edx, eax
			lodsd
			push cx
			invoke printf, CStr("%lX:%lX "), edx, eax
			pop cx
			dec cx
		.endw
		invoke printf, CStr(lf)
		mov dx,0
		mov ax,8106h
		int 4bh
		.if (CARRY?)
			cbw
			invoke printf, CStr("int 4B, ax=8106h failed, AL=%X",lf), ax
		.else
			invoke printf, CStr("int 4B, ax=8106h ok",lf)
		.endif
	.endif

;--- 8105/8106: scatter/gather lock without PTEs, size 5 byte

	mov di,offset edds_
	mov [di].EDDS.dwSize,5
	mov [di].EDDS.dwOfs,00h
	mov [di].EDDS.wSeg,0C800h
	mov [di].EDDS.numAvl,4
	mov dx,0
	mov ax,8105h
	int 4bh
	.if (CARRY?)
		cbw
		invoke printf, CStr("int 4B, ax=8105h, dx=0 reg=C800:5 failed, AL=%X",lf), ax
	.else
		invoke printf, CStr("int 4B, ax=8105h, dx=0 reg=C800:5 ok",lf)
		mov cx, es:[di].EDDS.numUsed
		lea si,[di+sizeof EDDS]
		.while cx
			lodsd
			mov edx, eax
			lodsd
			push cx
			invoke printf, CStr("%lX:%lX "), edx, eax
			pop cx
			dec cx
		.endw
		invoke printf, CStr(lf)
		mov dx,0
		mov ax,8106h
		int 4bh
		.if (CARRY?)
			cbw
			invoke printf, CStr("int 4B, ax=8106h failed, AL=%X",lf), ax
		.else
			invoke printf, CStr("int 4B, ax=8106h ok",lf)
		.endif
	.endif

;--- 8105/8106: scatter/gather lock without PTEs, size 2 byte, starting at CEFFF

	mov di,offset edds_
	mov [di].EDDS.dwSize,2
	mov [di].EDDS.dwOfs,0EFFFh
	mov [di].EDDS.wSeg,0C000h
	mov [di].EDDS.numAvl,4
	mov dx,0
	mov ax,8105h
	int 4bh
	.if (CARRY?)
		cbw
		invoke printf, CStr("int 4B, ax=8105h, dx=0 reg=CEFFF:2 failed, AL=%X",lf), ax
	.else
		invoke printf, CStr("int 4B, ax=8105h, dx=0 reg=CEFFF:2 ok",lf)
		mov cx, es:[di].EDDS.numUsed
		lea si,[di+sizeof EDDS]
		.while cx
			lodsd
			mov edx, eax
			lodsd
			push cx
			invoke printf, CStr("%lX:%lX "), edx, eax
			pop cx
			dec cx
		.endw
		invoke printf, CStr(lf)
		mov dx,0
		mov ax,8106h
		int 4bh
		.if (CARRY?)
			cbw
			invoke printf, CStr("int 4B, ax=8106h failed, AL=%X",lf), ax
		.else
			invoke printf, CStr("int 4B, ax=8106h ok",lf)
		.endif
	.endif

;--- 8105/8106: scatter/gather lock without PTEs, size 0 byte

	mov di,offset edds_
	mov [di].EDDS.dwSize,0
	mov [di].EDDS.dwOfs,0F000h
	mov [di].EDDS.wSeg,0C000h
	mov [di].EDDS.numAvl,4
	mov dx,0
	mov ax,8105h
	int 4bh
	.if (CARRY?)
		cbw
		invoke printf, CStr("int 4B, ax=8105h, dx=0 reg=CF000:0 failed, AL=%X",lf), ax
	.else
		invoke printf, CStr("int 4B, ax=8105h, dx=0 reg=CF000:0 ok",lf)
		mov cx, es:[di].EDDS.numUsed
		lea si,[di+sizeof EDDS]
		.while cx
			lodsd
			mov edx, eax
			lodsd
			push cx
			invoke printf, CStr("%lX:%lX "), edx, eax
			pop cx
			dec cx
		.endw
		invoke printf, CStr(lf)
		mov dx,0
		mov ax,8106h
		int 4bh
		.if (CARRY?)
			cbw
			invoke printf, CStr("int 4B, ax=8106h failed, AL=%X",lf), ax
		.else
			invoke printf, CStr("int 4B, ax=8106h ok",lf)
		.endif
	.endif
	ret
ScatterGather endp

main proc c

local	version:word
local	product:word
local	revision:word
local	dmasize:dword
local	flags:word

	xor ax, ax
	mov es, ax
	test byte ptr es:[47bh],20h
	jz novds
	mov ax,8102h
	mov dx,0000
	int 4bh
	jnc @F
novds:
	invoke printf, CStr("VDS not installed",lf)
	jmp exit
@@:
	mov version,ax
	mov product,bx
	mov revision,cx
	mov word ptr dmasize+0,di
	mov word ptr dmasize+2,si
	mov flags,dx
	invoke printf, CStr("version: %u.%u",lf), byte ptr version+1, byte ptr version+0
	invoke printf, CStr("product number/revision: %X/%X",lf), product, revision
	invoke printf, CStr("maximum dma buffer size: %lX",lf), dmasize
	invoke printf, CStr("flags: %X",lf), flags

	mov ax,ds
	mov es,ax

	call RsvdFunction
	invoke printf, CStr(lf)
	call LockUnlock
	invoke printf, CStr(lf)
	call DMABuffer
	invoke printf, CStr(lf)
	call ScatterGather

exit:
	ret
main endp

start:
	mov ax, @data
	mov ds, ax
	mov bx, ss
	sub bx, ax
	shl bx, 4
	mov ss, ax
	add sp, bx
	call main
	mov ah, 4Ch
	int 21h

	END start
