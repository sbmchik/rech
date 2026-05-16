BITS 32

global cur_ptr, cur_init, cur_peek, cur_next, cur_skip_ws

section .bss
cur_ptr resd 1

section .text

cur_init:
    mov [cur_ptr], eax
    ret

cur_peek:
    mov eax, [cur_ptr]
    movzx eax, byte [eax]
    ret

cur_next:
    mov eax, [cur_ptr]
    inc eax
    mov [cur_ptr], eax
    ret

cur_skip_ws:
.loop:
    call cur_peek
    cmp al, ' '
    je .adv
    cmp al, 10
    je .adv
    cmp al, 13
    je .adv
    ret

.adv:
    call cur_next
    jmp .loop