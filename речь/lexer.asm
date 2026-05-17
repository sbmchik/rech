BITS 32

extern cur_ptr, cur_peek, cur_next, cur_skip_ws, cur_line, cur_col

global lex_next, token_type, token_value, token_len
global token_start_line, token_start_col
global token_overflow, token_error_kind, decoded_str_pos
global try_kw

%define TOK_INT       1
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

%define INT32_MAX_DIV10 214748364
%define INT32_MAX_MOD10 7
%define INT32_MIN_ABS_DIV10 214748364
%define INT32_MIN_ABS_MOD10 8

%define MAX_STRING_ARENA 1048576

section .data
kw_say        db 208,161,208,186,208,176,208,182,208,184
kw_say_len    equ $ - kw_say

kw_pust       db 208,159,209,131,209,129,209,130,209,140
kw_pust_len   equ $ - kw_pust

kw_budet      db 208,177,209,131,208,180,208,181,209,130
kw_budet_len  equ $ - kw_budet

kw_int     db 209,134,208,181,208,187,209,139,208,188,32,209,135,208,184,209,129,208,187,208,190,208,188
kw_int_len equ $ - kw_int

kw_str     db 209,129,209,130,209,128,208,190,208,186,208,190,208,185
kw_str_len equ $ - kw_str

kw_var     db 208,191,208,181,209,128,208,181,208,188,208,181,208,189,208,189,208,190,208,185
kw_var_len equ $ - kw_var

section .bss
token_type       resd 1
token_value      resd 1
token_len        resd 1
token_start_line resd 1
token_start_col  resd 1
token_overflow   resd 1
token_error_kind resd 1

decoded_str_pos   resd 1
string_start_pos  resd 1
decoded_str_buf   resb MAX_STRING_ARENA

int_negative      resd 1

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
    cmp al, 34
    je .advance
    ; U+00A0 in UTF-8: C2 A0
    cmp al, 194
    jne .fail
    mov ebx, [cur_ptr]
    add ebx, ecx
    cmp byte [ebx+1], 160
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

hex_digit_value:
    cmp al, '0'
    jb .bad
    cmp al, '9'
    jbe .dec
    cmp al, 'A'
    jb .lower
    cmp al, 'F'
    jbe .upper
.lower:
    cmp al, 'a'
    jb .bad
    cmp al, 'f'
    ja .bad
    sub al, 'a' - 10
    movzx eax, al
    ret
.upper:
    sub al, 'A' - 10
    movzx eax, al
    ret
.dec:
    sub al, '0'
    movzx eax, al
    ret
.bad:
    mov eax, -1
    ret

append_raw_byte:
    push edx
    mov edx, [decoded_str_pos]
    cmp edx, MAX_STRING_ARENA
    jae .too_long
    mov [decoded_str_buf + edx], al
    inc edx
    mov [decoded_str_pos], edx
    xor eax, eax
    jmp .done
.too_long:
    mov dword [token_error_kind], 3
    mov eax, -1
.done:
    pop edx
    ret

append_utf8_cp:
    push ebx
    push ecx
    push edx
    push edi

    mov ebx, eax

    cmp ebx, 0x10FFFF
    ja .bad
    cmp ebx, 0xD800
    jb .size_ok
    cmp ebx, 0xDFFF
    jbe .bad
.size_ok:
    cmp ebx, 0x7F
    jbe .one
    cmp ebx, 0x7FF
    jbe .two
    cmp ebx, 0xFFFF
    jbe .three
    mov ecx, 4
    jmp .check
.one:
    mov ecx, 1
    jmp .check
.two:
    mov ecx, 2
    jmp .check
.three:
    mov ecx, 3
.check:
    mov edx, [decoded_str_pos]
    mov eax, edx
    add eax, ecx
    cmp eax, MAX_STRING_ARENA
    ja .too_long

    lea edi, [decoded_str_buf + edx]

    cmp ecx, 1
    je .enc1
    cmp ecx, 2
    je .enc2
    cmp ecx, 3
    je .enc3

.enc4:
    mov eax, ebx
    shr eax, 18
    or al, 0F0h
    mov [edi], al

    mov eax, ebx
    shr eax, 12
    and al, 3Fh
    or al, 80h
    mov [edi+1], al

    mov eax, ebx
    shr eax, 6
    and al, 3Fh
    or al, 80h
    mov [edi+2], al

    mov eax, ebx
    and al, 3Fh
    or al, 80h
    mov [edi+3], al
    jmp .store

.enc3:
    mov eax, ebx
    shr eax, 12
    or al, 0E0h
    mov [edi], al

    mov eax, ebx
    shr eax, 6
    and al, 3Fh
    or al, 80h
    mov [edi+1], al

    mov eax, ebx
    and al, 3Fh
    or al, 80h
    mov [edi+2], al
    jmp .store

.enc2:
    mov eax, ebx
    shr eax, 6
    or al, 0C0h
    mov [edi], al

    mov eax, ebx
    and al, 3Fh
    or al, 80h
    mov [edi+1], al
    jmp .store

.enc1:
    mov [edi], bl

.store:
    mov eax, edx
    add eax, ecx
    mov [decoded_str_pos], eax
    xor eax, eax
    jmp .done

.too_long:
    mov dword [token_error_kind], 3
    mov eax, -1
    jmp .done

.bad:
    mov dword [token_error_kind], 2
    mov eax, -1

.done:
    pop edi
    pop edx
    pop ecx
    pop ebx
    ret

parse_fixed_hex:
    push ebx
    xor edx, edx
