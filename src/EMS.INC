
;--- EMS status codes

EMSS_OK                 equ 00h
EMSS_SOFTWARE_ERR       equ 80h ;unexpected error
EMSS_HARDWARE_ERR       equ 81h ;should never occur with EMM emulators
EMSS_EMM_BUSY           equ 82h ;should never occur with EMS 3.2+
EMSS_INVALID_HANDLE     equ 83h
EMSS_INVALID_FUNCTION   equ 84h ;function code in AH not defined
EMSS_NO_MORE_HANDLES    equ 85h ;all handles in use
EMSS_CONTEXT_EXISTS     equ 86h ;45h: try to free a handle with saved context
EMSS_OUT_OF_PAGES       equ 87h ;43h, 51h, 5A00h, 5A01h
EMSS_OUT_OF_FREE_PAGES  equ 88h ;43h, 51h, 5A00h, 5A01h
EMSS_ZERO_PAGES         equ 89h ;43h
EMSS_LOG_PAGE_INVALID   equ 8Ah ;44h, 50h, 55h, 56h, 57h
EMSS_PHYS_PAGE_INVALID  equ 8Bh ;44h, 4Fh, 50h, 55h, 56h
EMSS_CONTEXT_STACK_FULL equ 8Ch ;46h
EMSS_STATE_ALREADY_SAVED equ 8Dh;47h
EMSS_NO_STATE_IS_SAVED  equ 8Eh ;48h
EMSS_INVALID_SUBFUNC    equ 8Fh ;4Eh, 4Fh, 50h, 52h, 53h, 54h, 57h, 58h, 59h, 5Bh
EMSS_UNDEF_ATTR_TYPE    equ 90h ;
EMSS_FEATURE_UNSUPP     equ 91h ;52h
EMSS_OVERLAP_OCCURED    equ 92h ;5700h
EMSS_LENGTH_EXCEEDED    equ 93h ;57h
EMSS_CONVEMS_OVERLAPP   equ 94h ;57h (jemm never returns this code)
EMSS_OFFS_EXCEEDS_PGSIZ equ 95h ;57h
EMSS_REGLEN_EXCEEDS_1MB equ 96h ;57h
EMSS_REGIONS_OVERLAPP   equ 97h ;5701h
EMSS_TYPE_UNDEFINED     equ 98h ;57h
EMSS_ALT_MAPS_UNSUPP    equ 9Ch ;5B01h, 5B04h, 5B06h, 5B07h, 5B08h
EMSS_INVALID_ALT_MAP    equ 9Dh ;5Bh (jemm never returns this code)
EMSS_MBBOUNDARY_CROSSED equ 0A2h;57h
EMSS_SRC_ARRAY_INVALID  equ 0A3h;4E01h, 5B01h
EMSS_ACCESS_DENIED      equ 0A4h;5Bh

