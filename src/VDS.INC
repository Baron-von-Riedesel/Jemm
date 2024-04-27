
;--- VDS definitions

;--- flags in DX used by various VDS functions

VDSF_COPY       equ 02h	;bit 1
VDSF_NOBUFFER   equ 04h	;bit 2
VDSF_NOREMAP    equ 08h	;bit 3 - Jemm ignores this flag!
VDSF_64KALIGN   equ 10h	;bit 4
VDSF_128KALIGN  equ 20h	;bit 5
VDSF_PTE        equ 40h	;bit 6 - 1=scatter_lock returns PTEs 
VDSF_NPPTE      equ 80h	;bit 7 - allow non-present pages for scatter/gather remap

;--- error codes returned in AL by lock (8103)

VDSERR_NOTCONTIGUOUS equ 1	;region not in contiguous memory
VDSERR_CROSSEDBOUNDS equ 2	;region crossed alignemnt boundary
VDSERR_CANTLOCKPAGES equ 3	;
VDSERR_NOBUFFER      equ 4	; 8107
VDSERR_BUFFTOOSMALL  equ 5	; 8107
VDSERR_BUFFINUSE     equ 6	; 

;--- other VDS error codes

VDSERR_07            equ 7	; invalid memory region (8107)
VDSERR_REG_NOTLOCKED equ 8	; region wasn't locked (8106)
VDSERR_NAVL_TOOSMALL equ 9	; # of phys pages was > than table length (8105)
VDSERR_INVAL_BUFFID  equ 10	; invalid buffer ID (8108,8109,810A)
VDSERR_BNDVIOLATION  equ 11	; buffer boundary violated (8109,810A)
VDSERR_INVAL_DMACHN  equ 12	; invalid DMA channel # (810B, 810C)
VDSERR_DISCNTOVFL    equ 13	; disable cnt overflow (810B)
VDSERR_DISCNTUNFL    equ 14	; disable cnt underflow (810C)
VDSERR_FUNC_NOTSUPP  equ 15	; function not supported
VDSERR_DXRSVDBITSSET equ 16	; reserved flag bits set in DX (8102,8106,8108,8109,810A,810B,810C)

;--- DDS, used by 03-04, 07-08, 09-0A

DDS struct
dwSize  dd ?    ;+0  size of region
dwOfs   dd ?    ;+4  offset virtual start address
wSeg    dw ?    ;+8  segment/selector virtual start address (or 0000)
wID     dw ?    ;+10 buffer ID
dwPhys  dd ?    ;+12 physical address
DDS ends

;--- EDDS, used by 05-06

EDDS struct
dwSize  dd ?    ;+0
dwOfs   dd ?    ;+4
wSeg    dw ?    ;+8
wRes    dw ?    ;+10
wNumAvail   dw ?    ;+12
wNumUsed    dw ?    ;+14
EDDS ends

;--- EDDS suffix for regions

EDDSRG struct
dwPhysAddr  dd ?    ;+16
dwSizeRg    dd ?    ;+20
EDDSRG ends

;--- EDDS suffix for PTEs

EDDSPT struct
dwPTE       dd ?    ;+16
EDDSPT ends

