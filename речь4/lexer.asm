BITS 32

extern cur_ptr, endptr
extern cur_peek, cur_next, cur_skip_ws
extern line_no, col_no

global lex_next
global token_type, token_value, token_len

%define TOK_BAD     0
%define TOK_NUMBER  1
%define TOK_STRING  2
%define TOK_SAY     3
%define TOK_DOT     4
%define TOK_EOF     5

section .bss
token_type  resd 1
token_value resd 1
token_len   resd 1

section .data
kw_say db 0D0h,0A1h,0D0h,0BAh,0D0h,0B0h,0D0h,0B6h,0D0h,0B8h
kw_say_len equ $ - kw_say

section .text

lex_next:
    call cur_skip_ws

    call cur_peek
    cmp al, 0
    je .eof

    cmp al, '.'
    je .dot

    cmp al, '"'
    je .string

    cmp al, '-'
    je .maybe_number

    cmp al, '0'
    jb .try_say
    cmp al, '9'
    jbe .number

.try_say:
    mov eax, [cur_ptr]
    mov edx, [endptr]
    sub edx, eax
    cmp edx, kw_say_len
    jb .fail

    cmp byte [eax],   0D0h
    jne .fail
    cmp byte [eax+1], 0A1h
    jne .fail
    cmp byte [eax+2], 0D0h
    jne .fail
    cmp byte [eax+3], 0BAh
    jne .fail
    cmp byte [eax+4], 0D0h
    jne .fail
    cmp byte [eax+5], 0B0h
    jne .fail
    cmp byte [eax+6], 0D0h
    jne .fail
    cmp byte [eax+7], 0B6h
    jne .fail
    cmp byte [eax+8], 0D0h
    jne .fail
    cmp byte [eax+9], 0B8h
    jne .fail

    mov edx, [cur_ptr]
    add edx, kw_say_len
    cmp edx, [endptr]
    je .say_ok

    mov al, [edx]
    cmp al, ' '
    je .say_ok
    cmp al, 9
    je .say_ok
    cmp al, 10
    je .say_ok
    cmp al, 13
    je .say_ok
    cmp al, '.'
    je .say_ok
    cmp al, '"'
    je .say_ok
    cmp al, 0
    je .say_ok
    jmp .fail

.say_ok:
    mov dword [token_type], TOK_SAY
    mov dword [token_value], 0
    mov dword [token_len], kw_say_len

    add dword [cur_ptr], kw_say_len
    add dword [col_no], kw_say_len
    ret

.maybe_number:
    mov eax, [cur_ptr]
    mov edx, [endptr]
    cmp eax, edx
    jae .fail

    mov bl, [eax]
    cmp bl, '-'
    jne .fail

    mov ecx, 1
    call cur_next

    call cur_peek
    cmp al, '0'
    jb .fail
    cmp al, '9'
    ja .fail
    jmp .number_body

.number:
    xor ecx, ecx

.number_body:
    xor ebx, ebx
    xor esi, esi

.num_loop:
    call cur_peek
    cmp al, '0'
    jb .num_done
    cmp al, '9'
    ja .num_done

    imul ebx, ebx, 10
    movzx eax, al
    sub eax, '0'
    add ebx, eax
    inc esi

    call cur_next
    jmp .num_loop

.num_done:
    cmp esi, 0
    je .fail

    cmp ecx, 0
    je .store_num
    neg ebx

.store_num:
    mov dword [token_type], TOK_NUMBER
    mov [token_value], ebx
    mov [token_len], esi
    ret

.string:
    call cur_next
    mov eax, [cur_ptr]
    mov [token_value], eax

.str_loop:
    call cur_peek
    cmp al, 0
    je .fail
    cmp al, 10
    je .fail
    cmp al, 13
    je .fail
    cmp al, '"'
    je .str_done

    call cur_next
    jmp .str_loop

.str_done:
    mov eax, [cur_ptr]
    sub eax, [token_value]
    mov [token_len], eax
    call cur_next

    mov dword [token_type], TOK_STRING
    ret

.dot:
    call cur_next
    mov dword [token_type], TOK_DOT
    ret

.eof:
    mov dword [token_type], TOK_EOF
    ret

.fail:
    mov dword [token_type], TOK_BAD
    ret