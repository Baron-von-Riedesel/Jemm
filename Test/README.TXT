
bmintrm:    benchmark int 69h real-mode
ems4e:      get/set page map
ems4f:      get/set partial page map
ems56:      alter map and call
ems57:      EMS copy
ems57a:     copy EMS to EMS, 1 MB
ems5b:      alternate map register set
hlttest:    emulation of HLT, IF=1
hlttest2:   emulation of HLT, IF=0
i15move:    move block using int 15h, ah=87h
testdma:    read FD in UMB, using int 25h
testdma2:   read FD in UMB, using int 13h
testdma3:   read FD in UMB, using int 13h, ensured that DMA buffer/PTE remap must be used.
testvds:    run various VDS API calls
testvds2:   test VDS API calls 810B/810C for DMA channel 2
testvds3:   test 810B/810C for all channels
xmstest:    XMS memory moves
xmstest2:   XMS block allocation
