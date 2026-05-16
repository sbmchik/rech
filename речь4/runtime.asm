BITS 32

extern _printf

global rt_print_number
global rt_print_string

section .data
fmt_int db "%d",10,0
fmt_str db "%s",10,0

section .text

rt_print_number:
    push dword [esp+4]
    push fmt_int
    call _printf
    add esp,8
    ret

rt_print_string:
    push ebp
    mov ebp, esp

    mov eax, [ebp+8]    ; строка
    mov ecx, [ebp+12]   ; длина
    mov byte [eax+ecx], 0

    push eax
    push fmt_str
    call _printf
    add esp, 8

    mov esp, ebp
    pop ebp
    ret