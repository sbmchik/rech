; main.asm
; nasm -f win64 main.asm -o main.obj
; gcc main.obj -o main.exe

BITS 64
default rel

extern fopen, fread, fclose, printf, SetConsoleCP, SetConsoleOutputCP
global main

%define MAXVARS 64
%define STR_SLOT_SIZE 512

%macro ADVANCE_ONE 0
    mov     rax, [curptr]
    mov     dl, [rax]
    inc     rax
    mov     [curptr], rax

    cmp     dl, 10
    je      %%newline

    movzx   eax, dl
    and     eax, 0C0h
    cmp     eax, 080h
    je      %%done

    mov     eax, [col_no]
    inc     eax
    mov     [col_no], eax
    jmp     %%done

%%newline:
    mov     dword [col_no], 1
    mov     eax, [line_no]
    inc     eax
    mov     [line_no], eax

%%done:
%endmacro

section .data
    mode                 db "rb", 0
    usage_msg            db "Использование: main.exe <файл>", 0
    open_fail_msg        db "Не удалось открыть файл", 0
    err_fmt              db "Ошибка в строке %u, столбце %u: %s", 10, 0

    msg_expected_stmt    db "ожидалось 'Пусть' или 'Скажи'", 0
    msg_expected_name    db "ожидалось имя переменной", 0
    msg_expected_will    db "ожидалось 'будет'", 0
    msg_expected_type    db "ожидалось 'целым числом', 'строкой', 'integer' или 'str'", 0
    msg_expected_value   db "ожидалась строка в кавычках или имя переменной", 0
    msg_expected_number   db "ожидалось целое число", 0
    msg_unclosed_string  db "строка не закрыта", 0
    msg_too_long         db "строка слишком длинная", 0
    msg_expected_dot     db "ожидалась точка", 0
    msg_unknown_var      db "неизвестная переменная", 0

    fmt_str              db "%s", 10, 0
    fmt_int              db "%lld", 10, 0

    kw_pust              db 0D0h,09Fh,0D1h,083h,0D1h,081h,0D1h,082h,0D1h,08Ch
    kw_pust_len          equ $ - kw_pust

    kw_skazhi            db 0D0h,0A1h,0D0h,0BAh,0D0h,0B0h,0D0h,0B6h,0D0h,0B8h
    kw_skazhi_len        equ $ - kw_skazhi

    kw_budet             db 0D0h,0B1h,0D1h,083h,0D0h,0B4h,0D0h,0B5h,0D1h,082h
    kw_budet_len         equ $ - kw_budet

    kw_int_ru            db 0D1h,086h,0D0h,0B5h,0D0h,0BBh,0D1h,08Bh,0D0h,0BCh,20h,0D1h,087h,0D0h,0B8h,0D1h,081h,0D0h,0BBh,0D0h,0BEh,0D0h,0BCh
    kw_int_ru_len        equ $ - kw_int_ru

    kw_str_ru            db 0D1h,081h,0D1h,082h,0D1h,080h,0D0h,0BEh,0D0h,0BAh,0D0h,0BEh,0D0h,0B9h
    kw_str_ru_len        equ $ - kw_str_ru

    kw_int_en            db "integer"
    kw_int_en_len        equ $ - kw_int_en

    kw_str_en            db "str"
    kw_str_en_len        equ $ - kw_str_en

section .bss
    buffer       resb 1048576
    fileh        resq 1

    curptr       resq 1
    endptr       resq 1
    line_no      resd 1
    col_no       resd 1

    tok_start    resq 1
    tok_len      resq 1
    str_start    resq 1
    quote_ptr    resq 1
    int_value    resq 1

    var_count    resd 1
    var_type     resb MAXVARS
    var_name_ptr resq MAXVARS
    var_name_len resd MAXVARS
    var_int      resq MAXVARS
    var_str      resb MAXVARS * STR_SLOT_SIZE
    var_str_len  resd MAXVARS

section .text

