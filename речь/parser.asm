BITS 32

extern lex_next, token_type, token_value, token_len
extern token_start_line, token_start_col
extern cur_line, cur_col
extern rt_print_number, rt_print_string
extern rt_error_pos
extern cur_ptr, cur_peek, cur_next, cur_skip_ws

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
%define MAX_INSTRUCTIONS 4096
%define VAR_NAME_MAX 128

; Opcodes for instructions (IR - Intermediate Representation)
%define OP_SAY_NUM       1
%define OP_SAY_STR       2
%define OP_SAY_VAR       3
%define OP_PUST_INT_NUM  4
%define OP_PUST_INT_VAR  5
%define OP_PUST_STR_STR  6
%define OP_PUST_STR_VAR  7

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

msg_name_too_long db "имя переменной слишком длинное."
msg_name_too_long_len equ $ - msg_name_too_long

section .bss
var_count    resd 1
var_type     resb MAXVARS
var_name_ptr resd MAXVARS
var_name_len resd MAXVARS
var_int      resd MAXVARS
var_str      resb MAXVARS * STR_SLOT_SIZE
var_str_len  resd MAXVARS
var_name_buf  resb MAXVARS * VAR_NAME_MAX

tmp_name_ptr resd 1
tmp_name_len resd 1
tmp_src_idx  resd 1
parse_failed resd 1
err_line     resd 1
err_col      resd 1

; Instruction storage (IR array)
instr_opcode   resd MAX_INSTRUCTIONS
instr_arg1     resd MAX_INSTRUCTIONS
instr_arg2     resd MAX_INSTRUCTIONS
instr_arg3     resd MAX_INSTRUCTIONS
instr_count    resd 1

section .text

; ESI = pattern ptr
; EDI = pattern len
; EDX = token type
try_kw:
    push ebx
    push edi

    mov ebx, [cur_ptr]
    xor edi, edi

.cmp_loop:
    cmp edi, ecx
    je .boundary

    mov al, [ebx + edi]
    cmp al, [esi + edi]
    jne .fail

    inc edi
    jmp .cmp_loop

.boundary:
    mov eax, [cur_ptr]
    add eax, ecx
    mov al, [eax]

    cmp al, 0
    je .advance
    cmp al, ' '
    je .advance
    cmp al, 9
    je .advance
    cmp al, 10
    je .advance
    cmp al, 13
    je .advance
    cmp al, '.'
    je .advance
    cmp al, '"'
    je .advance
    cmp al, 0C2h
    jne .fail
    mov ebx, [cur_ptr]
    add ebx, ecx
    cmp byte [ebx+1], 0A0h
    je .advance
    jmp .fail

.advance:
    mov edi, ecx
.step:
    test edi, edi
    jz .ok
    call cur_next
    dec edi
    jmp .step

.ok:
    mov [token_type], edx
    mov eax, 1
    jmp .done

.fail:
    xor eax, eax

.done:
    pop edi
    pop ebx
    ret

; ------------------------------------------------------------
; parse_say
; ------------------------------------------------------------
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
    mov eax, [instr_count]
    mov dword [instr_opcode + eax*4], OP_SAY_NUM
    mov ecx, [token_value]
    mov [instr_arg1 + eax*4], ecx
    inc dword [instr_count]
    ret

.str:
    mov eax, [instr_count]
    mov dword [instr_opcode + eax*4], OP_SAY_STR
    mov ecx, [token_value]
    mov [instr_arg1 + eax*4], ecx
    mov ecx, [token_len]
    mov [instr_arg2 + eax*4], ecx
    inc dword [instr_count]
    ret

.ident:
    mov esi, [token_value]
    mov edi, [token_len]
    call find_var
    cmp eax, -1
    je .unknown

    mov edx, eax
    mov eax, [instr_count]
    mov dword [instr_opcode + eax*4], OP_SAY_VAR
    mov [instr_arg1 + eax*4], edx
    inc dword [instr_count]
    ret

.unknown:
    FAIL msg_unknown_var, msg_unknown_var_len
    ret

