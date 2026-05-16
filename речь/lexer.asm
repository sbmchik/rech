BITS 32

extern cur_ptr, cur_peek, cur_next, cur_skip_ws, cur_line, cur_col

global lex_next, token_type, token_value, token_len
global token_start_line, token_start_col
global try_kw

%define TOK_INT    1
%define TOK_STRING    2
%define TOK_SAY       3
%define TOK_PUST      4
%define TOK_BUDET     5
%define TOK_TYPE_INT  6
%define TOK_TYPE_STR  7
%define TOK_TYPE_VAR  11
%define TOK_IDENT     8
%define TOK_DOT       9
%define TOK_EOF       10

section .data
kw_say        db 0D0h,0A1h,0D0h,0BAh,0D0h,0B0h,0D0h,0B6h,0D0h,0B8h
kw_say_len    equ $ - kw_say

kw_pust       db 0D0h,09Fh,0D1h,083h,0D1h,081h,0D1h,082h,0D1h,08Ch
kw_pust_len   equ $ - kw_pust

kw_budet      db 0D0h,0B1h,0D1h,083h,0D0h,0B4h,0D0h,0B5h,0D1h,082h
kw_budet_len  equ $ - kw_budet

kw_int     db 0D1h,086h,0D0h,0B5h,0D0h,0BBh,0D1h,08Bh,0D0h,0BCh,20h,0D1h,087h,0D0h,0B8h,0D1h,081h,0D0h,0BBh,0D0h,0BEh,0D0h,0BCh
kw_int_len equ $ - kw_int

kw_str     db 0D1h,081h,0D1h,082h,0D1h,080h,0D0h,0BEh,0D0h,0BAh,0D0h,0BEh,0D0h,0B9h
kw_str_len equ $ - kw_str

kw_var     db 0D0h,0BFh,0D0h,0B5h,0D1h,080h,0D0h,0B5h,0D0h,0BCh,0D0h,0B5h,0D0h,0BDh,0D0h,0BDh,0D0h,0BEh,0D0h,0B9h
kw_var_len equ $ - kw_var

section .bss
token_type       resd 1
token_value      resd 1
token_len        resd 1
token_start_line resd 1
token_start_col  resd 1

int_negative     resd 1

section .text

; ESI = pattern ptr
; ECX = pattern len
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
    ; неразрывный пробел U+00A0 в UTF-8: C2 A0
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

lex_next:
    call cur_skip_ws

    mov eax, [cur_line]
    mov [token_start_line], eax
    mov eax, [cur_col]
    mov [token_start_col], eax

    call cur_peek
    cmp al, 0
    je .eof

    cmp al, '.'
    je .dot

    cmp al, '"'
    je .string

    cmp al, '-'
    je .signed_int
    cmp al, '0'
    jb .word
    cmp al, '9'
    jbe .int

.word:
    lea esi, [kw_say]
    mov ecx, kw_say_len
    mov edx, TOK_SAY
    call try_kw
    test eax, eax
    jnz .done

    lea esi, [kw_pust]
    mov ecx, kw_pust_len
    mov edx, TOK_PUST
    call try_kw
    test eax, eax
    jnz .done

    lea esi, [kw_budet]
    mov ecx, kw_budet_len
    mov edx, TOK_BUDET
    call try_kw
    test eax, eax
    jnz .done

    lea esi, [kw_int]
    mov ecx, kw_int_len
    mov edx, TOK_TYPE_INT
    call try_kw
    test eax, eax
    jnz .done

    lea esi, [kw_str]
    mov ecx, kw_str_len
    mov edx, TOK_TYPE_STR
    call try_kw
    test eax, eax
    jnz .done

    lea esi, [kw_var]
    mov ecx, kw_var_len
    mov edx, TOK_TYPE_VAR
    call try_kw
    test eax, eax
    jnz .done

    ; обычный идентификатор
    mov eax, [cur_ptr]
    mov [token_value], eax

    xor ecx, ecx
.id_loop:
    call cur_peek
    cmp al, 0
    je .id_done
    cmp al, ' '
    je .id_done
    cmp al, 9
    je .id_done
    cmp al, 10
    je .id_done
    cmp al, 13
    je .id_done
    cmp al, '.'
    je .id_done
    cmp al, '"'
    je .id_done

    call cur_next
    inc ecx
    jmp .id_loop

.id_done:
    mov [token_len], ecx
    mov dword [token_type], TOK_IDENT
    jmp .done

.signed_int:
    call cur_peek
    cmp al, '-'
    jne .int

    call cur_next
    call cur_peek
    cmp al, '0'
    jb .fail
    cmp al, '9'
    ja .fail

    mov dword [int_negative], 1
    jmp .int

.int:
    mov dword [int_negative], 0
    xor ecx, ecx
    xor edx, edx

    mov eax, [cur_ptr]
    mov [token_value], eax

.int_loop:
    call cur_peek
    cmp al, '0'
    jb .int_done
    cmp al, '9'
    ja .int_done

    imul edx, edx, 10
    movzx eax, al
    sub eax, '0'
    add edx, eax

    call cur_next
    inc ecx
    jmp .int_loop

.int_done:
    test ecx, ecx
    jz .fail

    mov [token_len], ecx
    mov [token_value], edx

    cmp dword [int_negative], 0
    je .int_not_negr
    neg dword [token_value]
.int_not_negr:
    mov dword [token_type], TOK_INT
    jmp .done

.string:
    call cur_next
    mov eax, [cur_ptr]
    mov [token_value], eax

    xor ecx, ecx
.str_loop:
    call cur_peek
    cmp al, 0
    je .fail
    cmp al, '"'
    je .str_done
    cmp al, 10
    je .fail
    cmp al, 13
    je .fail

    call cur_next
    inc ecx
    jmp .str_loop

.str_done:
    mov [token_len], ecx
    call cur_next
    mov dword [token_type], TOK_STRING
    jmp .done

.dot:
    call cur_next
    mov dword [token_type], TOK_DOT
    jmp .done

.eof:
    mov dword [token_type], TOK_EOF
    jmp .done

.fail:
    mov dword [token_type], TOK_EOF

.done:
    ret

