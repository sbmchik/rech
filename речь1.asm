; main.asm
; nasm -f win64 main.asm -o main.obj
; gcc main.obj -o main.exe

BITS 64
default rel

extern fopen, fread, fclose, printf, SetConsoleCP, SetConsoleOutputCP
global main

%macro ADVANCE_ONE 0
    mov     rax, [curptr]
    mov     dl, [rax]
    inc     rax
    mov     [curptr], rax

    cmp     dl, 10
    je      %%newline

    movzx   eax, dl
    and     eax, 0C0h
    cmp     eax, 080h
    je      %%done

    mov     eax, [col_no]
    inc     eax
    mov     [col_no], eax
    jmp     %%done

%%newline:
    mov     dword [col_no], 1
    mov     eax, [line_no]
    inc     eax
    mov     [line_no], eax

%%done:
%endmacro

%macro SKIP_WS 0
%%loop:
    mov     rax, [curptr]
    cmp     rax, [endptr]
    jae     %%done

    mov     dl, [rax]
    cmp     dl, ' '
    je      %%adv
    cmp     dl, 9
    je      %%adv
    cmp     dl, 10
    je      %%adv
    cmp     dl, 13
    je      %%adv
    jmp     %%done

%%adv:
    ADVANCE_ONE
    jmp     %%loop

%%done:
%endmacro

section .data
    mode             db "rb", 0
    usage_msg        db "Usage: main.exe <file>", 10, 0
    open_fail_msg    db "Could not open file", 10, 0
    out_fmt          db "%s", 10, 0
    err_fmt          db "Error at line %u, column %u: %s", 10, 0

    msg_expected_say     db "expected 'skazhi'", 0
    msg_expected_string  db "expected string in quotes", 0
    msg_unclosed_string  db "unclosed string", 0
    msg_expected_dot     db "expected '.'", 0

    ; UTF-8 bytes for "скажи"
    cmd_say db 0xD1,0x81,0xD0,0xBA,0xD0,0xB0,0xD0,0xB6,0xD0,0xB8

section .bss
    buffer      resb 1048576
    fileh       resq 1
    curptr      resq 1
    endptr      resq 1
    quote_ptr   resq 1
    str_start   resq 1
    line_no     resd 1
    col_no      resd 1
    status      resd 1

section .text

main:
    sub rsp, 56

    ; save argc/argv before WinAPI calls
    mov [rsp+32], ecx
    mov [rsp+40], rdx

    ; console UTF-8
    mov ecx, 65001
    call SetConsoleCP
    mov ecx, 65001
    call SetConsoleOutputCP

    mov eax, [rsp+32]
    cmp eax, 2
    jl .usage

    mov rdx, [rsp+40]
    mov rcx, [rdx+8]        ; argv[1]
    lea rdx, [mode]
    call fopen
    test rax, rax
    jz .open_fail
    mov [fileh], rax

    ; fread(buffer, 1, 1048575, file)
    lea rcx, [buffer]
    mov edx, 1
    mov r8d, 1048575
    mov r9, rax
    call fread

    ; NUL terminate
    lea rdx, [buffer]
    mov byte [rdx + rax], 0

    ; init parser state
    lea rdx, [buffer]
    mov [curptr], rdx
    lea rdx, [buffer]
    add rdx, rax
    mov [endptr], rdx
    mov dword [line_no], 1
    mov dword [col_no], 1

    ; skip UTF-8 BOM if present
    mov rax, [curptr]
    cmp rax, [endptr]
    jae .start_parse
    cmp byte [rax], 0EFh
    jne .start_parse
    cmp byte [rax+1], 0BBh
    jne .start_parse
    cmp byte [rax+2], 0BFh
    jne .start_parse
    add rax, 3
    mov [curptr], rax

.start_parse:
    call parse_program
    mov [status], eax

    mov rcx, [fileh]
    call fclose

    mov eax, [status]
    jmp .exit

.usage:
    lea rcx, [usage_msg]
    call printf
    mov eax, 1
    jmp .exit

.open_fail:
    lea rcx, [open_fail_msg]
    call printf
    mov eax, 1

.exit:
    add rsp, 56
    ret


parse_program:
    sub rsp, 40

.loop:
    SKIP_WS

    mov rax, [curptr]
    cmp rax, [endptr]
    jae .ok

    ; Need at least 10 bytes for "скажи"
    mov rdx, [endptr]
    sub rdx, rax
    cmp rdx, 10
    jb .err_say

    cmp byte [rax], 0D1h
    jne .err_say
    cmp byte [rax+1], 081h
    jne .err_say
    cmp byte [rax+2], 0D0h
    jne .err_say
    cmp byte [rax+3], 0BAh
    jne .err_say
    cmp byte [rax+4], 0D0h
    jne .err_say
    cmp byte [rax+5], 0B0h
    jne .err_say
    cmp byte [rax+6], 0D0h
    jne .err_say
    cmp byte [rax+7], 0B6h
    jne .err_say
    cmp byte [rax+8], 0D0h
    jne .err_say
    cmp byte [rax+9], 0B8h
    jne .err_say

    %rep 10
        ADVANCE_ONE
    %endrep

    SKIP_WS

    mov rax, [curptr]
    cmp rax, [endptr]
    jae .err_string
    cmp byte [rax], '"'
    jne .err_string

    ; consume opening quote
    ADVANCE_ONE
    mov rax, [curptr]
    mov [str_start], rax

.scan_string:
    mov rax, [curptr]
    cmp rax, [endptr]
    jae .err_unclosed

    mov dl, [rax]
    cmp dl, 10
    je .err_unclosed
    cmp dl, 13
    je .err_unclosed
    cmp dl, '"'
    je .close_string

    ADVANCE_ONE
    jmp .scan_string

.close_string:
    mov [quote_ptr], rax
    mov byte [rax], 0

    ; consume closing quote
    ADVANCE_ONE

    ; print string
    lea rcx, [out_fmt]
    mov rdx, [str_start]
    sub rsp, 32
    call printf
    add rsp, 32

    ; restore closing quote
    mov rax, [quote_ptr]
    mov byte [rax], '"'

    SKIP_WS

    mov rax, [curptr]
    cmp rax, [endptr]
    jae .err_dot
    cmp byte [rax], '.'
    jne .err_dot

    ; consume dot and continue parsing
    ADVANCE_ONE
    jmp .loop

.err_say:
    lea rcx, [msg_expected_say]
    call report_error
    mov eax, 1
    jmp .done

.err_string:
    lea rcx, [msg_expected_string]
    call report_error
    mov eax, 1
    jmp .done

.err_unclosed:
    lea rcx, [msg_unclosed_string]
    call report_error
    mov eax, 1
    jmp .done

.err_dot:
    lea rcx, [msg_expected_dot]
    call report_error
    mov eax, 1
    jmp .done

.ok:
    xor eax, eax

.done:
    add rsp, 40
    ret


report_error:
    sub rsp, 40
    mov edx, [line_no]
    mov r8d, [col_no]
    mov r9, rcx
    lea rcx, [err_fmt]
    call printf
    add rsp, 40
    ret