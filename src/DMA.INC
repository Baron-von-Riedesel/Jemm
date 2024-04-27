
;--- ports ISA DMA controller

DMA_STATUS_CMD     equ 8	; R status / W command
DMA_REQUEST        equ 9	; W b0+1: channel, b2: 1=enable?, b3-7:rsvd
DMA_SINGLEMASK     equ 10	; W b0+1: channel to mask, b2: 0=clear/1=mask, b3-7:rsvd
DMA_MODE           equ 11	; W b0+1: channel, b2-7:see below
DMA_FLIPFLOP       equ 12	; W
DMA_IMM_RESET      equ 13	; R immediate / W master reset
DMA_MASK_RESET     equ 14	; W master enable
DMA_MULTIMASK      equ 15	; W master mask b0-3: channel

;--- bits in DMA_MODE
DMA_MODE_OPERATION equ 0Ch	; "op" bits 2+3
DMA_MODE_OP_VERIFY equ 00h
DMA_MODE_OP_WRITE  equ 04h
DMA_MODE_OP_READ   equ 08h
DMA_MODE_AUTO      equ 10h	; b4
DMA_MODE_DIRECTION equ 20h	; b5: direction 0=increment, 1=decrement
;--- b6-7: 00=demand,01=single,10=block,11=cascade

DMA_BASE_16BIT     equ 0C0h

DMA_STATUS_CMD16   equ DMA_BASE_16BIT + DMA_STATUS_CMD*2
DMA_SINGLEMASK16   equ DMA_BASE_16BIT + DMA_SINGLEMASK*2
DMA_MODE16         equ DMA_BASE_16BIT + DMA_MODE*2
DMA_FLIPFLOP16     equ DMA_BASE_16BIT + DMA_FLIPFLOP*2
DMA_IMM_RESET16    equ DMA_BASE_16BIT + DMA_IMM_RESET*2
DMA_MASK_RESET16   equ DMA_BASE_16BIT + DMA_MASK_RESET*2
DMA_MULTIMASK16    equ DMA_BASE_16BIT + DMA_MULTIMASK*2
