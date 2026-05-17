


BITS 32

extern lex_next, token_type, token_value, token_len, token_overflow, token_error_kind
extern token_start_line, token_start_col
extern cur_line, cur_col
extern cur_ptr, cur_peek, cur_next, cur_skip_ws
extern rt_print_int, rt_print_string
extern rt_error_pos
extern platform_alloc, platform_realloc, platform_free

global parser_run
global parse_failed

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

 ; dynamic buffers; no fixed max vars / names / strings

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
    .str_ptr:  resd 1
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

msg_int_too_big db "целое число вне диапазона."
msg_int_too_big_len equ $ - msg_int_too_big

msg_bad_escape db "неверная экранирующая последовательность."
msg_bad_escape_len equ $ - msg_bad_escape

msg_string_too_long db "строковый литерал слишком длинный."
msg_string_too_long_len equ $ - msg_string_too_long

msg_unterminated_string db "не закрыта строка."
msg_unterminated_string_len equ $ - msg_unterminated_string

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

msg_alloc_fail db "не удалось выделить память."
msg_alloc_fail_len equ $ - msg_alloc_fail


section .bss
; runtime variable table (dynamic)
vars_ptr     resd 1
var_count    resd 1
var_cap      resd 1

; temporaries
tmp_name_ptr resd 1
tmp_name_len resd 1
tmp_src_idx  resd 1
stmt_line    resd 1
stmt_col     resd 1
parse_failed resd 1
err_line     resd 1
err_col      resd 1

; dynamic instruction buffer
instructions_ptr resd 1
instructions_cap resd 1
instr_count      resd 1

section .text

; ----------------------------------------------------------------------
; check_lex_errors
; turns lexer status into parser error messages
; ----------------------------------------------------------------------
check_lex_errors:
    cmp dword [token_overflow], 0
    jne .int_overflow

    mov eax, [token_error_kind]
    cmp eax, 0
    je .ok
    cmp eax, 1
    je .int_overflow
    cmp eax, 2
    je .bad_escape
    cmp eax, 3
    je .string_too_long
    cmp eax, 4
    je .unterminated_string
    cmp eax, 5
    je .alloc_fail
    jmp .ok

.int_overflow:
    FAIL msg_int_too_big, msg_int_too_big_len
    ret

.bad_escape:
    FAIL msg_bad_escape, msg_bad_escape_len
    ret

.string_too_long:
    FAIL msg_string_too_long, msg_string_too_long_len
    ret

.unterminated_string:
    FAIL msg_unterminated_string, msg_unterminated_string_len
    ret

.alloc_fail:
    FAIL msg_alloc_fail, msg_alloc_fail_len
    ret

.ok:
    ret


; ----------------------------------------------------------------------
; find_var
; ESI = name ptr
; EDI = name len
; returns EAX = slot or -1
; ----------------------------------------------------------------------
find_var:
    push ebx
    push esi
    push edi

    mov ebx, [vars_ptr]
    test ebx, ebx
    jz .not_found

    xor ecx, ecx

.loop:
    cmp ecx, [var_count]
    jae .not_found

    mov edx, ecx
    imul edx, edx, Variable_size

    cmp byte [ebx + edx + Variable.used], 0
    je .next

    mov eax, [ebx + edx + Variable.name_len]
    cmp eax, edi
    jne .next

    mov edx, [ebx + edx + Variable.name_ptr]
    test edx, edx
    jz .next

    push ecx
    xor ecx, ecx

.cmp:
    cmp ecx, edi
    je .found

    mov al, [edx + ecx]
    cmp al, [esi + ecx]
    jne .cmp_fail

    inc ecx
    jmp .cmp

.cmp_fail:
    pop ecx
    jmp .next

.found:
    pop ecx
    mov eax, ecx
    jmp .done

.next:
    inc ecx
    jmp .loop

.not_found:
    mov eax, -1

.done:
    pop edi
    pop esi
    pop ebx
    ret

; ----------------------------------------------------------------------
; ensure_var_capacity
; grows the variable table as needed
; ----------------------------------------------------------------------
ensure_var_capacity:
    push ebx
    push ecx
    push edx

    mov eax, [var_count]
    mov ecx, [var_cap]
    cmp eax, ecx
    jb .ok

    test ecx, ecx
    jnz .grow
    mov ecx, 32
    jmp .alloc

