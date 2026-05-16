BITS 32

extern _fopen, _fread, _fclose
extern parser_run
extern cur_init

global _main

section .data
mode db "rb",0

section .bss
buffer resb 1048576
fileh resd 1

section .text

_main:
    push ebp
    mov ebp, esp

    ; argv
    mov eax, [ebp+12]
    mov eax, [eax+4]

    push mode
    push eax
    call _fopen
    add esp,8

    mov [fileh], eax

    push eax
    push 1048575
    push 1
    push buffer
    call _fread
    add esp,16

    mov byte [buffer+eax], 0

    mov eax, buffer
    call cur_init

    call parser_run

    push dword [fileh]
    call _fclose
    add esp,4

    mov esp, ebp
    pop ebp
    ret