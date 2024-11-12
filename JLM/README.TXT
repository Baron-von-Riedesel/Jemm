
 1. About

 This directory contains some JLMs:

 AHCICD:   AHCI Optical disk driver.
 GENERIC:  protected-mode TSR sample in ASM (Masm/JWasm).
 HELLO:    "hello world" JLM in ASM (Masm/JWasm)
 HELLO2:   "hello world" JLM in C (MS VC, Open Watcom)
 IOTRAP:   sample how to trap IO port access.
 JCLOCK:   shows clock in text mode.
 KEYBGR:   German keyboard driver.
 QPIEMU:   emulates port trapping part of QPI.  
 XCDROM32: UltraDMA DVD/CD-ROM driver (GNU GPL 2).
 XDMA32:   UltraDMA HD driver (GNU GPL 2).

 GENERIC, HELLO, HELLO2, IOTRAP, JCLOCK, QPIEMU are Public Domain.


 2. Tools that may be used

 tools             version   result
 -----------------------------------------
 assembler:
 Masm               6.15      ok
 JWasm              2.15      ok
 Fasm               1.67      ok

 C compiler:
 MS VC              2/5/6     ok
 Borland C++        5.5       ok
 Ladsoft CC386      3.8.1.18  ok
 Digital Mars C++   8.49      ok
 Open Watcom WCC386 1.9       ok
 
 COFF linker:
 JWlink             1.9beta17 ok
 Open Watcom WLink  1.9       ok
 MS Link            6.00      ok