.grow:
    shl ecx, 1

.alloc:
    mov ebx, ecx
    mov eax, ebx
    imul eax, eax, Variable_size
    mov edx, [vars_ptr]
    test edx, edx
    jz .fresh

    push eax
    push edx
    call platform_realloc
    add esp, 8
    test eax, eax
    jz .fail

    mov [vars_ptr], eax
    mov [var_cap], ebx
    xor eax, eax
    jmp .done

.fresh:
    push eax
    call platform_alloc
    add esp, 4
    test eax, eax
    jz .fail

    mov [vars_ptr], eax
    mov [var_cap], ebx
    xor eax, eax
    jmp .done

.ok:
    xor eax, eax
    jmp .done

.fail:
    mov eax, -1

.done:
    pop edx
    pop ecx
    pop ebx
    ret

; ----------------------------------------------------------------------
; heap_dup_bytes
; ESI = source ptr
; ECX = byte count
; returns EAX = ptr with trailing zero, or 0 on failure
; ----------------------------------------------------------------------
heap_dup_bytes:
    push ebx
    push esi
    push edi

    push ecx
    lea eax, [ecx + 1]
    call platform_alloc
    test eax, eax
    jz .fail

    mov edi, eax
    pop ecx
    mov ebx, ecx
    cld
    rep movsb
    mov byte [edi], 0
    mov ecx, ebx
    jmp .done

.fail:
    pop ecx
    xor eax, eax

.done:
    pop edi
    pop esi
    pop ebx
    ret

; ----------------------------------------------------------------------
; alloc_var_slot
; returns EAX = slot or -1
; ----------------------------------------------------------------------
alloc_var_slot:
    push ebx
    push ecx
    push edx

    call ensure_var_capacity
    cmp eax, 0
    jne .full

    mov eax, [var_count]
    mov ebx, [vars_ptr]
    mov edx, eax
    imul edx, edx, Variable_size
    lea edx, [ebx + edx]

    mov byte [edx + Variable.used], 1
    mov byte [edx + Variable.type], VT_EMPTY
    mov dword [edx + Variable.name_ptr], 0
    mov dword [edx + Variable.name_len], 0
    mov dword [edx + Variable.int_val], 0
    mov dword [edx + Variable.str_ptr], 0
    mov dword [edx + Variable.str_len], 0

    inc dword [var_count]
    pop edx
    pop ecx
    pop ebx
    ret

.full:
    mov eax, -1
    pop edx
    pop ecx
    pop ebx
    ret

; ----------------------------------------------------------------------
; free_var_string
; EAX = slot
; ----------------------------------------------------------------------
free_var_string:
    push ebx
    push edx

    mov ebx, [vars_ptr]
    test ebx, ebx
    jz .done

    mov edx, eax
    imul edx, edx, Variable_size
    lea edx, [ebx + edx]

    cmp byte [edx + Variable.type], VT_STR
    jne .done

    mov eax, [edx + Variable.str_ptr]
    test eax, eax
    jz .clear
    push eax
    call platform_free
    add esp, 4

.clear:
    mov dword [edx + Variable.str_ptr], 0
    mov dword [edx + Variable.str_len], 0
    mov byte [edx + Variable.type], VT_EMPTY

.done:
    pop edx
    pop ebx
    ret

; ----------------------------------------------------------------------
; alloc_instr_slot
; returns EAX = slot index or -1, ESI = pointer to slot
; ----------------------------------------------------------------------
alloc_instr_slot:
    push ebx
    push ecx
    push edx

    mov eax, [instr_count]
    mov ecx, [instructions_cap]
    cmp eax, ecx
    jb .have_space

    test ecx, ecx
    jnz .grow
    mov ecx, 32
    jmp .resize

.grow:
    shl ecx, 1
    cmp ecx, eax
    jb .grow
.resize:
    mov ebx, ecx
    mov eax, ebx
    imul eax, eax, Instruction_size
    mov edx, [instructions_ptr]
    test edx, edx
    jz .fresh

    push eax
    push edx
    call platform_realloc
    add esp, 8
    test eax, eax
    jz .fail
    mov [instructions_ptr], eax
    mov [instructions_cap], ebx
    jmp .have_space

