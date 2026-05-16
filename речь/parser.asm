BITS 32

extern lex_next, token_type, token_value, token_len
extern token_start_line, token_start_col
extern cur_line, cur_col
extern cur_ptr, cur_peek, cur_next, cur_skip_ws
extern rt_print_int, rt_print_string
extern rt_error_pos

global parser_run

%define TOK_INT    1
%define TOK_STRING 2
%define TOK_SAY    3
%define TOK_PUST   4
%define TOK_BUDET  5
%define TOK_TYPE_INT  6
%define TOK_TYPE_STR  7
%define TOK_IDENT   8
%define TOK_DOT     9
%define TOK_EOF     10
%define TOK_TYPE_VAR 11

%define MAXVARS 64
%define STR_SLOT_SIZE 512
%define MAX_INSTRUCTIONS 4096
%define VAR_NAME_MAX 128

; runtime types
%define VT_EMPTY 0
%define VT_INT   1
%define VT_STR   2

; source kinds for IR
%define SRC_INT_LIT 0
%define SRC_STR_LIT 1
%define SRC_VAR     2

%define OP_SAY_INT   1
%define OP_SAY_STR   2
%define OP_SAY_VAR   3
%define OP_ASSIGN    4

struc Variable
    .used:     resb 1
    .type:     resb 1
    .pad:      resw 1
    .name_ptr: resd 1
    .name_len: resd 1
    .int_val:  resd 1
    .str_len:  resd 1
endstruc

struc Instruction
    .op:    resd 1
    .arg1:  resd 1
    .arg2:  resd 1
    .arg3:  resd 1
    .arg4:  resd 1
    .line:  resd 1
    .col:   resd 1
endstruc

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

%macro FAILINST 2
    push dword [ebx + Instruction.col]
    push dword [ebx + Instruction.line]
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

msg_expected_budet db 'ожидалось ключевое слово "будет".'
msg_expected_budet_len equ $ - msg_expected_budet

msg_expected_type db "ожидался тип переменной."
msg_expected_type_len equ $ - msg_expected_type

msg_expected_dot db "ожидалась точка."
msg_expected_dot_len equ $ - msg_expected_dot

msg_name_too_long db "имя переменной слишком длинное."
msg_name_too_long_len equ $ - msg_name_too_long

section .bss
; compile-time symbol table
var_count    resd 1
var_name_buf resb MAXVARS * VAR_NAME_MAX

; runtime variable state
vars         resb MAXVARS * Variable_size
var_str      resb MAXVARS * STR_SLOT_SIZE

; temporaries
tmp_name_ptr resd 1
tmp_name_len resd 1
tmp_src_idx  resd 1
stmt_line    resd 1
stmt_col     resd 1
parse_failed resd 1
err_line     resd 1
err_col      resd 1

; instruction / AST-ish IR
instructions resb MAX_INSTRUCTIONS * Instruction_size
instr_count  resd 1

section .text

; ----------------------------------------------------------------------
; find_var
; ESI = name ptr
; EDI = name len
; returns EAX = slot or -1
; ----------------------------------------------------------------------
find_var:
    push ebx
    xor ebx, ebx

.loop:
    cmp ebx, [var_count]
    jae .not_found

    mov edx, ebx
    imul edx, edx, Variable_size
    cmp byte [vars + edx + Variable.used], 0
    je .next

    mov eax, [vars + edx + Variable.name_len]
    cmp eax, edi
    jne .next

    mov edx, [vars + edx + Variable.name_ptr]
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

; ----------------------------------------------------------------------
; alloc_var_slot
; returns EAX = slot or -1
; ----------------------------------------------------------------------
alloc_var_slot:
    mov eax, [var_count]
    cmp eax, MAXVARS
    jae .full

    mov edx, eax
    imul edx, edx, Variable_size
    mov byte [vars + edx + Variable.used], 1
    inc dword [var_count]
    ret

.full:
    mov eax, -1
    ret

; ----------------------------------------------------------------------
; store_var_name
; EBX = slot
; uses tmp_name_ptr/tmp_name_len
; returns EAX=0 success, -1 fail
; ----------------------------------------------------------------------
store_var_name:
    mov ecx, [tmp_name_len]
    cmp ecx, VAR_NAME_MAX - 1
    ja .too_long

    mov edx, ebx
    imul edx, edx, Variable_size

    mov eax, ebx
    imul eax, eax, VAR_NAME_MAX
    lea edi, [var_name_buf + eax]
    mov esi, [tmp_name_ptr]
    mov eax, edi

    push ecx
    rep movsb
    mov byte [edi], 0
    pop ecx

    mov [vars + edx + Variable.name_ptr], eax
    mov [vars + edx + Variable.name_len], ecx
    xor eax, eax
    ret

