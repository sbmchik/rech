BITS 64
default rel

extern _fopen, _fread, _fclose, _printf, SetConsoleCP, SetConsoleOutputCP

global platform_init
global platform_read_file
global platform_print

section .data
mode db "rb",0
fmt db "%s",10,0

section .bss
fileh resq 1

section .text

platform_init:
    mov ecx,65001
    call SetConsoleCP
    mov ecx,65001
    call SetConsoleOutputCP
    ret

platform_read_file:
    ; rcx = buffer

    mov rdx,[rdx+8]
    lea rcx,[rdx]
    lea rdx,[mode]
    call _fopen
    mov [fileh],rax

    mov r9,rax
    mov r8d,1048575
    mov edx,1
    call _fread

    mov byte [rcx+rax],0

    mov rcx,[fileh]
    call _fclose
    ret

platform_print:
    ; rcx = ptr
    lea rdx,[rcx]
    lea rcx,[fmt]
    call _printf
    ret