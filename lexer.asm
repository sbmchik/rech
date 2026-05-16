BITS 32

extern cur_ptr, cur_peek, cur_next, cur_skip_ws

global lex_next
global token_type, token_value, token_len

; токены
%define TOK_NUMBER  1
%define TOK_STRING  2
%define TOK_SAY     3
%define TOK_DOT     4
%define TOK_EOF     5

section .bss
token_type  resd 1
token_value resd 1
token_len   resd 1

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

    cmp al, '0'
    jb .word
    cmp al, '9'
    jbe .number

.word:
    ; проверяем "Скажи" (очень тупо, но работает)
    mov eax, [cur_ptr]

    ; проверка первой буквы UTF-8 (С)
    cmp byte [eax], 0D0h
    jne .fail

    mov dword [token_type], TOK_SAY

    ; пропускаем 10 байт слова
    mov ecx, 10
.skip:
    call cur_next
    loop .skip

    ret

.number:
    xor ecx, ecx

.loopn:
    call cur_peek
    cmp al, '0'
    jb .endn
    cmp al, '9'
    ja .endn

    imul ecx, 10
    movzx eax, al
    sub eax, '0'
    add ecx, eax

    call cur_next
    jmp .loopn

.endn:
    mov dword [token_type], TOK_NUMBER
    mov [token_value], ecx
    ret

.string:
    call cur_next
    mov eax, [cur_ptr]
    mov [token_value], eax

.loop:
    call cur_peek
    cmp al, '"'
    je .done
    call cur_next
    jmp .loop

.done:
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
    mov dword [token_type], TOK_EOF
    ret