; ------------------------------------------------------------
; helper: find variable by name
; ESI = name ptr
; EDI = name len
; returns EAX = slot or -1
; ------------------------------------------------------------
find_var:
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

; ------------------------------------------------------------
; allocate new variable slot
; returns EAX = slot or -1
; ------------------------------------------------------------
alloc_var_slot:
    mov eax, [var_count]
    cmp eax, MAXVARS
    jae .full
    inc dword [var_count]
    ret
.full:
    mov eax, -1
    ret

; ------------------------------------------------------------
; parse_pust
; ------------------------------------------------------------
parse_pust:
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

; ------------------------------------------------------------
; int declaration
; ------------------------------------------------------------
.int_decl:
    call lex_next
    cmp dword [token_type], TOK_NUMBER
    je .int_num_init
    cmp dword [token_type], TOK_IDENT
    je .int_var_init

    FAIL msg_expected_value, msg_expected_value_len
    ret

.int_num_init:
    mov esi, [tmp_name_ptr]
    mov edi, [tmp_name_len]
    call find_var
    cmp eax, -1
    jne .redeclared

    call alloc_var_slot
    cmp eax, -1
    je .bad
    mov ebx, eax

    mov ecx, [tmp_name_len]
    cmp ecx, VAR_NAME_MAX - 1
    ja .name_too_long

    mov byte [var_type + ebx], 1

    mov edx, ebx
    imul edx, edx, VAR_NAME_MAX
    lea edi, [var_name_buf + edx]

    mov esi, [tmp_name_ptr]
    push ecx
    rep movsb
    mov byte [edi], 0
    pop ecx

    lea eax, [var_name_buf + edx]
    mov [var_name_ptr + ebx*4], eax
    mov [var_name_len + ebx*4], ecx

    mov eax, [instr_count]
    mov dword [instr_opcode + eax*4], OP_PUST_INT_NUM
    mov [instr_arg1 + eax*4], ebx
    mov ecx, [token_value]
    mov [instr_arg2 + eax*4], ecx
    inc dword [instr_count]
    ret

.int_var_init:
    mov esi, [token_value]
    mov edi, [token_len]
    call find_var
    cmp eax, -1
    je .unknown_src_int
    cmp byte [var_type + eax], 1
    jne .wrong_src_int
    mov [tmp_src_idx], eax

    mov esi, [tmp_name_ptr]
    mov edi, [tmp_name_len]
    call find_var
    cmp eax, -1
    jne .redeclared

    call alloc_var_slot
    cmp eax, -1
    je .bad
    mov ebx, eax

    mov ecx, [tmp_name_len]
    cmp ecx, VAR_NAME_MAX - 1
    ja .name_too_long

    mov byte [var_type + ebx], 1

    mov edx, ebx
    imul edx, edx, VAR_NAME_MAX
    lea edi, [var_name_buf + edx]

    mov esi, [tmp_name_ptr]
    push ecx
    rep movsb
    mov byte [edi], 0
    pop ecx

    lea eax, [var_name_buf + edx]
    mov [var_name_ptr + ebx*4], eax
    mov [var_name_len + ebx*4], ecx

    mov eax, [instr_count]
    mov dword [instr_opcode + eax*4], OP_PUST_INT_VAR
    mov [instr_arg1 + eax*4], ebx
    mov ecx, [tmp_src_idx]
    mov [instr_arg2 + eax*4], ecx
    inc dword [instr_count]
    ret

.unknown_src_int:
    FAIL msg_unknown_var, msg_unknown_var_len
    ret

.wrong_src_int:
    FAIL msg_expected_int_source, msg_expected_int_source_len
    ret

; ------------------------------------------------------------
; string declaration
; ------------------------------------------------------------
.str_decl:
    call lex_next
    cmp dword [token_type], TOK_STRING
    je .str_str_init
    cmp dword [token_type], TOK_IDENT
    je .str_var_init

    FAIL msg_expected_value, msg_expected_value_len
    ret