main:
    sub rsp, 56
    cld

    mov [rsp+32], ecx
    mov [rsp+40], rdx

    mov ecx, 65001
    call SetConsoleCP
    mov ecx, 65001
    call SetConsoleOutputCP

    mov eax, [rsp+32]
    cmp eax, 2
    jl .usage

    mov rdx, [rsp+40]
    mov rcx, [rdx+8]
    lea rdx, [mode]
    call fopen
    test rax, rax
    jz .open_fail
    mov [fileh], rax

    lea rcx, [buffer]
    mov edx, 1
    mov r8d, 1048575
    mov r9, [fileh]
    call fread

    mov r8, rax
    lea rax, [buffer]
    mov [curptr], rax
    lea rdx, [rax + r8]
    mov [endptr], rdx
    mov byte [rax + r8], 0

    mov dword [line_no], 1
    mov dword [col_no], 1

    mov rax, [curptr]
    cmp rax, [endptr]
    jae .parse
    cmp byte [rax], 0EFh
    jne .parse
    cmp byte [rax+1], 0BBh
    jne .parse
    cmp byte [rax+2], 0BFh
    jne .parse
    add rax, 3
    mov [curptr], rax

.parse:
    call parse_program
    mov [rsp+48], eax

    mov rcx, [fileh]
    call fclose

    mov eax, [rsp+48]
    jmp .exit

.usage:
    lea rcx, [usage_msg]
    call printf
    mov eax, 1
    jmp .exit

.open_fail:
    lea rcx, [open_fail_msg]
    call printf
    mov eax, 1

.exit:
    add rsp, 56
    ret


skip_ws:
.loop:
    mov rax, [curptr]
    cmp rax, [endptr]
    jae .done

    mov dl, [rax]
    cmp dl, ' '
    je .adv
    cmp dl, 9
    je .adv
    cmp dl, 10
    je .adv
    cmp dl, 13
    je .adv
    jmp .done

.adv:
    ADVANCE_ONE
    jmp .loop

.done:
    ret


report_error:
    sub rsp, 40
    mov edx, [line_no]
    mov r8d, [col_no]
    mov r9, rcx
    lea rcx, [err_fmt]
    call printf
    add rsp, 40
    ret


parse_identifier:
    call skip_ws

    mov rax, [curptr]
    cmp rax, [endptr]
    jae .fail

    mov dl, [rax]
    cmp dl, '0'
    jb .check_other
    cmp dl, '9'
    jbe .fail

.check_other:
    cmp dl, ' '
    je .fail
    cmp dl, 9
    je .fail
    cmp dl, 10
    je .fail
    cmp dl, 13
    je .fail
    cmp dl, '.'
    je .fail
    cmp dl, '"'
    je .fail

    mov [tok_start], rax

.loop:
    mov rax, [curptr]
    cmp rax, [endptr]
    jae .done

    mov dl, [rax]
    cmp dl, ' '
    je .done
    cmp dl, 9
    je .done
    cmp dl, 10
    je .done
    cmp dl, 13
    je .done
    cmp dl, '.'
    je .done
    cmp dl, '"'
    je .done
    cmp dl, 0
    je .done

    ADVANCE_ONE
    jmp .loop

.done:
    mov rax, [curptr]
    sub rax, [tok_start]
    mov [tok_len], rax
    test rax, rax
    jz .fail

    mov eax, 1
    ret

.fail:
    xor eax, eax
    ret


parse_quoted_string:
    call skip_ws

    mov rax, [curptr]
    cmp rax, [endptr]
    jae .fail

    cmp byte [rax], '"'
    jne .fail

    ADVANCE_ONE
    mov rax, [curptr]
    mov [str_start], rax

.loop:
    mov rax, [curptr]
    cmp rax, [endptr]
    jae .unclosed

    mov dl, [rax]
    cmp dl, '"'
    je .done
    cmp dl, 10
    je .unclosed
    cmp dl, 13
    je .unclosed

    ADVANCE_ONE
    jmp .loop

.done:
    mov [quote_ptr], rax
    mov rax, [quote_ptr]
    sub rax, [str_start]
    mov [tok_len], rax
    mov eax, 1
    ret

.unclosed:
    lea rcx, [msg_unclosed_string]
    call report_error
    xor eax, eax
    ret

.fail:
    xor eax, eax
    ret


parse_integer_literal:
    call skip_ws

    mov rax, [curptr]
    cmp rax, [endptr]
    jae .fail

    xor r8, r8
    xor r9d, r9d
    xor r10d, r10d

    mov dl, [rax]
    cmp dl, '-'
    jne .digits
    mov r9d, 1
    ADVANCE_ONE

.digits:
.loop:
    mov rax, [curptr]
    cmp rax, [endptr]
    je .done

    mov dl, [rax]
    cmp dl, '0'
    jb .done
    cmp dl, '9'
    ja .done

    movzx ecx, dl
    sub ecx, '0'
    imul r8, r8, 10
    add r8, rcx
    inc r10d

    ADVANCE_ONE
    jmp .loop

