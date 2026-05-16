BITS 32

extern lex_next, token_type, token_value, token_len
extern token_start_line, token_start_col
extern cur_line, cur_col
extern rt_print_number, rt_print_string
extern rt_error_pos

global parser_run

; Внутренние функции парсера
global parse_say
global parse_pust

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
    push dword [token_start_col]
    push dword [token_start_line]
    push dword %2
    push dword %1
    call rt_error_pos
    add esp, 16
    mov dword [parse_failed], 1
%endmacro

%macro FAILHERE 2
    push dword [err_col]
    push dword [err_line]
    push dword %2
    push dword %1
    call rt_error_pos
    add esp, 16
    mov dword [parse_failed], 1
%endmacro

section .data
msg_expected_stmt db "ожидалось начало оператора."
msg_expected_stmt_len equ $ - msg_expected_stmt

msg_expected_value db "ожидалось значение."
msg_expected_value_len equ $ - msg_expected_value

msg_unknown_var db "неизвестная переменная."
msg_unknown_var_len equ $ - msg_unknown_var

msg_expected_ident db "ожидалось имя переменной."
msg_expected_ident_len equ $ - msg_expected_ident

msg_expected_budet db "ожидалось слово 'будет'."
msg_expected_budet_len equ $ - msg_expected_budet

msg_expected_type db "ожидался тип."
msg_expected_type_len equ $ - msg_expected_type

msg_expected_int_source db "ожидалась переменная целого типа."
msg_expected_int_source_len equ $ - msg_expected_int_source

msg_expected_str_source db "ожидалась строковая переменная."
msg_expected_str_source_len equ $ - msg_expected_str_source

msg_expected_dot db "ожидалась точка."
msg_expected_dot_len equ $ - msg_expected_dot

%define MAX_STMTS 256
%define STMT_SAY  1
%define STMT_PUST 2

section .bss
; AST (Abstract Syntax Tree) для двухпроходного парсинга
stmt_type     resb MAX_STMTS    ; тип оператора (SAY/PUST)
stmt_value    resd MAX_STMTS    ; значение для SAY (число/указатель)
stmt_val_len  resd MAX_STMTS    ; длина значения
stmt_var_ptr  resd MAX_STMTS    ; указатель на имя переменной для PUST
stmt_var_len  resd MAX_STMTS    ; длина имени переменной
stmt_var_type resb MAX_STMTS    ; тип переменной (int/str)
stmt_count    resd 1            ; количество операторов в AST

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
err_line     resd 1
err_col      resd 1

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

; === AST функции ===

ast_add_say:
    ; Добавить SAY оператор в AST
    ; EAX = значение (число или указатель)
    ; ECX = длина значения (для строк)
    push ebx
    mov ebx, [stmt_count]
    cmp ebx, MAX_STMTS
    jae .full
    
    mov byte [stmt_type + ebx], STMT_SAY
    mov [stmt_value + ebx*4], eax
    mov [stmt_val_len + ebx*4], ecx
    inc dword [stmt_count]
    pop ebx
    ret
    
.full:
    pop ebx
    ret

ast_add_pust:
    ; Добавить PUST оператор в AST
    ; ESI = указатель на имя переменной
    ; EDI = длина имени
    ; EAX = значение (число или указатель)
    ; ECX = длина значения
    ; DL = тип переменной (1=int, 2=str)
    push ebx
    mov ebx, [stmt_count]
    cmp ebx, MAX_STMTS
    jae .full
    
    mov byte [stmt_type + ebx], STMT_PUST
    mov [stmt_var_ptr + ebx*4], esi
    mov [stmt_var_len + ebx*4], edi
    mov [stmt_value + ebx*4], eax
    mov [stmt_val_len + ebx*4], ecx
    mov byte [stmt_var_type + ebx], dl
    inc dword [stmt_count]
    pop ebx
    ret
    
.full:
    pop ebx
    ret

; === Конец AST функций ===

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

; === ДВУХПРОХОДНОЙ ПАРСЕР (как в C++) ===

parser_build_ast:
    ; Первый проход: парсим и проверяем синтаксис, строим AST
    mov dword [stmt_count], 0
    mov dword [parse_failed], 0
    
.build_loop:
    cmp dword [parse_failed], 0
    jne .build_done
    
    call lex_next
    
    cmp dword [token_type], TOK_EOF
    je .build_done
    
    cmp dword [token_type], TOK_SAY
    je .build_say
    
    cmp dword [token_type], TOK_PUST
    je .build_pust
    
    FAIL msg_expected_stmt, msg_expected_stmt_len
    jmp .build_done