.fresh:
    push eax
    call platform_alloc
    add esp, 4
    test eax, eax
    jz .fail
    mov [instructions_ptr], eax
    mov [instructions_cap], ebx

.have_space:
    mov eax, [instr_count]
    mov edx, eax
    imul edx, edx, Instruction_size
    mov esi, [instructions_ptr]
    lea esi, [esi + edx]

    push edi
    mov edi, esi
    xor eax, eax
    mov ecx, Instruction_size
    rep stosb
    pop edi

    mov eax, [instr_count]
    inc dword [instr_count]

    pop edx
    pop ecx
    pop ebx
    ret

.fail:
    mov eax, -1
    xor esi, esi
    pop edx
    pop ecx
    pop ebx
    ret

; ----------------------------------------------------------------------
; store_var_name
; EBX = slot
; uses tmp_name_ptr/tmp_name_len
; returns EAX=0 success, -1 fail
; ----------------------------------------------------------------------
store_var_name:
    mov ecx, [tmp_name_len]
    mov esi, [tmp_name_ptr]
    call heap_dup_bytes
    test eax, eax
    jz .fail

    mov edx, ebx
    imul edx, edx, Variable_size
    mov ebx, [vars_ptr]
    lea edx, [ebx + edx]

    mov [edx + Variable.name_ptr], eax
    mov ecx, [tmp_name_len]
    mov [edx + Variable.name_len], ecx
    xor eax, eax
    ret

.fail:
    mov eax, -1
    ret

; ----------------------------------------------------------------------
; store_var_string_copy
; EAX = dest slot
; ESI = source ptr
; ECX = byte count
; returns EAX=0 success, -1 fail
; ----------------------------------------------------------------------
store_var_string_copy:
    push ebx
    push edx
    push edi

    mov ebx, eax
    call heap_dup_bytes
    test eax, eax
    jz .fail

    mov edx, eax
    mov edi, [vars_ptr]
    mov eax, ebx
    imul eax, eax, Variable_size
    lea edi, [edi + eax]

    mov [edi + Variable.str_ptr], edx
    mov [edi + Variable.str_len], ecx
    mov byte [edi + Variable.type], VT_STR
    mov dword [edi + Variable.int_val], 0
    xor eax, eax
    jmp .done

.fail:
    mov eax, -1

.done:
    pop edi
    pop edx
    pop ebx
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

    ; rollback on allocation failure
    mov edx, ebx
    imul edx, edx, Variable_size
    mov ebx, [vars_ptr]
    lea edx, [ebx + edx]
    mov byte [edx + Variable.used], 0
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
    call check_lex_errors
    cmp dword [parse_failed], 0
    jne .ret

    cmp dword [token_type], TOK_INT
    je .int
    cmp dword [token_type], TOK_STRING
    je .str
    cmp dword [token_type], TOK_IDENT
    je .ident

    FAIL msg_expected_value, msg_expected_value_len
    ret

.int:
    call alloc_instr_slot
    cmp eax, -1
    je .ret
    mov dword [esi + Instruction.op], OP_SAY_INT
    mov ecx, [token_value]
    mov [esi + Instruction.arg1], ecx
    mov edx, [stmt_line]
    mov [esi + Instruction.line], edx
    mov edx, [stmt_col]
    mov [esi + Instruction.col], edx
    ret

.str:
    call alloc_instr_slot
    cmp eax, -1
    je .ret
    mov dword [esi + Instruction.op], OP_SAY_STR
    mov ecx, [token_value]
    mov [esi + Instruction.arg1], ecx
    mov ecx, [token_len]
    mov [esi + Instruction.arg2], ecx
    mov edx, [stmt_line]
    mov [esi + Instruction.line], edx
    mov edx, [stmt_col]
    mov [esi + Instruction.col], edx
    ret

.ident:
    mov esi, [token_value]
    mov edi, [token_len]
    call find_var
    cmp eax, -1
    je .unknown

    mov edx, eax
    call alloc_instr_slot
    cmp eax, -1
    je .ret
    mov dword [esi + Instruction.op], OP_SAY_VAR
    mov [esi + Instruction.arg1], edx
    mov edx, [stmt_line]
    mov [esi + Instruction.line], edx
    mov edx, [stmt_col]
    mov [esi + Instruction.col], edx
    ret

