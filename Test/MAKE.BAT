@echo off
rem the programs may all be created without link step,
rem using jwasm's -mz option
jwasm -mz %1.asm