.str_str_init:
    mov esi, [tmp_name_ptr]
    mov edi, [tmp_name_len]
    call find_var
    cmp eax, -1
    jne .redeclared_str

    call alloc_var_slot
    cmp eax, -1
    je .bad
    mov ebx, eax

    mov ecx, [tmp_name_len]
    cmp ecx, VAR_NAME_MAX - 1
    ja .name_too_long

    mov byte [var_type + ebx], 2

    mov edx, ebx
    imul edx, edx, VAR_NAME_MAX
    lea edi, [var_name_buf + edx]

    mov esi, [tmp_name_ptr]
    push ecx
    rep movsb
    mov byte [edi], 0
    pop ecx

    lea eax, [var_name_buf + edx]
    mov [var_name_ptr + ebx*4], eax
    mov [var_name_len + ebx*4], ecx

    mov eax, [instr_count]
    mov dword [instr_opcode + eax*4], OP_PUST_STR_STR
    mov [instr_arg1 + eax*4], ebx
    mov ecx, [token_value]
    mov [instr_arg2 + eax*4], ecx
    mov ecx, [token_len]
    mov [instr_arg3 + eax*4], ecx
    inc dword [instr_count]
    ret

.str_var_init:
    mov esi, [token_value]
    mov edi, [token_len]
    call find_var
    cmp eax, -1
    je .unknown_src_str
    cmp byte [var_type + eax], 2
    jne .wrong_src_str
    mov [tmp_src_idx], eax

    mov esi, [tmp_name_ptr]
    mov edi, [tmp_name_len]
    call find_var
    cmp eax, -1
    jne .redeclared_str

    call alloc_var_slot
    cmp eax, -1
    je .bad
    mov ebx, eax

    mov ecx, [tmp_name_len]
    cmp ecx, VAR_NAME_MAX - 1
    ja .name_too_long

    mov byte [var_type + ebx], 2

    mov edx, ebx
    imul edx, edx, VAR_NAME_MAX
    lea edi, [var_name_buf + edx]

    mov esi, [tmp_name_ptr]
    push ecx
    rep movsb
    mov byte [edi], 0
    pop ecx

    lea eax, [var_name_buf + edx]
    mov [var_name_ptr + ebx*4], eax
    mov [var_name_len + ebx*4], ecx

    mov eax, [instr_count]
    mov dword [instr_opcode + eax*4], OP_PUST_STR_VAR
    mov [instr_arg1 + eax*4], ebx
    mov ecx, [tmp_src_idx]
    mov [instr_arg2 + eax*4], ecx
    inc dword [instr_count]
    ret

.unknown_src_str:
    FAIL msg_unknown_var, msg_unknown_var_len
    ret

.wrong_src_str:
    FAIL msg_expected_str_source, msg_expected_str_source_len
    ret

.redeclared:
    cmp byte [var_type + eax], 1
    jne .type_mismatch_int
    jmp .bad

.type_mismatch_int:
    FAIL msg_expected_int_source, msg_expected_int_source_len
    ret

.redeclared_str:
    cmp byte [var_type + eax], 2
    jne .type_mismatch_str
    jmp .bad

.type_mismatch_str:
    FAIL msg_expected_str_source, msg_expected_str_source_len
    ret

.name_too_long:
    FAIL msg_name_too_long, msg_name_too_long_len
    ret

.bad:
    ret

; ----------------------------------------------------------------------
; Second pass: execute instructions
; ----------------------------------------------------------------------
execute_all:
    xor esi, esi

.loop:
    mov eax, [instr_count]
    cmp esi, eax
    je .done

    mov eax, [instr_opcode + esi*4]
    cmp eax, OP_SAY_NUM
    je .say_num
    cmp eax, OP_SAY_STR
    je .say_str
    cmp eax, OP_SAY_VAR
    je .say_var
    cmp eax, OP_PUST_INT_NUM
    je .pust_int_num
    cmp eax, OP_PUST_INT_VAR
    je .pust_int_var
    cmp eax, OP_PUST_STR_STR
    je .pust_str_str
    cmp eax, OP_PUST_STR_VAR
    je .pust_str_var
    jmp .next

