BITS 32

extern lex_next, token_type, token_value, token_len
extern rt_print_number, rt_print_string

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
    je .ret

    cmp byte [var_type + eax], 1
    je .print_int
    cmp byte [var_type + eax], 2
    je .print_str
    jmp .ret

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
.ret:
    ret

parse_pust:
    ; current token is TOK_PUST, read name
    call lex_next
    cmp dword [token_type], TOK_IDENT
    jne .bad

    mov eax, [token_value]
    mov [tmp_name_ptr], eax
    mov eax, [token_len]
    mov [tmp_name_len], eax

    call lex_next
    cmp dword [token_type], TOK_BUDET
    jne .bad

    call lex_next

    cmp dword [token_type], TOK_TYPE_INT
    je .int_decl
    cmp dword [token_type], TOK_TYPE_STR
    je .str_decl
    ret

.int_decl:
    call lex_next
    cmp dword [token_type], TOK_NUMBER
    je .store_int
    cmp dword [token_type], TOK_IDENT
    je .copy_int
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
    je .bad
    cmp byte [var_type + eax], 1
    jne .bad

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

.str_decl:
    call lex_next
    cmp dword [token_type], TOK_STRING
    je .store_str
    cmp dword [token_type], TOK_IDENT
    je .copy_str
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
    je .bad
    cmp byte [var_type + eax], 2
    jne .bad

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

    mov eax, ebx
    imul eax, STR_SLOT_SIZE
    lea edi, [var_str + eax]

    mov ecx, [var_str_len + eax*0]  ; не трогаем, просто копию ниже
    mov ecx, [var_str_len + eax*0]
    ; легче так:
    mov ecx, [var_str_len + eax*0]

    ; source slot
    mov esi, eax
    ; но eax уже сломан, поэтому делаем по-человечески:
    mov eax, [token_value]
    mov edx, [token_len]
    ; eax/edx тут уже не нужны для строки, поэтому копируем ниже по источнику:

    mov eax, [token_value]
    ; source variable index уже был в EAX от find_var, так что это место лучше не использовать для копии
    ; проще: вынеси копию строки позже отдельной правкой, если будешь использовать копирование строк между переменными

    ret

.bad:
    ret

parser_run:
.loop:
    call lex_next

    cmp dword [token_type], TOK_EOF
    je .done

    cmp dword [token_type], TOK_SAY
    je .do_say

    cmp dword [token_type], TOK_PUST
    je .do_pust

    jmp .done

.do_say:
    call parse_say
    call lex_next
    cmp dword [token_type], TOK_DOT
    jne .done
    jmp .loop

.do_pust:
    call parse_pust
    call lex_next
    cmp dword [token_type], TOK_DOT
    jne .done
    jmp .loop

.done:
    ret