.unknown:
    FAIL msg_unknown_var, msg_unknown_var_len
    ret

.ret:
    ret

; ----------------------------------------------------------------------
; parse_pust
; ----------------------------------------------------------------------
parse_pust:
    call lex_next
    call check_lex_errors
    cmp dword [parse_failed], 0
    jne .ret
    cmp dword [token_type], TOK_IDENT
    jne .bad_ident

    mov eax, [token_value]
    mov [tmp_name_ptr], eax
    mov eax, [token_len]
    mov [tmp_name_len], eax

    call lex_next
    call check_lex_errors
    cmp dword [parse_failed], 0
    jne .ret
    cmp dword [token_type], TOK_BUDET
    jne .bad_budet

    call lex_next
    call check_lex_errors
    cmp dword [parse_failed], 0
    jne .ret
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
    call check_lex_errors
    cmp dword [parse_failed], 0
    jne .ret
    cmp dword [token_type], TOK_INT
    je .int_init

    FAIL msg_expected_value, msg_expected_value_len
    ret

.want_str:
    call lex_next
    call check_lex_errors
    cmp dword [parse_failed], 0
    jne .ret
    cmp dword [token_type], TOK_STRING
    je .str_init

    FAIL msg_expected_value, msg_expected_value_len
    ret

.want_var:
    call lex_next
    call check_lex_errors
    cmp dword [parse_failed], 0
    jne .ret
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

    call alloc_instr_slot
    cmp eax, -1
    je .name_too_long_or_no_slot
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
    ret

; ----------------------------------------------------------------------
; string literal assignment
; ----------------------------------------------------------------------
.str_init:
    call ensure_var_slot
    cmp eax, -1
    je .name_too_long_or_no_slot
    mov ebx, eax

    call alloc_instr_slot
    cmp eax, -1
    je .name_too_long_or_no_slot
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

    call alloc_instr_slot
    cmp eax, -1
    je .name_too_long_or_no_slot
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
    ret

.unknown_src:
    FAIL msg_unknown_var, msg_unknown_var_len
    ret

.name_too_long_or_no_slot:
    FAIL msg_alloc_fail, msg_alloc_fail_len
    ret

.ret:
    ret


; ----------------------------------------------------------------------
; execute_all
; runs IR in order, so earlier SAYS see earlier state
; ----------------------------------------------------------------------
execute_all:
    mov edi, [vars_ptr]
    xor esi, esi

.loop:
    mov eax, [instr_count]
    cmp esi, eax
    je .done

    mov eax, esi
    imul eax, Instruction_size
    mov edx, [instructions_ptr]
    lea ebx, [edx + eax]

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
    cmp byte [edi + edx + Variable.type], VT_INT
    je .say_var_int
    cmp byte [edi + edx + Variable.type], VT_STR
    je .say_var_str
    FAILINST msg_unknown_var, msg_unknown_var_len
    jmp .done

.say_var_int:
    mov eax, [edi + edx + Variable.int_val]
    push esi
    push eax
    call rt_print_int
    add esp, 4
    pop esi
    jmp .next

.say_var_str:
    mov eax, [edi + edx + Variable.str_ptr]
    mov ecx, [edi + edx + Variable.str_len]
    test eax, eax
    jz .say_var_empty
    push esi
    push ecx
    push eax
    call rt_print_string
    add esp, 8
    pop esi
    jmp .next

.say_var_empty:
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
    mov eax, [ebx + Instruction.arg1]
    call free_var_string

    mov edx, [ebx + Instruction.arg3]
    mov [edi + ecx + Variable.int_val], edx
    mov byte [edi + ecx + Variable.type], VT_INT
    mov dword [edi + ecx + Variable.str_ptr], 0
    mov dword [edi + ecx + Variable.str_len], 0
    jmp .next

.assign_str_lit:
    mov eax, [ebx + Instruction.arg1]
    call free_var_string

    mov eax, [ebx + Instruction.arg1]   ; dest slot
    mov esi, [ebx + Instruction.arg3]   ; source ptr
    mov ecx, [ebx + Instruction.arg4]   ; source len
    call store_var_string_copy
    cmp eax, 0
    je .next
    FAILINST msg_alloc_fail, msg_alloc_fail_len
    jmp .done

