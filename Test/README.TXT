
bmintrm:    benchmark int 69h real-mode
ems4e:      get/set page map
ems4f:      get/set partial page map
ems56:      alter map and call
ems57:      EMS copy
ems57a:     copy EMS to EMS, 1 MB
ems5b:      alternate map register set
exc00:      v86 divide error
exc06:      v86 invalid opcode exception
frameres:   reset page frame mapping to a known value
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
xmstest3:   test XMS functions 0Eh/8Eh (get handle information)
xmstest4:   test XMS resize function 8Fh
xmstest5:   test XMS resize function 0Fh

Debug scripts:
test0c.deb  test stack exception 0Ch
test0c1.deb test stack exception 0Ch
test0d.deb  test GPF
test10.deb  test floating point exception 10h
test11.deb  test alignment check exception 11h