.too_long:
    mov eax, -1
    ret

; ----------------------------------------------------------------------
; ensure_var_slot
; finds existing var or allocates new one and stores its name
; uses tmp_name_ptr/tmp_name_len
; returns EAX = slot or -1
; ----------------------------------------------------------------------
ensure_var_slot:
    mov esi, [tmp_name_ptr]
    mov edi, [tmp_name_len]
    call find_var
    cmp eax, -1
    jne .done

    call alloc_var_slot
    cmp eax, -1
    je .done

    mov ebx, eax
    call store_var_name
    cmp eax, -1
    jne .return_slot

    ; if the name is too long, roll back the allocation
    mov edx, ebx
    imul edx, edx, Variable_size
    mov byte [vars + edx + Variable.used], 0
    dec dword [var_count]
    mov eax, -1
    ret

.return_slot:
    mov eax, ebx
.done:
    ret

; ----------------------------------------------------------------------
; parse_say
; emits one instruction
; ----------------------------------------------------------------------
parse_say:
    call lex_next

    cmp dword [token_type], TOK_INT
    je .int
    cmp dword [token_type], TOK_STRING
    je .str
    cmp dword [token_type], TOK_IDENT
    je .ident

    FAIL msg_expected_value, msg_expected_value_len
    ret

.int:
    mov eax, [instr_count]
    imul eax, Instruction_size
    lea esi, [instructions + eax]
    mov dword [esi + Instruction.op], OP_SAY_INT
    mov ecx, [token_value]
    mov [esi + Instruction.arg1], ecx
    mov edx, [stmt_line]
    mov [esi + Instruction.line], edx
    mov edx, [stmt_col]
    mov [esi + Instruction.col], edx
    inc dword [instr_count]
    ret

.str:
    mov eax, [instr_count]
    imul eax, Instruction_size
    lea esi, [instructions + eax]
    mov dword [esi + Instruction.op], OP_SAY_STR
    mov ecx, [token_value]
    mov [esi + Instruction.arg1], ecx
    mov ecx, [token_len]
    mov [esi + Instruction.arg2], ecx
    mov edx, [stmt_line]
    mov [esi + Instruction.line], edx
    mov edx, [stmt_col]
    mov [esi + Instruction.col], edx
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
    imul eax, Instruction_size
    lea esi, [instructions + eax]
    mov dword [esi + Instruction.op], OP_SAY_VAR
    mov [esi + Instruction.arg1], edx
    mov edx, [stmt_line]
    mov [esi + Instruction.line], edx
    mov edx, [stmt_col]
    mov [esi + Instruction.col], edx
    inc dword [instr_count]
    ret

.unknown:
    FAIL msg_unknown_var, msg_unknown_var_len
    ret

; ----------------------------------------------------------------------
; parse_pust
; ----------------------------------------------------------------------
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
    je .want_int
    cmp dword [token_type], TOK_TYPE_STR
    je .want_str
    cmp dword [token_type], TOK_TYPE_VAR
    je .want_var

    FAIL msg_expected_type, msg_expected_type_len
    ret

.want_int:
    call lex_next
    cmp dword [token_type], TOK_INT
    je .int_init

    FAIL msg_expected_value, msg_expected_value_len
    ret

.want_str:
    call lex_next
    cmp dword [token_type], TOK_STRING
    je .str_init

    FAIL msg_expected_value, msg_expected_value_len
    ret

.want_var:
    call lex_next
    cmp dword [token_type], TOK_IDENT
    je .var_init

    FAIL msg_expected_ident, msg_expected_ident_len
    ret

.bad_ident:
    FAIL msg_expected_ident, msg_expected_ident_len
    ret

.bad_budet:
    FAIL msg_expected_budet, msg_expected_budet_len
    ret

; ----------------------------------------------------------------------
; integer literal assignment
; ----------------------------------------------------------------------
.int_init:
    call ensure_var_slot
    cmp eax, -1
    je .name_too_long_or_no_slot
    mov ebx, eax

    mov eax, [instr_count]
    imul eax, Instruction_size
    lea esi, [instructions + eax]
    mov dword [esi + Instruction.op], OP_ASSIGN
    mov [esi + Instruction.arg1], ebx
    mov dword [esi + Instruction.arg2], SRC_INT_LIT
    mov ecx, [token_value]
    mov [esi + Instruction.arg3], ecx
    mov dword [esi + Instruction.arg4], 0
    mov edx, [stmt_line]
    mov [esi + Instruction.line], edx
    mov edx, [stmt_col]
    mov [esi + Instruction.col], edx
    inc dword [instr_count]
    ret

