BITS 32

extern lex_next, token_type, token_value, token_len
extern rt_print_number, rt_print_string
extern rt_error_string

global parser_run

%define TOK_NUMBER    1
%define TOK_STRING    2
%define TOK_SAY       3
%define TOK_PUST      4
%define TOK_BUDET     5
%define TOK_TYPE_INT  6
%define TOK_TYPE_STR  7
%define TOK_IDENT     8
%define TOK_DOT       9
%define TOK_EOF       10

%define MAXVARS 64
%define STR_SLOT_SIZE 512

%macro FAIL 2
    push dword %2
    push dword %1
    call rt_error_string
    add esp, 8
    mov dword [parse_failed], 1
%endmacro

section .data
msg_expected_stmt db "Ошибка: ожидалось начало конструкции: Скажи или Пусть."
msg_expected_stmt_len equ $ - msg_expected_stmt

msg_expected_value db "Ошибка: ожидалось число, строка или имя переменной."
msg_expected_value_len equ $ - msg_expected_value

msg_unknown_var db "Ошибка: неизвестная переменная."
msg_unknown_var_len equ $ - msg_unknown_var

msg_expected_ident db "Ошибка: ожидалось имя переменной."
msg_expected_ident_len equ $ - msg_expected_ident

msg_expected_budet db "Ошибка: ожидалось слово Будет."
msg_expected_budet_len equ $ - msg_expected_budet

msg_expected_type db "Ошибка: ожидался тип: целым числом или строкой."
msg_expected_type_len equ $ - msg_expected_type

msg_expected_int_source db "Ошибка: ожидалась переменная целого типа."
msg_expected_int_source_len equ $ - msg_expected_int_source

msg_expected_str_source db "Ошибка: ожидалась строковая переменная."
msg_expected_str_source_len equ $ - msg_expected_str_source

msg_expected_dot db "Ошибка: ожидалась точка в конце конструкции."
msg_expected_dot_len equ $ - msg_expected_dot

section .bss
var_count    resd 1
var_type     resb MAXVARS
var_name_ptr resd MAXVARS
var_name_len resd MAXVARS
var_int      resd MAXVARS
var_str      resb MAXVARS * STR_SLOT_SIZE
var_str_len  resd MAXVARS

tmp_name_ptr resd 1
tmp_name_len resd 1
tmp_src_idx  resd 1
parse_failed resd 1

section .text

find_var:
    ; ESI = name ptr
    ; EDI = name len
    push ebx
    xor ebx, ebx

.loop:
    cmp ebx, [var_count]
    jae .not_found

    cmp byte [var_type + ebx], 0
    je .next

    mov eax, [var_name_len + ebx*4]
    cmp eax, edi
    jne .next

    mov edx, [var_name_ptr + ebx*4]
    xor ecx, ecx

.cmp:
    cmp ecx, edi
    je .found

    mov al, [edx + ecx]
    cmp al, [esi + ecx]
    jne .next

    inc ecx
    jmp .cmp

.next:
    inc ebx
    jmp .loop

.found:
    mov eax, ebx
    pop ebx
    ret

.not_found:
    mov eax, -1
    pop ebx
    ret

ensure_var_slot:
    ; ESI = name ptr
    ; EDI = name len
    call find_var
    cmp eax, -1
    jne .done

    mov eax, [var_count]
    cmp eax, MAXVARS
    jae .too_many

    inc dword [var_count]
.done:
    ret

.too_many:
    mov eax, -1
    ret

parse_say:
    call lex_next

    cmp dword [token_type], TOK_NUMBER
    je .num
    cmp dword [token_type], TOK_STRING
    je .str
    cmp dword [token_type], TOK_IDENT
    je .ident

    FAIL msg_expected_value, msg_expected_value_len
    ret

.num:
    push dword [token_value]
    call rt_print_number
    add esp, 4
    ret

.str:
    push dword [token_len]
    push dword [token_value]
    call rt_print_string
    add esp, 8
    ret

.ident:
    mov esi, [token_value]
    mov edi, [token_len]
    call find_var
    cmp eax, -1
    je .unknown

    cmp byte [var_type + eax], 1
    je .print_int
    cmp byte [var_type + eax], 2
    je .print_str

    FAIL msg_unknown_var, msg_unknown_var_len
    ret

.unknown:
    FAIL msg_unknown_var, msg_unknown_var_len
    ret

.print_int:
    push dword [var_int + eax*4]
    call rt_print_number
    add esp, 4
    ret

.print_str:
    mov edx, eax
    mov eax, edx
    imul eax, STR_SLOT_SIZE
    lea eax, [var_str + eax]
    push dword [var_str_len + edx*4]
    push eax
    call rt_print_string
    add esp, 8
    ret

parse_pust:
    ; current token is TOK_PUST, read name
    call lex_next
    cmp dword [token_type], TOK_IDENT
    jne .bad_ident

    mov eax, [token_value]
    mov [tmp_name_ptr], eax
    mov eax, [token_len]
    mov [tmp_name_len], eax

    call lex_next
    cmp dword [token_type], TOK_BUDET
    jne .bad_budet

    call lex_next

    cmp dword [token_type], TOK_TYPE_INT
    je .int_decl
    cmp dword [token_type], TOK_TYPE_STR
    je .str_decl

    FAIL msg_expected_type, msg_expected_type_len
    ret

