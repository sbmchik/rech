BITS 32

extern parser_run
extern cur_init
extern rt_init
extern rt_error_string
extern platform_init
extern platform_read_file

extern _GetCommandLineW@0
extern _CommandLineToArgvW@8
extern _LocalFree@4
extern _GetFullPathNameW@16
extern _ExitProcess@4

global _start

section .data
msg_usage db "main.exe <имя файла>"
msg_usage_len equ $ - msg_usage

msg_open_fail db "Ошибка: не удалось открыть файл."
msg_open_fail_len equ $ - msg_open_fail

section .bss
buffer      resb 1048576
fullpathbuf resw 1024
argc        resd 1

section .text

_start:
    call platform_init
    call rt_init

    call _GetCommandLineW@0
    test eax, eax
    jz .usage

    push argc
    push eax
    call _CommandLineToArgvW@8
    test eax, eax
    jz .usage

    mov ebx, eax              ; argv array pointer
    mov ecx, [argc]
    cmp ecx, 2
    jb .free_and_usage

    mov esi, [ebx+4]          ; argv[1]

    push dword 0
    push dword fullpathbuf
    push dword 1024
    push esi
    call _GetFullPathNameW@16
    test eax, eax
    jz .free_and_openfail
    cmp eax, 1024
    jae .free_and_openfail

    push dword 1048576
    push dword buffer
    push dword fullpathbuf
    call platform_read_file
    add esp, 12

    cmp eax, -1
    je .free_and_openfail

    mov eax, buffer

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

    push ebx
    call _LocalFree@4

    push eax
    call _ExitProcess@4

.free_and_usage:
    push ebx
    call _LocalFree@4

.usage:
    push dword msg_usage_len
    push dword msg_usage
    call rt_error_string
    add esp, 8

    push dword 1
    call _ExitProcess@4

.free_and_openfail:
    push ebx
    call _LocalFree@4

.open_fail:
    push dword msg_open_fail_len
    push dword msg_open_fail
    call rt_error_string
    add esp, 8

    push dword 1
    call _ExitProcess@4