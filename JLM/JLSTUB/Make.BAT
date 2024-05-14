@echo off
if not exist Build\NUL mkdir Build
jwasm -nologo -mz -FlBuild\ -Fo=Build\jlstub.bin jlstub.asm
