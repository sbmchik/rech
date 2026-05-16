BITS 32

extern lex_next
extern token_type, token_value, token_len

extern _rt_print_number
extern _rt_print_string
extern _rt_error

global parser_run

%define TOK_BAD     0
%define TOK_NUMBER  1
%define TOK_STRING  2
%define TOK_SAY     3
%define TOK_DOT     4
%define TOK_EOF     5

section .data
msg_expected_say    db "ожидалось 'Скажи'", 0
msg_expected_value  db "ожидалось число или строка", 0
msg_expected_dot    db "ожидалась точка", 0
msg_lexer_error     db "ошибка лексера", 0

section .text

parse_say:
    call lex_next

    mov eax, [token_type]
    cmp eax, TOK_NUMBER
    je .num
    cmp eax, TOK_STRING
    je .str
    cmp eax, TOK_BAD
    je .err
    cmp eax, TOK_EOF
    je .err

    push msg_expected_value
    call _rt_error
    add esp, 4
    xor eax, eax
    ret

.num:
    push dword [token_value]
    call _rt_print_number
    add esp, 4
    mov eax, 1
    ret

.str:
    push dword [token_len]
    push dword [token_value]
    call _rt_print_string
    add esp, 8
    mov eax, 1
    ret

.err:
    push msg_expected_value
    call _rt_error
    add esp, 4
    xor eax, eax
    ret

parser_run:
.loop:
    call lex_next

    mov eax, [token_type]
    cmp eax, TOK_EOF
    je .done
    cmp eax, TOK_BAD
    je .lexerr
    cmp eax, TOK_SAY
    jne .err_say

    call parse_say
    test eax, eax
    jz .fail

    call lex_next
    mov eax, [token_type]
    cmp eax, TOK_DOT
    je .loop
    cmp eax, TOK_BAD
    je .lexerr

    jmp .err_dot

.err_say:
    push msg_expected_say
    call _rt_error
    add esp, 4
    mov eax, 1
    ret

.err_dot:
    push msg_expected_dot
    call _rt_error
    add esp, 4
    mov eax, 1
    ret

.lexerr:
    push msg_lexer_error
    call _rt_error
    add esp, 4
    mov eax, 1
    ret

.fail:
    mov eax, 1
    ret

.done:
    xor eax, eax
    ret