.say_num:
    mov eax, [instr_arg1 + esi*4]
    push esi
    push eax
    call rt_print_number
    add esp, 4
    pop esi
    jmp .next

.say_str:
    mov eax, [instr_arg1 + esi*4]
    mov edx, [instr_arg2 + esi*4]
    push esi
    push edx
    push eax
    call rt_print_string
    add esp, 8
    pop esi
    jmp .next

.say_var:
    mov eax, [instr_arg1 + esi*4]
    cmp byte [var_type + eax], 1
    je .say_var_int
    cmp byte [var_type + eax], 2
    je .say_var_str
    jmp .next

.say_var_int:
    mov eax, [var_int + eax*4]
    push esi
    push eax
    call rt_print_number
    add esp, 4
    pop esi
    jmp .next

.say_var_str:
    mov edx, eax
    mov eax, [var_name_len + edx*4]
    ; EAX = length is not needed here, keep only for safety? no.
    mov eax, edx
    imul eax, eax, STR_SLOT_SIZE
    lea eax, [var_str + eax]
    mov ecx, [var_str_len + edx*4]
    push esi
    push ecx
    push eax
    call rt_print_string
    add esp, 8
    pop esi
    jmp .next

.pust_int_num:
    mov eax, [instr_arg1 + esi*4]
    mov ecx, [instr_arg2 + esi*4]
    mov [var_int + eax*4], ecx
    jmp .next

.pust_int_var:
    mov eax, [instr_arg1 + esi*4]
    mov ecx, [instr_arg2 + esi*4]
    mov edx, [var_int + ecx*4]
    mov [var_int + eax*4], edx
    jmp .next

.pust_str_str:
    mov eax, [instr_arg1 + esi*4]     ; dest slot
    mov ecx, [instr_arg2 + esi*4]     ; source ptr
    mov edx, [instr_arg3 + esi*4]     ; length

    mov ebx, eax
    imul ebx, ebx, STR_SLOT_SIZE
    lea edi, [var_str + ebx]

    push esi
    mov esi, ecx
    mov ecx, edx
    rep movsb
    mov byte [edi], 0
    pop esi

    mov [var_str_len + eax*4], edx
    jmp .next

.pust_str_var:
    mov eax, [instr_arg1 + esi*4]     ; dest slot
    mov ecx, [instr_arg2 + esi*4]     ; src slot
    mov edx, [var_str_len + ecx*4]    ; length

    mov ebx, ecx
    imul ebx, ebx, STR_SLOT_SIZE
    lea esi, [var_str + ebx]

    mov ebx, eax
    imul ebx, ebx, STR_SLOT_SIZE
    lea edi, [var_str + ebx]

    push esi
    mov ecx, edx
    rep movsb
    mov byte [edi], 0
    pop esi

    mov [var_str_len + eax*4], edx
    jmp .next

.next:
    inc esi
    jmp .loop

.done:
    ret

; ----------------------------------------------------------------------
; Main parsing routine: build IR, then execute it
; ----------------------------------------------------------------------
parse_all:
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

    mov eax, [cur_line]
    mov [err_line], eax
    mov eax, [cur_col]
    mov [err_col], eax

    call lex_next
    cmp dword [token_type], TOK_DOT
    je .loop

    FAILHERE msg_expected_dot, msg_expected_dot_len
    jmp .done

.do_pust:
    call parse_pust
    cmp dword [parse_failed], 0
    jne .done

    mov eax, [cur_line]
    mov [err_line], eax
    mov eax, [cur_col]
    mov [err_col], eax

    call lex_next
    cmp dword [token_type], TOK_DOT
    je .loop

    FAILHERE msg_expected_dot, msg_expected_dot_len

.done:
    ret

parser_run:
    mov dword [parse_failed], 0
    mov dword [instr_count], 0
    mov dword [var_count], 0

    ; parse and build instruction list
    call parse_all
    cmp dword [parse_failed], 0
    jne .done

    ; execute instructions
    call execute_all

.done:
    mov eax, [parse_failed]
    ret