.done:
    cmp r10d, 0
    je .fail

    cmp r9d, 0
    je .store
    neg r8

.store:
    mov [int_value], r8
    mov eax, 1
    ret

.fail:
    xor eax, eax
    ret


match_literal:
    ; rcx = pattern ptr, edx = pattern len
    mov r8, [curptr]
    mov r9, [endptr]
    mov r10d, edx

    lea rax, [r8 + r10]
    cmp rax, r9
    ja .fail

    xor r11d, r11d

.cmp_loop:
    cmp r11d, r10d
    je .boundary

    mov al, [r8 + r11]
    cmp al, [rcx + r11]
    jne .fail

    inc r11d
    jmp .cmp_loop

.boundary:
    lea rax, [r8 + r10]
    cmp rax, r9
    je .advance

    mov dl, [rax]
    cmp dl, ' '
    je .advance
    cmp dl, 9
    je .advance
    cmp dl, 10
    je .advance
    cmp dl, 13
    je .advance
    cmp dl, '.'
    je .advance
    cmp dl, '"'
    je .advance
    cmp dl, 0
    je .advance
    jmp .fail

.advance:
    mov ecx, r10d
.loop2:
    test ecx, ecx
    jz .success
    ADVANCE_ONE
    dec ecx
    jmp .loop2

.success:
    mov eax, 1
    ret

.fail:
    xor eax, eax
    ret


find_var:
    ; rcx = name ptr, edx = name len
    mov r10, rcx
    mov r11d, edx
    mov r9d, [var_count]
    xor r8d, r8d

.loop:
    cmp r8d, r9d
    jae .not_found

    lea rdx, [rel var_type]
    cmp byte [rdx + r8], 0
    je .next

    lea rdx, [rel var_name_len]
    mov eax, [rdx + r8*4]
    cmp eax, r11d
    jne .next

    lea rdx, [rel var_name_ptr]
    mov rdx, [rdx + r8*8]
    xor ecx, ecx

.cmp:
    cmp ecx, r11d
    je .found

    mov al, [rdx + rcx]
    cmp al, [r10 + rcx]
    jne .next

    inc ecx
    jmp .cmp

.next:
    inc r8d
    jmp .loop

.found:
    mov eax, r8d
    ret

.not_found:
    mov eax, -1
    ret


ensure_var_slot:
    ; rcx = name ptr, edx = name len
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


parse_declaration:
    sub rsp, 40

    call skip_ws

    call parse_identifier
    test eax, eax
    jz .err_name

    call skip_ws

    lea rcx, [kw_budet]
    mov edx, kw_budet_len
    call match_literal
    test eax, eax
    jz .err_will

    call skip_ws

    lea rcx, [kw_int_ru]
    mov edx, kw_int_ru_len
    call match_literal
    test eax, eax
    jnz .int_type

    lea rcx, [kw_int_en]
    mov edx, kw_int_en_len
    call match_literal
    test eax, eax
    jnz .int_type

    lea rcx, [kw_str_ru]
    mov edx, kw_str_ru_len
    call match_literal
    test eax, eax
    jnz .str_type

    lea rcx, [kw_str_en]
    mov edx, kw_str_en_len
    call match_literal
    test eax, eax
    jnz .str_type

    lea rcx, [msg_expected_type]
    call report_error
    xor eax, eax
    jmp .done

.int_type:
    call parse_integer_literal
    test eax, eax
    jz .err_num

    mov rcx, [tok_start]
    mov edx, [tok_len]
    call ensure_var_slot
    cmp eax, -1
    je .err_many

    mov r8d, eax

    mov rdx, [tok_start]
    lea r9, [rel var_name_ptr]
    mov [r9 + r8*8], rdx

    mov edx, [tok_len]
    lea r9, [rel var_name_len]
    mov [r9 + r8*4], edx

    lea r9, [rel var_type]
    mov byte [r9 + r8], 1

    mov rax, [int_value]
    lea r9, [rel var_int]
    mov [r9 + r8*8], rax

    mov eax, 1
    jmp .done