.loop:
    call cur_peek
    call hex_digit_value
    cmp eax, -1
    je .bad
    shl edx, 4
    or edx, eax
    call cur_next
    dec ecx
    jnz .loop
    mov eax, edx
    pop ebx
    ret
.bad:
    mov dword [token_error_kind], 2
    mov eax, -1
    pop ebx
    ret

parse_var_hex_escape:
    push ebx
    xor edx, edx
    xor ecx, ecx
.loop:
    call cur_peek
    call hex_digit_value
    cmp eax, -1
    je .done_digits
    shl edx, 4
    or edx, eax
    call cur_next
    inc ecx
    cmp ecx, 8
    ja .too_long_digits
    jmp .loop
.done_digits:
    cmp ecx, 0
    je .bad
    mov eax, edx
    pop ebx
    ret
.too_long_digits:
    mov dword [token_error_kind], 2
    mov eax, -1
    pop ebx
    ret
.bad:
    mov dword [token_error_kind], 2
    mov eax, -1
    pop ebx
    ret

lex_next:
    mov dword [token_overflow], 0
    mov dword [token_error_kind], 0

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

    cmp al, 34
    je .string

    cmp al, '-'
    je .signed_int
    cmp al, '0'
    jb .word
    cmp al, '9'
    jbe .int_start

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
    cmp al, 34
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
    jne .int_start

    call cur_next
    call cur_peek
    cmp al, '0'
    jb .fail
    cmp al, '9'
    ja .fail

    mov dword [int_negative], 1
    jmp .int_body

.int_start:
    mov dword [int_negative], 0

.int_body:
    xor ecx, ecx
    xor edx, edx

    mov eax, [cur_ptr]
    mov [token_value], eax

    mov ebx, INT32_MAX_DIV10
    mov edi, INT32_MAX_MOD10
    cmp dword [int_negative], 0
    je .int_loop
    mov edi, INT32_MIN_ABS_MOD10

.int_loop:
    call cur_peek
    cmp al, '0'
    jb .int_done
    cmp al, '9'
    ja .int_done

    movzx eax, al
    sub eax, '0'

    cmp edx, ebx
    ja .overflow
    jb .accumulate
    cmp eax, edi
    ja .overflow

.accumulate:
    imul edx, edx, 10
    add edx, eax
    call cur_next
    inc ecx
    jmp .int_loop

.overflow:
    mov dword [token_overflow], 1
    mov dword [token_error_kind], 1
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
    mov eax, [decoded_str_pos]
    mov [string_start_pos], eax
    lea eax, [decoded_str_buf + eax]
    mov [token_value], eax

.str_loop:
    call cur_peek
    cmp al, 0
    je .unterminated
    cmp al, 10
    je .unterminated
    cmp al, 13
    je .unterminated
    cmp al, 34
    je .str_done
    cmp al, 92
    je .escape

    call append_raw_byte
    cmp eax, 0
    jne .fail
    call cur_next
    jmp .str_loop

.escape:
    call cur_next
    call cur_peek
    cmp al, 0
    je .unterminated

    ; ASCII escapes
    cmp al, 92          ; \
    je .esc_backslash
    cmp al, 34          ; "
    je .esc_quote

    ; UTF-8 aliases for Cyrillic letters
    cmp al, 208
    je .alias_d0
    cmp al, 209
    je .alias_d1
    jmp .bad_escape

.alias_d0:
    mov ebx, [cur_ptr]
    cmp byte [ebx+1], 189    ; н
    je .esc_n
    cmp byte [ebx+1], 186    ; к
    je .esc_k
    cmp byte [ebx+1], 178    ; в
    je .esc_v
    cmp byte [ebx+1], 183    ; з
    je .esc_z
    cmp byte [ebx+1], 191    ; п
    je .esc_p
    jmp .bad_escape

.alias_d1:
    mov ebx, [cur_ptr]
    cmp byte [ebx+1], 130    ; т
    je .esc_t
    cmp byte [ebx+1], 129    ; с
    je .esc_s
    cmp byte [ebx+1], 141    ; э
    je .esc_e
    jmp .bad_escape

.esc_n:
    call cur_next
    call cur_next
    mov eax, 10
    jmp .emit_cp

.esc_t:
    call cur_next
    call cur_next
    mov eax, 9
    jmp .emit_cp

.esc_k:
    call cur_next
    call cur_next
    mov eax, 13
    jmp .emit_cp

.esc_v:
    call cur_next
    call cur_next
    mov eax, 11
    jmp .emit_cp

.esc_s:
    call cur_next
    call cur_next
    mov eax, 8
    jmp .emit_cp

.esc_z:
    call cur_next
    call cur_next
    mov eax, 7
    jmp .emit_cp

.esc_p:
    call cur_next
    call cur_next
    mov eax, 12
    jmp .emit_cp

.esc_e:
    call cur_next
    call cur_next
    mov eax, 92
    jmp .emit_cp

.esc_backslash:
    call cur_next
    mov eax, 92
    jmp .emit_cp

.esc_quote:
    call cur_next
    mov eax, 34
    jmp .emit_cp

.emit_cp:
    call append_utf8_cp
    cmp eax, 0
    jne .fail
    jmp .str_loop

.bad_escape:
    mov dword [token_error_kind], 2
    jmp .fail

.unterminated:
    mov dword [token_error_kind], 4
    jmp .fail

.str_done:
    mov eax, [decoded_str_pos]
    sub eax, [string_start_pos]
    mov [token_len], eax
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