
 1. About

 GENERIC is a JLM sample which demonstrates how to implement a
 protected-mode TSR.


 2. How to install and uninstall GENERIC

 GENERIC can be installed either as a device driver in CONFIG.SYS:

   DEVICE=JLOAD.EXE GENERIC.DLL

 or as a TSR from the command line:

   JLOAD GENERIC.DLL

 To uninstall, use JLOAD's -u option:

   JLOAD -u GENERIC.DLL


 3. How to use GENERIC

 GENERIC doesn't hook real-mode interrupt vectors. If a real-mode program
 wants to call a function provided by GENERIC, it first has to get the JLM's
 entry point. This is done similiar to Windows 9x: a call of Int 2F, 
 AX=1684h with register BX containing the "device id". On return, if the
 "device" has been found, ES:DI will contain its entry address:
 
  mov ax, 1684h   ;standard value to get VxD entry points
  mov bx, 6660h   ;6660h is the ID of GENERIC
  int 2Fh
  cmp al,0
  jnz not_installed
  mov word ptr [genpm+0],di
  mov word ptr [genpm+2],es

 The protected-mode TSR implements two functions, which are selected
 by the value of register AX:

  mov ax, 0000             ;0000=get version
  call dword ptr [genpm]

  mov ax, 0001             ;0001=display hello
  call dword ptr [genpm]

 There's a test program - TESTGEN.EXE - supplied which uses GENERIC.


 4. License

 GENERIC is Public Domain.

 Japheth

