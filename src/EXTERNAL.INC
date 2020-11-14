
;--- publics for Jemm32

@seg macro name_, align_
name_ SEGMENT align_ FLAT public 'CODE'
endm

@seg .text$01,<DWORD>
externdef GDT_PTR:fword
externdef IDT_PTR:fword
externdef V86CR3:dword
externdef V86GDT:descriptor
externdef dwStackCurr:dword
if ?DYNTRAPP60
externdef dwTSS:dword
endif
externdef dwMaxPhysMem:dword
externdef PageMapHeap:dword
externdef dwMaxMem4K:dword
externdef dwUsedMem4K:dword
externdef dwRes:dword
externdef dwRSeg:dword
if ?HOOK13
externdef dwRFlags:dword
else
externdef bDiskIrq:byte
endif
externdef bpstart:dword
externdef wMasterPICBase:word
externdef wSlavePICBase:word
externdef DMABuffStartPhys:dword
externdef bNoInvlPg:byte
externdef bV86Flags:byte
externdef DmaChn:DMAREQ
externdef bBpTab:byte
externdef bNoPool:byte
externdef OldInt06:dword
if ?SAFEKEYBOARD
externdef OldInt16:dword
endif
externdef OldInt19:dword
externdef OldInt67:dword

externdef pSavedVecs:dword
externdef dwV86IDT:dword
externdef dwFeatures:dword
externdef bIs486:byte
externdef bPageMask:byte
externdef bBpBack:byte

externdef EMSPageAllocationStart:dword
externdef EMSPageAllocationEnd:dword
externdef bNoEMS:byte
externdef bNoFrame:byte
externdef bNoVCPI:byte
externdef EMSPage2Segm:byte
externdef EMSPagesMax:dword

externdef bNoA20:byte
externdef XMS_Handle_Table:XMS_HANDLETABLE
externdef UMBsegments:UMBBLK
if ?INTEGRATED
externdef A20Index:BYTE
else
externdef XMSCtrlHandle:WORD
endif

externdef DMABuffSize:dword
externdef DMABuffStart:dword
externdef DMABuffFree:dword

.text$01 ENDS

@seg .text$03,<DWORD>

;--- Jemm32 publics

externdef int00:near
externdef V86_Monitor:near
externdef Begin_Nest_Exec:near
externdef End_Nest_Exec:near
externdef Simulate_Far_Call:near
externdef Simulate_Far_Ret:near
externdef Simulate_Iret:near
externdef Resume_Exec:near
externdef Yield:near
externdef Simulate_IO:near
externdef MoveMemoryPhys:near
if ?XMS35COMPAT
externdef MoveMemoryPhysEx:near
endif
externdef MapPhysPages:near
externdef MapPhysPagesEx:near
externdef MoveMemory:near
externdef EnableInts:near
externdef DisableInts:near
if ?EXC10
externdef Int10_Entry:near
endif
externdef Int15_Entry:near
externdef Int15_Entry_Ex:near
externdef SetVME:near
externdef V86_Exc0D:near

externdef VPRINTSTR:near
externdef VPUTCHR:near
externdef VDWORDOUT:near
externdef VWORDOUT:near
externdef VBYTEOUT:near

;--- EMS/VCPI publics

externdef VCPI_Call_Table:dword
externdef VCPI_V86toPM:near
externdef Int67_Entry:near
externdef Int67_V86Entry:near

;--- XMS/A20 publics

externdef umb_handler:near
externdef xms_handler:near
externdef A20_Set:near
externdef A20_Handle60:near
externdef A20_Handle64:near
externdef A20_Handle92:near

;--- VDS publics

externdef vds_handler:near
externdef VDS_Call_Table:dword
externdef VDS_Exit:near

;--- Pool publics

externdef Pool_GetFree4KPages:near
externdef Pool_GetFree16KPages:near
externdef Pool_Allocate4KPage:near
externdef Pool_Allocate16KPage:near
externdef Pool_Free4KPage:near
externdef Pool_Free16KPage:near
externdef Pool_FreeAllBlocks:near
externdef Pool_AllocBlocksForEMB:near
externdef Pool_GetPhysAddr:near

;--- DMA translation publics

externdef Dma_CopyBuffer:near
externdef Dma_HandleDmaPorts8:near
externdef Dma_HandleDmaPorts16:near
externdef Dma_HandlePagePorts:near

externdef ExtendedOp:near

externdef I15_Simulate87:near

.text$03 ENDS

@seg .text$04,<DWORD>
externdef HeapMalloc:near
externdef SetEMSHandleTable:near
externdef SetEMSStateTable:near
externdef XMS_Init:near
externdef Debug_Init:near
externdef EMS_Init1:near
externdef EMS_Init2:near
externdef VDS_Init:near
externdef Pool_Init1:near
externdef Pool_Init2:near
externdef InitMonitor:near
externdef EMMXXXX0_Strategy:near
externdef EMMXXXX0_Interrupt:near
externdef vmm_service_table:VMM_SERV_TABLE
externdef bptable:BPTABLE
.text$04 ends