; ----------------------------------------------------------------------
; string literal assignment
; ----------------------------------------------------------------------
.str_init:
    call ensure_var_slot
    cmp eax, -1
    je .name_too_long_or_no_slot
    mov ebx, eax

    mov eax, [instr_count]
    imul eax, Instruction_size
    lea esi, [instructions + eax]
    mov dword [esi + Instruction.op], OP_ASSIGN
    mov [esi + Instruction.arg1], ebx
    mov dword [esi + Instruction.arg2], SRC_STR_LIT
    mov ecx, [token_value]
    mov [esi + Instruction.arg3], ecx
    mov ecx, [token_len]
    mov [esi + Instruction.arg4], ecx
    mov edx, [stmt_line]
    mov [esi + Instruction.line], edx
    mov edx, [stmt_col]
    mov [esi + Instruction.col], edx
    inc dword [instr_count]
    ret

; ----------------------------------------------------------------------
; variable assignment: value/type copied from source variable at runtime
; ----------------------------------------------------------------------
.var_init:
    mov esi, [token_value]
    mov edi, [token_len]
    call find_var
    cmp eax, -1
    je .unknown_src
    mov [tmp_src_idx], eax

    call ensure_var_slot
    cmp eax, -1
    je .name_too_long_or_no_slot
    mov ebx, eax

    mov eax, [instr_count]
    imul eax, Instruction_size
    lea esi, [instructions + eax]
    mov dword [esi + Instruction.op], OP_ASSIGN
    mov [esi + Instruction.arg1], ebx
    mov dword [esi + Instruction.arg2], SRC_VAR
    mov ecx, [tmp_src_idx]
    mov [esi + Instruction.arg3], ecx
    mov dword [esi + Instruction.arg4], 0
    mov edx, [stmt_line]
    mov [esi + Instruction.line], edx
    mov edx, [stmt_col]
    mov [esi + Instruction.col], edx
    inc dword [instr_count]
    ret

.unknown_src:
    FAIL msg_unknown_var, msg_unknown_var_len
    ret

.name_too_long_or_no_slot:
    FAIL msg_name_too_long, msg_name_too_long_len
    ret

; ----------------------------------------------------------------------
; execute_all
; runs IR in order, so earlier SAYS see earlier state
; ----------------------------------------------------------------------
execute_all:
    xor esi, esi

.loop:
    mov eax, [instr_count]
    cmp esi, eax
    je .done

    mov eax, esi
    imul eax, Instruction_size
    lea ebx, [instructions + eax]

    mov eax, [ebx + Instruction.op]
    cmp eax, OP_SAY_INT
    je .say_int
    cmp eax, OP_SAY_STR
    je .say_str
    cmp eax, OP_SAY_VAR
    je .say_var
    cmp eax, OP_ASSIGN
    je .assign
    jmp .next

.say_int:
    mov eax, [ebx + Instruction.arg1]
    push esi
    push eax
    call rt_print_int
    add esp, 4
    pop esi
    jmp .next

.say_str:
    mov eax, [ebx + Instruction.arg1]
    mov edx, [ebx + Instruction.arg2]
    push esi
    push edx
    push eax
    call rt_print_string
    add esp, 8
    pop esi
    jmp .next

.say_var:
    mov eax, [ebx + Instruction.arg1]
    mov edx, eax
    imul edx, edx, Variable_size
    cmp byte [vars + edx + Variable.type], VT_INT
    je .say_var_int
    cmp byte [vars + edx + Variable.type], VT_STR
    je .say_var_str
    FAILINST msg_unknown_var, msg_unknown_var_len
    jmp .done

.say_var_int:
    mov eax, [vars + edx + Variable.int_val]
    push esi
    push eax
    call rt_print_int
    add esp, 4
    pop esi
    jmp .next

.say_var_str:
    mov eax, [ebx + Instruction.arg1]
    mov edx, eax
    imul edx, edx, Variable_size
    mov ecx, [vars + edx + Variable.str_len]
    imul eax, eax, STR_SLOT_SIZE
    lea eax, [var_str + eax]
    push esi
    push ecx
    push eax
    call rt_print_string
    add esp, 8
    pop esi
    jmp .next

.assign:
    mov eax, [ebx + Instruction.arg1]   ; dest slot
    mov ecx, eax
    imul ecx, ecx, Variable_size       ; dest var offset
    mov edx, [ebx + Instruction.arg2]  ; source kind

    cmp edx, SRC_INT_LIT
    je .assign_int_lit
    cmp edx, SRC_STR_LIT
    je .assign_str_lit
    cmp edx, SRC_VAR
    je .assign_var

    FAILINST msg_expected_value, msg_expected_value_len
    jmp .done

