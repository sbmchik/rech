BITS 32

global cur_ptr, endptr, line_no, col_no
global cur_init, cur_peek, cur_next, cur_skip_ws

section .bss
cur_ptr  resd 1
endptr   resd 1
line_no  resd 1
col_no   resd 1

section .text

cur_init:
    mov [cur_ptr], eax
    ret

cur_peek:
    mov eax, [cur_ptr]
    cmp eax, [endptr]
    jae .eof
    movzx eax, byte [eax]
    ret
.eof:
    xor eax, eax
    ret

cur_next:
    mov eax, [cur_ptr]
    cmp eax, [endptr]
    jae .done

    mov dl, [eax]
    inc eax
    mov [cur_ptr], eax

    cmp dl, 10
    je .newline

    inc dword [col_no]
    ret

.newline:
    inc dword [line_no]
    mov dword [col_no], 1

.done:
    ret

cur_skip_ws:
.loop:
    call cur_peek
    cmp al, ' '
    je .adv
    cmp al, 9
    je .adv
    cmp al, 10
    je .adv
    cmp al, 13
    je .adv
    ret

.adv:
    call cur_next
    jmp .loop