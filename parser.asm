BITS 32

extern lex_next
extern token_type, token_value, token_len

extern rt_print_number
extern rt_print_string

global parser_run

%define TOK_NUMBER  1
%define TOK_STRING  2
%define TOK_SAY     3
%define TOK_DOT     4
%define TOK_EOF     5

section .text

parse_say:
    call lex_next

    cmp dword [token_type], TOK_NUMBER
    je .num

    cmp dword [token_type], TOK_STRING
    je .str

    ret

.num:
    push dword [token_value]
    call rt_print_number
    add esp,4
    ret

.str:
    push dword [token_len]
    push dword [token_value]
    call rt_print_string
    add esp, 8
    ret

parser_run:
.loop:
    call lex_next

    cmp dword [token_type], TOK_EOF
    je .done

    cmp dword [token_type], TOK_SAY
    jne .done

    call parse_say

    call lex_next
    cmp dword [token_type], TOK_DOT
    jne .done

    jmp .loop

.done:
    ret