.bad_ident:
    FAIL msg_expected_ident, msg_expected_ident_len
    ret

.bad_budet:
    FAIL msg_expected_budet, msg_expected_budet_len
    ret

.int_decl:
    call lex_next
    cmp dword [token_type], TOK_NUMBER
    je .store_int
    cmp dword [token_type], TOK_IDENT
    je .copy_int

    FAIL msg_expected_value, msg_expected_value_len
    ret

.store_int:
    mov esi, [tmp_name_ptr]
    mov edi, [tmp_name_len]
    call ensure_var_slot
    cmp eax, -1
    je .bad

    mov ebx, eax
    mov byte [var_type + ebx], 1
    mov eax, [tmp_name_ptr]
    mov [var_name_ptr + ebx*4], eax
    mov eax, [tmp_name_len]
    mov [var_name_len + ebx*4], eax
    mov eax, [token_value]
    mov [var_int + ebx*4], eax
    ret

.copy_int:
    mov esi, [token_value]
    mov edi, [token_len]
    call find_var
    cmp eax, -1
    je .unknown_src_int
    cmp byte [var_type + eax], 1
    jne .wrong_src_int

    mov edx, [var_int + eax*4]
    mov esi, [tmp_name_ptr]
    mov edi, [tmp_name_len]
    call ensure_var_slot
    cmp eax, -1
    je .bad

    mov ebx, eax
    mov byte [var_type + ebx], 1
    mov eax, [tmp_name_ptr]
    mov [var_name_ptr + ebx*4], eax
    mov eax, [tmp_name_len]
    mov [var_name_len + ebx*4], eax
    mov [var_int + ebx*4], edx
    ret

.unknown_src_int:
    FAIL msg_unknown_var, msg_unknown_var_len
    ret

.wrong_src_int:
    FAIL msg_expected_int_source, msg_expected_int_source_len
    ret

.str_decl:
    call lex_next
    cmp dword [token_type], TOK_STRING
    je .store_str
    cmp dword [token_type], TOK_IDENT
    je .copy_str

    FAIL msg_expected_value, msg_expected_value_len
    ret

.store_str:
    mov eax, [token_len]
    cmp eax, STR_SLOT_SIZE - 1
    ja .bad

    mov esi, [tmp_name_ptr]
    mov edi, [tmp_name_len]
    call ensure_var_slot
    cmp eax, -1
    je .bad

    mov ebx, eax
    mov byte [var_type + ebx], 2
    mov eax, [tmp_name_ptr]
    mov [var_name_ptr + ebx*4], eax
    mov eax, [tmp_name_len]
    mov [var_name_len + ebx*4], eax

    mov esi, [token_value]
    mov eax, ebx
    imul eax, STR_SLOT_SIZE
    lea edi, [var_str + eax]
    mov ecx, [token_len]
    rep movsb
    mov byte [edi], 0

    mov eax, [token_len]
    mov [var_str_len + ebx*4], eax
    ret

.copy_str:
    mov esi, [token_value]
    mov edi, [token_len]
    call find_var
    cmp eax, -1
    je .unknown_src_str
    cmp byte [var_type + eax], 2
    jne .wrong_src_str

    mov [tmp_src_idx], eax

    mov edx, [var_str_len + eax*4]
    cmp edx, STR_SLOT_SIZE - 1
    ja .bad

    mov esi, [tmp_name_ptr]
    mov edi, [tmp_name_len]
    call ensure_var_slot
    cmp eax, -1
    je .bad

    mov ebx, eax
    mov byte [var_type + ebx], 2
    mov eax, [tmp_name_ptr]
    mov [var_name_ptr + ebx*4], eax
    mov eax, [tmp_name_len]
    mov [var_name_len + ebx*4], eax

    mov eax, [tmp_src_idx]
    mov ecx, [var_str_len + eax*4]
    imul eax, STR_SLOT_SIZE
    lea esi, [var_str + eax]

    mov eax, ebx
    imul eax, STR_SLOT_SIZE
    lea edi, [var_str + eax]

    rep movsb
    mov byte [edi], 0

    mov eax, [tmp_src_idx]
    mov eax, [var_str_len + eax*4]
    mov [var_str_len + ebx*4], eax
    ret

.unknown_src_str:
    FAIL msg_unknown_var, msg_unknown_var_len
    ret

.wrong_src_str:
    FAIL msg_expected_str_source, msg_expected_str_source_len
    ret

.bad:
    ret

parser_run:
    mov dword [parse_failed], 0

.loop:
    cmp dword [parse_failed], 0
    jne .done

    call lex_next

    cmp dword [token_type], TOK_EOF
    je .done

    cmp dword [token_type], TOK_SAY
    je .do_say

    cmp dword [token_type], TOK_PUST
    je .do_pust

    FAIL msg_expected_stmt, msg_expected_stmt_len
    jmp .done

.do_say:
    call parse_say
    cmp dword [parse_failed], 0
    jne .done

    call lex_next
    cmp dword [token_type], TOK_DOT
    je .loop

    FAIL msg_expected_dot, msg_expected_dot_len
    jmp .done

.do_pust:
    call parse_pust
    cmp dword [parse_failed], 0
    jne .done

    call lex_next
    cmp dword [token_type], TOK_DOT
    je .loop

    FAIL msg_expected_dot, msg_expected_dot_len

.done:
    mov eax, [parse_failed]
    ret