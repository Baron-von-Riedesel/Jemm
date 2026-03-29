#!/bin/sh
set -e
# uses Open Watcom C, JWAsm and JWLink which must be in PATH
# OW needs a helper module: jlmw.obj
jwasm -I../../Include JLMW.ASM
wcc386 -mf -zl -zls -s -I../../Include HELLO2W.C
jwlink format win nt hx ru native file HELLO2W.o, JLMW.o name hello2w.exe option start=main_, map

