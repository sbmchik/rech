BITS 32

extern parser_run
extern cur_init
extern rt_init
extern rt_error_string
extern platform_init
extern platform_read_file
extern platform_last_error
extern platform_last_stage

extern _GetCommandLineW@0
extern _CommandLineToArgvW@8
extern _LocalFree@4
extern _ExitProcess@4

global _start

section .data
msg_usage db "main.exe <имя файла>"
msg_usage_len equ $ - msg_usage

msg_open_fail db "Ошибка: не удалось открыть/прочитать файл. stage="
msg_open_fail_len equ $ - msg_open_fail

msg_err db " Win32 code="
msg_err_len equ $ - msg_err

msg_nl db 13, 10
msg_nl_len equ $ - msg_nl

section .bss
argc        resd 1
input_ptr   resd 1
int_buf      resb 16

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

    mov ebx, eax
    mov ecx, [argc]
    cmp ecx, 2
    jb .free_and_usage

    mov esi, [ebx+4]              ; argv[1]

    push esi
    call platform_read_file
    add esp, 4

    cmp eax, -1
    je .free_and_openfail

    mov esi, eax                  ; ESI = buffer with file contents

    cmp byte [esi], 0EFh
    jne .store_ptr
    cmp byte [esi+1], 0BBh
    jne .store_ptr
    cmp byte [esi+2], 0BFh
    jne .store_ptr
    add esi, 3

.store_ptr:
    mov [input_ptr], esi

    mov eax, esi
    call cur_init

    mov eax, [input_ptr]
    call parser_run
    mov edi, eax

    push ebx
    call _LocalFree@4

    push edi
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

    push dword msg_open_fail_len
    push dword msg_open_fail
    call rt_error_string
    add esp, 8

    mov eax, [platform_last_stage]
    call u32_to_dec
    push ecx
    push eax
    call rt_error_string
    add esp, 8

    push dword msg_err_len
    push dword msg_err
    call rt_error_string
    add esp, 8

    mov eax, [platform_last_error]
    call u32_to_dec
    push ecx
    push eax
    call rt_error_string
    add esp, 8

    push dword msg_nl_len
    push dword msg_nl
    call rt_error_string
    add esp, 8

    push dword 1
    call _ExitProcess@4

; eax = unsigned int
; returns:
;   eax = pointer to first digit
;   ecx = length
u32_to_dec:
    push ebx
    push edx
    push edi

    lea edi, [int_buf + 15]
    mov byte [edi], 0
    xor ecx, ecx
    mov ebx, 10

    cmp eax, 0
    jne .loop

    dec edi
    mov byte [edi], '0'
    mov ecx, 1
    jmp .done

.loop:
    xor edx, edx
    div ebx
    add dl, '0'
    dec edi
    mov [edi], dl
    inc ecx
    test eax, eax
    jnz .loop

.done:
    mov eax, edi
    pop edi
    pop edx
    pop ebx
    ret