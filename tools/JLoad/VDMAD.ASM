
;--- VDMAD support
;--- best viewed with TAB size 4

	.386
	.model flat

	option casemap:none
	option proc:private

	include ..\jemm.inc
	include ..\jemm32.inc
	include jlm.inc
	include jload32.inc
	include debug.inc

;--- structure of the VDS call table in Jemm

VDSCALL struct
			dd ?	;EBP -> client (not used here)
pLock		dd ?	;EDI -> DDS, DX (not used here)
pUnlock		dd ?	;EDI -> DDS, DX, modifies EBX!
pScLock		dd ?	;EDI -> EDDS, DX, modifies EBX, ESI!
pScUnlock	dd ?	;EDI -> EDDS, DX (does nothing)
pReqBuffer	dd ?	;EDI -> DDS, DX, modifies EBX!
pRelBuffer	dd ?	;EDI -> DDS, DX, modifies EBX!
			dd ?	;copy in  EDI -> DDS, DX, EBP -> client
			dd ?	;copy out EDI -> DDS, DX, EBP -> client
			dd ?	;disable translation
			dd ?	;enable translation
pCopyInBuf	dd ?	;copy in  EDI -> DDS, DX, ECX, modifies EBX!
pCopyOutBuf dd ?	;copy out EDI -> DDS, DX, ECX, modifies EBX!
VDSCALL ends

DATA_	segment dword public 'CODE'

ddb_0004 VxD_Desc_Block <    0,1,4,1,0,0,"        ",0,0,0,0,0,0,0,offset vdmad_services,?NUMSERV0004>
    
;--- VDMAD service table

vdmad_services label dword
	dd Get_VDMAD_Version
	dd Lock_DMA_Region
	dd Unlock_DMA_Region
	dd Scatter_Lock
	dd Scatter_Unlock
	dd Request_Buffer
	dd Release_Buffer
	dd Copy_To_Buffer		;new v5.69
	dd Copy_From_Buffer		;new v5.69
?NUMSERV0004 equ ($ - vdmad_services)/4        

DATA_	ends

	.code

;--- VDMA device functions

Get_VDMAD_Version proc
	mov eax,100h
	clc
	ret
	align 4

Get_VDMAD_Version endp

;--- esi = start region
;--- ecx = size region
;--- dl = flags (bit 0: check for 64 kB crossing)
;--- returns phys address in EDX if ok
;--- returns size in ECX on error

;--- Jemm is unable to handle addresses > 110000h
;--- therefore do it here.

Lock_DMA_Region proc uses esi edi ebx

	lea ebx, [esi+ecx-1]	;let EBX point to the last byte
	mov eax, esi
	shr eax, 12
	shr ebx, 12
	sub ebx, eax
	jc @@error2

	shr esi, 12
	lea esi, [esi*4 + (?PAGEMAP shl 22)]
	mov ecx, ebx
	lodsd
	and ax,0F000h
	mov bl,dl
	mov edx, eax
	jecxz @@done
	mov edi,edx		;save first phys page in EDX
	.while (ecx)
		lodsd
		and eax, eax
		jz @@error
		and ax, 0F000h
		add edi,1000h
		cmp eax, edi
		jnz @@error
		dec ecx
	.endw
	test bl,1		;64 kB border crossing test?
	jz @@done
	mov eax, edx
	shr eax, 16
	shr edi, 16
	cmp eax, edi
	jnz @@error2
@@done:
	mov eax,[esp+2*4]	;get original ESI
	and ax,0FFFh
	or	dx,ax
	ret
@@error:
	sub ebx,ecx
	mov ecx,ebx
	shl ecx,12
	stc
	ret
@@error2:
	xor ecx, ecx
	stc
	ret
	align 4
Lock_DMA_Region endp

;--- esi = start region
;--- ecx = size region
;--- dl = flags

Unlock_DMA_Region proc uses esi edi ebx
	sub esp, size DDS
	mov edi, esp
	mov [edi].DDS.dwSize, ecx
	mov [edi].DDS.dwOfs, esi
	mov dword ptr [edi].DDS.wSeg, 0		;clear wSeg and wID
	mov dh,0
	shr dl,4
	mov eax,[VDS_Call_Table]
	call [eax].VDSCALL.pUnlock			;call vds_unlock
	lea esp,[esp+size DDS]
	ret
	align 4

Unlock_DMA_Region endp

;--- edi = DDS
;--- al = flags

Scatter_Lock proc uses esi ebx
	xor edx,edx
	test al,1
	jz @F
	or dl,VDSF_PTE
@@:
	mov eax,[VDS_Call_Table]
	call [eax].VDSCALL.pScLock
	ret
	align 4
Scatter_Lock endp

;--- edi = DDS
;--- al = flags

Scatter_Unlock proc
	xor edx,edx
	mov eax,[VDS_Call_Table]
	call [eax].VDSCALL.pScUnlock	;this is a dummy
	ret
	align 4
Scatter_Unlock endp

;--- esi = region
;--- ecx = size
;--- out: ebx=id, edx=phys. addr

Request_Buffer proc uses esi edi
	sub esp, size DDS
	mov edi, esp
	mov [edi].DDS.dwSize, ecx
	mov [edi].DDS.dwOfs, esi
	xor edx,edx
	mov dword ptr [edi].DDS.wSeg, edx
	mov eax,[VDS_Call_Table]
	call [eax].VDSCALL.pReqBuffer
	jc @F
	movzx ebx,[edi].DDS.wID
	mov edx,[edi].DDS.dwPhys
@@:
	lea esp,[esp+size DDS]
	ret
	align 4
Request_Buffer endp

;--- ebx = id

Release_Buffer proc uses ebx edi
	sub esp, size DDS
	mov edi, esp
	mov [edi].DDS.wID, bx
	xor edx,edx					;no NOT copy out of DMA buffer!
	mov eax,[VDS_Call_Table]
	call [eax].VDSCALL.pRelBuffer
	lea esp,[esp+size DDS]
	ret
	align 4
Release_Buffer endp

;--- ebx = id
;--- esi = offset src
;--- edi = buffer offset 
;--- ecx = buffer size

Copy_To_Buffer proc uses ebx esi edi

	sub esp, size DDS
	mov [esp].DDS.dwSize, ecx
	mov ecx, edi
	mov edi, esp
	mov [edi].DDS.dwOfs, esi
	xor edx,edx
	mov [edi].DDS.wSeg, dx
	mov [edi].DDS.wID, bx
	mov eax,[VDS_Call_Table]
	call [eax].VDSCALL.pCopyInBuf
	lea esp,[esp+size DDS]
	ret
	align 4
Copy_To_Buffer endp

;--- ebx = id
;--- esi = offset src
;--- edi = buffer offset 
;--- ecx = buffer size

Copy_From_Buffer proc uses ebx esi edi
	sub esp, size DDS
	mov [esp].DDS.dwSize, ecx
	mov ecx, edi
	mov edi, esp
	mov [edi].DDS.dwOfs, esi
	xor edx,edx
	mov [edi].DDS.wSeg, dx
	mov [edi].DDS.wID, bx
	mov eax,[VDS_Call_Table]
	call [eax].VDSCALL.pCopyOutBuf
	lea esp,[esp+size DDS]
	ret
	align 4
Copy_From_Buffer endp

	end


