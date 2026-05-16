BITS 32

global cur_ptr, cur_line, cur_col, cur_init, cur_peek, cur_next, cur_skip_ws

section .bss
cur_ptr  resd 1
cur_line resd 1
cur_col  resd 1

section .text

cur_init:
    mov [cur_ptr], eax
    mov dword [cur_line], 1
    mov dword [cur_col], 1
    ret

cur_peek:
    mov eax, [cur_ptr]
    movzx eax, byte [eax]
    ret

cur_next:
    push ebx
    push edx
    mov eax, [cur_ptr]
    movzx eax, byte [eax]
    cmp al, 10
    je .is_nl
    cmp al, 13
    je .is_cr
    mov dl, al
    and dl, 0C0h
    cmp dl, 080h
    je .inc_ptr
    inc dword [cur_col]
    jmp .inc_ptr
.is_nl:
    inc dword [cur_line]
    mov dword [cur_col], 1
    jmp .inc_ptr
.is_cr:
    ; CRLF: не двигаем колонку на \r, если следом \n
    mov ebx, [cur_ptr]
    cmp byte [ebx+1], 10
    je .inc_ptr
    inc dword [cur_col]
    jmp .inc_ptr
.inc_ptr:
    mov eax, [cur_ptr]
    inc eax
    mov [cur_ptr], eax
    pop edx
    pop ebx
    ret

cur_skip_ws:
.loop:
    call cur_peek
    cmp al, 0
    je .done
    cmp al, ' '
    je .adv
    cmp al, 9
    je .adv
    cmp al, 10
    je .adv
    cmp al, 13
    je .adv
    cmp al, 0C2h
    jne .done
    mov eax, [cur_ptr]
    cmp byte [eax+1], 0A0h
    jne .done
    call cur_next
    call cur_next
    jmp .loop

.done:
    ret

.adv:
    call cur_next
    jmp .loop
