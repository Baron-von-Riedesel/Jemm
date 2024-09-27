
;--- XMS definitions

XMS_GETVERSION   equ  0h
XMS_ENABLEA20    equ  5h
XMS_DISABLEA20   equ  6h
XMS_V2_QUERYMEM  equ  8h
XMS_V2_ALLOCEMB  equ  9h
XMS_FREEEMB      equ 0Ah
XMS_LOCKEMB      equ 0Ch
XMS_UNLOCKEMB    equ 0Dh
XMS_ALLOCUMB     equ 10h
XMS_V3_QUERYMEM  equ 88h
XMS_V3_ALLOCEMB  equ 89h

XMS_HANDLE struct
xh_flags    DB  ?
xh_locks    DB  ?
xh_baseK    DD  ?
xh_sizeK    DD  ?
XMS_HANDLE ends

LPXMS_HANDLE typedef ptr XMS_HANDLE

;--- XMS handle flags

XMSF_FREE   equ 1   ;handle describes a free EMB
XMSF_USED   equ 2   ;handle describes a used EMB
XMSF_INPOOL equ 4   ;handle is free


XMS_HANDLETABLE struct
xht_sig         DB  ?
xht_sizeof      DB  ?
xht_numhandles  DW  ?
xht_pArray      DD  ?   ;converted to linear address for 32bit code!
XMS_HANDLETABLE ends

XMS_MOVE struct
  len           dd  ?       ;  +0 block length in bytes
  src_handle    dw  ?       ;  +4 source handle
  src_offset    dd  ?       ;  +6 offset into source
  dest_handle   dw  ?       ; +10 destination handle
  dest_offset   dd  ?       ; +12 offset into destination
XMS_MOVE ends

if ?INTEGRATED
 if ?XMS35
XMS_MOVEX struct
                XMS_MOVE <>
  src_hi        db  ?       ; bits 32-39 of src
  dest_hi       db  ?       ; bits 32-39 of dst
XMS_MOVEX ends
 endif
endif

;--- XMS error codes

XMS_NOT_IMPLEMENTED             equ 80h
XMS_VDISK_DETECTED              equ 81h
XMS_A20_FAILURE                 equ 82h
XMS_DRIVER_FAILURE              equ 8eh
XMS_DRIVER_FATAL                equ 8fh
XMS_HMA_NOT_THERE               equ 90h
XMS_HMA_IN_USE                  equ 91h
XMS_HMAREQ_TOO_SMALL            equ 92h
XMS_HMA_NOT_USED                equ 93h
XMS_A20_STILL_ENABLED           equ 94h
XMS_ALL_MEM_ALLOCATED           equ 0a0h
XMS_NO_HANDLE_LEFT              equ 0a1h
XMS_INVALID_HANDLE              equ 0a2h
XMS_INVALID_SOURCE_HANDLE       equ 0a3h
XMS_INVALID_SOURCE_OFFSET       equ 0a4h
XMS_INVALID_DESTINATION_HANDLE  equ 0a5h
XMS_INVALID_DESTINATION_OFFSET  equ 0a6h
XMS_INVALID_LENGTH              equ 0a7h
XMS_INVALID_OVERLAP             equ 0a8h
XMS_PARITY_ERROR                equ 0a9h
XMS_BLOCK_NOT_LOCKED            equ 0aah
XMS_BLOCK_LOCKED                equ 0abh
XMS_LOCK_COUNT_OVERFLOW         equ 0ach
XMS_LOCK_FAILED                 equ 0adh
XMS_ONLY_SMALLER_UMB            equ 0b0h
XMS_NO_UMB_AVAILABLE            equ 0b1h
XMS_UMB_SEGMENT_NR_INVALID      equ 0b2h

