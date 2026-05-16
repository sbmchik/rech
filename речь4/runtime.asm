BITS 32

extern _printf
extern line_no, col_no

global _rt_print_number
global _rt_print_string
global _rt_error

section .data
fmt_int db "%d", 10, 0
fmt_str db "%s", 10, 0
fmt_err db "Ошибка (%d:%d): %s", 10, 0

section .text

_rt_print_number:
    push dword [esp+4]
    push fmt_int
    call _printf
    add esp, 8
    ret

_rt_print_string:
    push ebp
    mov ebp, esp

    mov eax, [ebp+8]     ; ptr
    mov ecx, [ebp+12]    ; len

    mov dl, [eax+ecx]
    mov byte [eax+ecx], 0

    push eax
    push fmt_str
    call _printf
    add esp, 8

    mov [eax+ecx], dl

    mov esp, ebp
    pop ebp
    ret

_rt_error:
    push ebp
    mov ebp, esp

    push dword [ebp+8]     ; msg
    push dword [col_no]
    push dword [line_no]
    push fmt_err
    call _printf
    add esp, 16

    mov esp, ebp
    pop ebp
    ret