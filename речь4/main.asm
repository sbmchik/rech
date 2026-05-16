BITS 32

extern _fopen, _fread, _fclose
extern _printf
extern _SetConsoleCP@4
extern _SetConsoleOutputCP@4

extern cur_init
extern cur_ptr, endptr, line_no, col_no
extern parser_run

global _main

section .data
mode            db "rb", 0
usage_msg       db "Использование: main.exe <файл>", 10, 0
open_fail_msg   db "Не удалось открыть файл", 10, 0

section .bss
buffer  resb 1048576
fileh   resd 1

section .text

_main:
    push ebp
    mov ebp, esp

    push 65001
    call _SetConsoleCP@4
    add esp, 4

    push 65001
    call _SetConsoleOutputCP@4
    add esp, 4

    mov eax, [ebp+8]
    cmp eax, 2
    jl .usage

    mov eax, [ebp+12]
    mov eax, [eax+4]        ; argv[1]

    push mode
    push eax
    call _fopen
    add esp, 8

    test eax, eax
    jz .open_fail
    mov [fileh], eax

    push dword [fileh]
    push 1048575
    push 1
    push buffer
    call _fread
    add esp, 16

    mov ecx, eax
    mov eax, buffer
    mov [cur_ptr], eax
    add eax, ecx
    mov [endptr], eax
    mov byte [eax], 0

    mov dword [line_no], 1
    mov dword [col_no], 1

    mov eax, [cur_ptr]
    cmp eax, [endptr]
    jae .parse

    cmp byte [eax], 0EFh
    jne .parse
    cmp byte [eax+1], 0BBh
    jne .parse
    cmp byte [eax+2], 0BFh
    jne .parse

    add eax, 3
    mov [cur_ptr], eax
    add dword [col_no], 3

.parse:
    mov eax, buffer
    call cur_init

    call parser_run
    mov ebx, eax

    push dword [fileh]
    call _fclose
    add esp, 4

    mov eax, ebx
    jmp .exit

.usage:
    push usage_msg
    call _printf
    add esp, 4
    mov eax, 1
    jmp .exit

.open_fail:
    push open_fail_msg
    call _printf
    add esp, 4
    mov eax, 1

.exit:
    mov esp, ebp
    pop ebp
    ret