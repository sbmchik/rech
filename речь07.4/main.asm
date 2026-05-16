BITS 32

extern _fopen, _fread, _fclose
extern parser_run
extern cur_init
extern rt_init
extern rt_error_string

global _main

section .data
mode db "rb",0

msg_usage db "main.exe <имя файла>"
msg_usage_len equ $ - msg_usage

msg_open_fail db "Ошибка: не удалось открыть файл."
msg_open_fail_len equ $ - msg_open_fail

section .bss
buffer resb 1048576
fileh  resd 1

section .text

_main:
    push ebp
    mov ebp, esp
    cld

    call rt_init

    mov eax, [ebp+8]        ; argc
    cmp eax, 2
    jb .usage

    mov eax, [ebp+12]       ; argv
    mov eax, [eax+4]        ; argv[1]

    push mode
    push eax
    call _fopen
    add esp, 8

    test eax, eax
    jz .open_fail

    mov [fileh], eax

    push eax
    push 1048575
    push 1
    push buffer
    call _fread
    add esp, 16

    mov byte [buffer+eax], 0

    mov eax, buffer

    ; UTF-8 BOM skip, если файл сохранён с BOM
    cmp byte [eax], 0EFh
    jne .init_cur
    cmp byte [eax+1], 0BBh
    jne .init_cur
    cmp byte [eax+2], 0BFh
    jne .init_cur
    add eax, 3

.init_cur:
    call cur_init

    call parser_run
    mov ebx, eax

    push dword [fileh]
    call _fclose
    add esp, 4

    mov eax, ebx
    jmp .done

.usage:
    push dword msg_usage_len
    push dword msg_usage
    call rt_error_string
    add esp, 8
    mov eax, 1
    jmp .done

.open_fail:
    push dword msg_open_fail_len
    push dword msg_open_fail
    call rt_error_string
    add esp, 8
    mov eax, 1

.done:
    mov esp, ebp
    pop ebp
    ret
