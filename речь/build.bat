@echo off
echo Assembling...

nasm -f win32 cursor.asm -o cursor.obj
nasm -f win32 lexer.asm -o lexer.obj
nasm -f win32 parser.asm -o parser.obj
nasm -f win32 runtime.asm -o runtime.obj
nasm -f win32 main.asm -o main.obj
nasm -f win32 tokens.asm -o tokens.obj
nasm -f win32 platform.asm -o platform.obj

echo Linking...

gcc -m32 -nostdlib -Wl,-e,_start -Wl,--subsystem,console -o main.exe main.obj cursor.obj lexer.obj parser.obj runtime.obj platform.obj tokens.obj -lshell32 -lkernel32

echo Done.
pause