.assign_int_lit:
    mov edx, [ebx + Instruction.arg3]
    mov [vars + ecx + Variable.int_val], edx
    mov byte [vars + ecx + Variable.type], VT_INT
    mov dword [vars + ecx + Variable.str_len], 0
    jmp .next

.assign_str_lit:
    mov eax, [ebx + Instruction.arg1]   ; dest slot
    mov edx, [ebx + Instruction.arg3]   ; source ptr
    mov ecx, [ebx + Instruction.arg4]   ; source len
    cmp ecx, STR_SLOT_SIZE - 1
    jbe .len_ok_str_lit
    mov ecx, STR_SLOT_SIZE - 1
.len_ok_str_lit:
    push eax
    push ecx
    push esi

    mov esi, edx
    mov eax, [esp + 8]                  ; dest slot
    imul eax, eax, STR_SLOT_SIZE
    lea edi, [var_str + eax]
    mov ecx, [esp + 4]                  ; len
    rep movsb
    mov byte [edi], 0

    pop esi
    pop ecx
    pop eax

    imul eax, eax, Variable_size
    mov [vars + eax + Variable.str_len], ecx
    mov byte [vars + eax + Variable.type], VT_STR
    mov dword [vars + eax + Variable.int_val], 0
    jmp .next

.assign_var:
    mov edx, [ebx + Instruction.arg3]   ; source slot
    mov eax, edx
    imul eax, eax, Variable_size
    mov ecx, [ebx + Instruction.arg1]   ; dest slot

    cmp byte [vars + eax + Variable.type], VT_INT
    je .copy_var_int
    cmp byte [vars + eax + Variable.type], VT_STR
    je .copy_var_str

    FAILINST msg_unknown_var, msg_unknown_var_len
    jmp .done

.copy_var_int:
    mov edx, [vars + eax + Variable.int_val]
    imul ecx, ecx, Variable_size
    mov [vars + ecx + Variable.int_val], edx
    mov byte [vars + ecx + Variable.type], VT_INT
    mov dword [vars + ecx + Variable.str_len], 0
    jmp .next

.copy_var_str:
    mov edx, [vars + eax + Variable.str_len]
    cmp edx, STR_SLOT_SIZE - 1
    jbe .len_ok_sv
    mov edx, STR_SLOT_SIZE - 1
.len_ok_sv:
    push ecx
    push edx
    push esi

    mov esi, [ebx + Instruction.arg3]   ; source slot
    imul esi, esi, STR_SLOT_SIZE
    lea esi, [var_str + esi]

    mov eax, [ebx + Instruction.arg1]   ; dest slot
    imul eax, eax, STR_SLOT_SIZE
    lea edi, [var_str + eax]

    mov ecx, [esp + 4]
    rep movsb
    mov byte [edi], 0

    pop esi
    pop edx
    pop ecx

    mov eax, ecx
    imul eax, eax, Variable_size
    mov byte [vars + eax + Variable.type], VT_STR
    mov [vars + eax + Variable.str_len], edx
    mov dword [vars + eax + Variable.int_val], 0
    jmp .next

.next:
    inc esi
    jmp .loop

.done:
    ret

; ----------------------------------------------------------------------
; parse_all
; builds IR/AST-like instruction stream
; ----------------------------------------------------------------------
parse_all:
.loop:
    cmp dword [parse_failed], 0
    jne .done

    call lex_next
    cmp dword [token_type], TOK_EOF
    je .done

    mov eax, [token_start_line]
    mov [stmt_line], eax
    mov eax, [token_start_col]
    mov [stmt_col], eax

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

; ----------------------------------------------------------------------
; parser_run
; ----------------------------------------------------------------------
parser_run:
    mov dword [parse_failed], 0
    mov dword [instr_count], 0
    mov dword [var_count], 0

    ; clear symbol/runtime tables for a clean run
    xor eax, eax
    mov ecx, MAXVARS * Variable_size
    lea edi, [vars]
    rep stosb

    xor eax, eax
    mov ecx, MAXVARS * VAR_NAME_MAX
    lea edi, [var_name_buf]
    rep stosb

    xor eax, eax
    mov ecx, MAXVARS * STR_SLOT_SIZE
    lea edi, [var_str]
    rep stosb

    xor eax, eax
    mov ecx, MAX_INSTRUCTIONS * Instruction_size
    lea edi, [instructions]
    rep stosb

    call parse_all
    cmp dword [parse_failed], 0
    jne .done

    call execute_all

.done:
    mov eax, [parse_failed]
    ret