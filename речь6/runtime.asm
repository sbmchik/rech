BITS 32

extern _GetStdHandle@4
extern _GetConsoleMode@8
extern _WriteConsoleW@20
extern _WriteFile@20
extern _MultiByteToWideChar@24

global rt_init
global rt_print_number
global rt_print_string
global rt_error_string

%define STD_OUTPUT_HANDLE -11
%define STD_ERROR_HANDLE  -12
%define CP_UTF8 65001

section .data
nl  db 10
nlw dw 10

section .bss
hStdout     resd 1
hStderr     resd 1
out_console resd 1
err_console resd 1
tmp_mode    resd 1
written     resd 1
num_buf     resb 32
wide_buf    resw 1024

section .text

rt_init:
    push dword STD_OUTPUT_HANDLE
    call _GetStdHandle@4
    mov [hStdout], eax

    push tmp_mode
    push eax
    call _GetConsoleMode@8
    test eax, eax
    setnz al
    movzx eax, al
    mov [out_console], eax

    push dword STD_ERROR_HANDLE
    call _GetStdHandle@4
    mov [hStderr], eax

    push tmp_mode
    push eax
    call _GetConsoleMode@8
    test eax, eax
    setnz al
    movzx eax, al
    mov [err_console], eax

    ret

; cdecl:
; write_utf8(handle, is_console, ptr, len, add_newline)
write_utf8:
    push ebp
    mov ebp, esp
    push ebx
    push esi
    push edi

    mov eax, [ebp+8]     ; handle
    mov ebx, [ebp+12]    ; is_console
    mov esi, [ebp+16]    ; ptr
    mov ecx, [ebp+20]    ; len
    mov edx, [ebp+24]    ; add_newline

    cmp ecx, 1024
    jbe .len_ok
    mov ecx, 1024
.len_ok:

    test ebx, ebx
    jz .raw

    push dword 1024
    push wide_buf
    push ecx
    push esi
    push dword 0
    push dword CP_UTF8
    call _MultiByteToWideChar@24
    test eax, eax
    jz .raw

    push dword 0
    lea edi, [written]
    push edi
    push eax
    push wide_buf
    push dword [ebp+8]
    call _WriteConsoleW@20
    jmp .newline

.raw:
    push dword 0
    lea edi, [written]
    push edi
    push ecx
    push esi
    push dword [ebp+8]
    call _WriteFile@20

.newline:
    test edx, edx
    jz .done

    mov eax, [ebp+12]
    test eax, eax
    jz .nl_bytes

    push dword 0
    lea edi, [written]
    push edi
    push dword 1
    push nlw
    push dword [ebp+8]
    call _WriteConsoleW@20
    jmp .done

.nl_bytes:
    push dword 0
    lea edi, [written]
    push edi
    push dword 1
    push nl
    push dword [ebp+8]
    call _WriteFile@20

.done:
    pop edi
    pop esi
    pop ebx
    mov esp, ebp
    pop ebp
    ret

rt_print_number:
    push ebp
    mov ebp, esp

    mov eax, [ebp+8]
    mov esi, eax
    sar esi, 31
    xor eax, esi
    sub eax, esi

    lea edi, [num_buf+31]
    mov byte [edi], 0
    mov ebx, 10

    cmp eax, 0
    jne .digits

    dec edi
    mov byte [edi], '0'
    jmp .maybe_sign

.digits:
.loop:
    xor edx, edx
    div ebx
    add dl, '0'
    dec edi
    mov [edi], dl
    test eax, eax
    jnz .loop

.maybe_sign:
    test esi, esi
    jz .out_ready
    dec edi
    mov byte [edi], '-'

.out_ready:
    lea ecx, [num_buf+31]
    sub ecx, edi

    push dword 1
    push ecx
    push edi
    push dword [out_console]
    push dword [hStdout]
    call write_utf8

    mov esp, ebp
    pop ebp
    ret

rt_print_string:
    push ebp
    mov ebp, esp

    push dword 1
    push dword [ebp+12]
    push dword [ebp+8]
    push dword [out_console]
    push dword [hStdout]
    call write_utf8

    mov esp, ebp
    pop ebp
    ret

rt_error_string:
    push ebp
    mov ebp, esp

    push dword 1
    push dword [ebp+12]
    push dword [ebp+8]
    push dword [err_console]
    push dword [hStderr]
    call write_utf8

    mov esp, ebp
    pop ebp
    ret