.assign_var:
    mov eax, [ebx + Instruction.arg1]   ; dest slot
    mov ecx, [ebx + Instruction.arg3]   ; source slot
    cmp eax, ecx
    je .next                            ; self-assignment = no-op

    push eax
    call free_var_string
    pop ecx                             ; ecx = dest slot

    mov eax, [ebx + Instruction.arg3]   ; source slot
    mov edx, eax
    imul edx, edx, Variable_size        ; source offset
    mov eax, ecx
    imul eax, eax, Variable_size        ; dest offset

    cmp byte [edi + edx + Variable.type], VT_INT
    je .copy_var_int
    cmp byte [edi + edx + Variable.type], VT_STR
    je .copy_var_str

    FAILINST msg_unknown_var, msg_unknown_var_len
    jmp .done

.copy_var_int:
    mov edx, [edi + edx + Variable.int_val]
    mov [edi + eax + Variable.int_val], edx
    mov byte [edi + eax + Variable.type], VT_INT
    mov dword [edi + eax + Variable.str_ptr], 0
    mov dword [edi + eax + Variable.str_len], 0
    jmp .next

.copy_var_str:
    mov esi, [edi + edx + Variable.str_ptr]   ; source ptr
    mov ecx, [edi + edx + Variable.str_len]   ; source len
    test esi, esi
    jz .copy_empty_str

    mov eax, [ebx + Instruction.arg1]         ; dest slot
    call store_var_string_copy
    cmp eax, 0
    je .next
    FAILINST msg_alloc_fail, msg_alloc_fail_len
    jmp .done

.copy_empty_str:
    mov dword [edi + eax + Variable.str_ptr], 0
    mov dword [edi + eax + Variable.str_len], 0
    mov byte [edi + eax + Variable.type], VT_STR
    mov dword [edi + eax + Variable.int_val], 0
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
    call check_lex_errors
    cmp dword [parse_failed], 0
    jne .done
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
    call check_lex_errors
    cmp dword [parse_failed], 0
    jne .done
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
    call check_lex_errors
    cmp dword [parse_failed], 0
    jne .done
    cmp dword [token_type], TOK_DOT
    je .loop

    FAILHERE msg_expected_dot, msg_expected_dot_len

.done:
    ret

; ----------------------------------------------------------------------
; parser_run
; ----------------------------------------------------------------------

; ----------------------------------------------------------------------
; cleanup_parser_state
; frees all dynamically allocated variable names/strings and IR storage
; ----------------------------------------------------------------------
cleanup_parser_state:
    push ebx
    push ecx
    push edx
    push esi
    push edi

    mov esi, [vars_ptr]
    test esi, esi
    jz .skip_vars

    xor ebx, ebx
.loop_vars:
    cmp ebx, [var_count]
    jae .free_vars_array

    mov edx, ebx
    imul edx, edx, Variable_size

    mov eax, [esi + edx + Variable.name_ptr]
    test eax, eax
    jz .maybe_str
    push eax
    call platform_free
    add esp, 4

.maybe_str:
    mov eax, [esi + edx + Variable.str_ptr]
    test eax, eax
    jz .next_var
    push eax
    call platform_free
    add esp, 4

.next_var:
    inc ebx
    jmp .loop_vars

.free_vars_array:
    push esi
    call platform_free
    add esp, 4

.skip_vars:
    mov dword [vars_ptr], 0
    mov dword [var_cap], 0
    mov dword [var_count], 0

    mov eax, [instructions_ptr]
    test eax, eax
    jz .skip_instr
    push eax
    call platform_free
    add esp, 4

.skip_instr:
    mov dword [instructions_ptr], 0
    mov dword [instructions_cap], 0

    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; ----------------------------------------------------------------------
; parser_run
; ----------------------------------------------------------------------
parser_run:
    call cleanup_parser_state

    mov dword [parse_failed], 0
    mov dword [instr_count], 0
    mov dword [var_count], 0
    mov dword [instructions_ptr], 0
    mov dword [instructions_cap], 0
    mov dword [vars_ptr], 0
    mov dword [var_cap], 0

    cld

    call parse_all
    cmp dword [parse_failed], 0
    jne .done

    call execute_all

.done:
    mov eax, [parse_failed]
    ret