.build_say:
    call lex_next
    cmp dword [token_type], TOK_NUMBER
    je .say_num
    cmp dword [token_type], TOK_STRING
    je .say_str
    cmp dword [token_type], TOK_IDENT
    je .say_ident
    
    FAIL msg_expected_value, msg_expected_value_len
    jmp .build_done

.say_num:
    mov eax, [token_value]
    xor ecx, ecx
    call ast_add_say
    jmp .check_dot_say

.say_str:
    mov eax, [token_value]
    mov ecx, [token_len]
    call ast_add_say
    jmp .check_dot_say

.say_ident:
    mov eax, [token_value]
    mov ecx, [token_len]
    call ast_add_say
    jmp .check_dot_say

.check_dot_say:
    call lex_next
    cmp dword [token_type], TOK_DOT
    je .build_loop
    FAIL msg_expected_dot, msg_expected_dot_len
    jmp .build_done

.build_pust:
    call lex_next
    cmp dword [token_type], TOK_IDENT
    jne .bad_ident
    
    mov esi, [token_value]
    mov edi, [token_len]
    
    call lex_next
    cmp dword [token_type], TOK_BUDET
    jne .bad_budet
    
    call lex_next
    cmp dword [token_type], TOK_TYPE_INT
    je .pust_int_type
    cmp dword [token_type], TOK_TYPE_STR
    je .pust_str_type
    
    FAIL msg_expected_type, msg_expected_type_len
    jmp .build_done

.pust_int_type:
    mov dl, 1
    jmp .pust_value

.pust_str_type:
    mov dl, 2
    jmp .pust_value

.pust_value:
    call lex_next
    cmp dword [token_type], TOK_NUMBER
    je .pust_num
    cmp dword [token_type], TOK_STRING
    je .pust_str
    cmp dword [token_type], TOK_IDENT
    je .pust_ident
    
    FAIL msg_expected_value, msg_expected_value_len
    jmp .build_done

.pust_num:
    mov eax, [token_value]
    xor ecx, ecx
    call ast_add_pust
    jmp .check_dot_pust

.pust_str:
    mov eax, [token_value]
    mov ecx, [token_len]
    call ast_add_pust
    jmp .check_dot_pust

.pust_ident:
    mov eax, [token_value]
    mov ecx, [token_len]
    call ast_add_pust
    jmp .check_dot_pust

.check_dot_pust:
    call lex_next
    cmp dword [token_type], TOK_DOT
    je .build_loop
    FAIL msg_expected_dot, msg_expected_dot_len
    jmp .build_done

.bad_ident:
    FAIL msg_expected_ident, msg_expected_ident_len
    jmp .build_done

.bad_budet:
    FAIL msg_expected_budet, msg_expected_budet_len
    jmp .build_done

.build_done:
    ret

; === Второй проход: исполнение AST ===

parser_exec_ast:
    mov dword [parse_failed], 0
    xor ecx, ecx

.exec_loop:
    cmp ecx, [stmt_count]
    jge .exec_done
    
    mov al, [stmt_type + ecx]
    cmp al, STMT_SAY
    je .exec_say
    cmp al, STMT_PUST
    je .exec_pust
    
    inc ecx
    jmp .exec_loop

.exec_say:
    mov eax, [stmt_value + ecx*4]
    mov edx, [stmt_val_len + ecx*4]
    
    cmp edx, 0
    je .exec_say_num
    
    ; строка
    push edx
    push eax
    call rt_print_string
    add esp, 8
    jmp .next_stmt

.exec_say_num:
    push eax
    call rt_print_number
    add esp, 4
    jmp .next_stmt

.exec_pust:
    ; Пока просто пропускаем - переменные создаются в старом parse_pust
    ; TODO: реализовать создание переменных во втором проходе
    inc ecx
    jmp .exec_loop

.next_stmt:
    inc ecx
    jmp .exec_loop

.exec_done:
    ret

; === КОНЕЦ ДВУХПРОХОДНОГО ПАРСЕРА ===

parser_run:
    ; ДВУХПРОХОДНОЙ ПАРСЕР как в C++:
    ; 1. Проверяем весь синтаксис, строим AST
    ; 2. Если нет ошибок - исполняем AST
    
    call parser_build_ast
    cmp dword [parse_failed], 0
    jne .done
    
    call parser_exec_ast
    
.done:
    mov eax, [parse_failed]
    ret
