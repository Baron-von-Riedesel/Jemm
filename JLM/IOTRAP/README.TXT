
 1. About

 IOTRAP is a JLM sample which demonstrates how to trap IO port access.


 2. How to install and uninstall IOTRAP

 IOTRAP can be installed either as a device driver in CONFIG.SYS:

   DEVICE=JLOAD.EXE IOTRAP.DLL

 or as a TSR from the command line:

   JLOAD IOTRAP.DLL

 To uninstall, use JLOAD's -u option:

   JLOAD -u IOTRAP.DLL


 3. How to test IOTRAP

  - install IOTRAP:  C:\>JLOAD iotrap.dll
  - install TESTIOT: C:\>testiot
  - start DEBUG:     C:\>debug
  - read port 100:   -i 100

  now a colored string '*#!+' should appear on line 25.


 4. License

 IOTRAP is Public Domain.

 Japheth