.str_type:
    call parse_quoted_string
    test eax, eax
    jz .err_str

    mov rax, [quote_ptr]
    mov rdx, [str_start]
    sub rax, rdx
    mov [tok_len], rax

    cmp rax, STR_SLOT_SIZE - 1
    ja .err_long

    mov rcx, [tok_start]
    mov edx, [tok_len]
    call ensure_var_slot
    cmp eax, -1
    je .err_many

    mov r8d, eax

    mov rdx, [tok_start]
    lea r9, [rel var_name_ptr]
    mov [r9 + r8*8], rdx

    mov edx, [tok_len]
    lea r9, [rel var_name_len]
    mov [r9 + r8*4], edx

    lea r9, [rel var_type]
    mov byte [r9 + r8], 2

    mov rsi, [str_start]
    mov rcx, [quote_ptr]
    sub rcx, rsi
    mov r9, rcx

    mov rax, r8
    imul rax, STR_SLOT_SIZE
    lea rdi, [rel var_str]
    add rdi, rax
    rep movsb
    mov byte [rdi], 0

    lea rdx, [rel var_str_len]
    mov [rdx + r8*4], r9d

    mov rax, [quote_ptr]
    mov byte [rax], '"'
    ADVANCE_ONE

    mov eax, 1
    jmp .done

.err_name:
    lea rcx, [msg_expected_name]
    call report_error
    xor eax, eax
    jmp .done

.err_will:
    lea rcx, [msg_expected_will]
    call report_error
    xor eax, eax
    jmp .done

.err_num:
    lea rcx, [msg_expected_number]
    call report_error
    xor eax, eax
    jmp .done

.err_str:
    lea rcx, [msg_unclosed_string]
    call report_error
    xor eax, eax
    jmp .done

.err_long:
    lea rcx, [msg_too_long]
    call report_error
    xor eax, eax
    jmp .done

.err_many:
    lea rcx, [msg_too_long]
    call report_error
    xor eax, eax

.done:
    add rsp, 40
    ret


parse_say:
    sub rsp, 40

    call skip_ws

    mov rax, [curptr]
    cmp rax, [endptr]
    jae .err_value

    cmp byte [rax], '"'
    je .literal

    call parse_identifier
    test eax, eax
    jz .err_value

    mov rcx, [tok_start]
    mov edx, [tok_len]
    call find_var
    cmp eax, -1
    je .err_unknown

    mov r8d, eax

    lea r9, [rel var_type]
    cmp byte [r9 + r8], 1
    je .print_int
    cmp byte [r9 + r8], 2
    je .print_str

    lea rcx, [msg_unknown_var]
    call report_error
    xor eax, eax
    jmp .done

.literal:
    call parse_quoted_string
    test eax, eax
    jz .err_value

    mov rax, [quote_ptr]
    mov byte [rax], 0

    lea rcx, [fmt_str]
    mov rdx, [str_start]
    call printf

    mov rax, [quote_ptr]
    mov byte [rax], '"'
    ADVANCE_ONE

    mov eax, 1
    jmp .done

.print_int:
    lea rcx, [fmt_int]
    lea r9, [rel var_int]
    mov rdx, [r9 + r8*8]
    call printf
    mov eax, 1
    jmp .done

.print_str:
    mov rax, r8
    imul rax, STR_SLOT_SIZE
    lea rdx, [rel var_str]
    add rdx, rax
    lea rcx, [fmt_str]
    call printf
    mov eax, 1
    jmp .done

.err_value:
    lea rcx, [msg_expected_value]
    call report_error
    xor eax, eax
    jmp .done

.err_unknown:
    lea rcx, [msg_unknown_var]
    call report_error
    xor eax, eax

.done:
    add rsp, 40
    ret


parse_program:
    sub rsp, 40

.loop:
    call skip_ws

    mov rax, [curptr]
    cmp rax, [endptr]
    jae .ok

    lea rcx, [kw_pust]
    mov edx, kw_pust_len
    call match_literal
    test eax, eax
    jnz .do_decl

    lea rcx, [kw_skazhi]
    mov edx, kw_skazhi_len
    call match_literal
    test eax, eax
    jnz .do_say

    lea rcx, [msg_expected_stmt]
    call report_error
    mov eax, 1
    jmp .done

.do_decl:
    call parse_declaration
    test eax, eax
    jz .done
    jmp .need_dot

.do_say:
    call parse_say
    test eax, eax
    jz .done

.need_dot:
    call skip_ws
    mov rax, [curptr]
    cmp rax, [endptr]
    jae .err_dot
    cmp byte [rax], '.'
    jne .err_dot

    ADVANCE_ONE
    jmp .loop

.err_dot:
    lea rcx, [msg_expected_dot]
    call report_error
    mov eax, 1
    jmp .done

.ok:
    xor eax, eax

.done:
    add rsp, 40
    ret