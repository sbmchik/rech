BITS 32

extern _CreateFileW@28
extern _ReadFile@20
extern _CloseHandle@4
extern _SetConsoleCP@4
extern _SetConsoleOutputCP@4

global platform_init
global platform_read_file

%define GENERIC_READ          80000000h
%define FILE_SHARE_READ       1
%define FILE_SHARE_WRITE      2
%define FILE_SHARE_DELETE     4
%define OPEN_EXISTING         3
%define FILE_ATTRIBUTE_NORMAL  80h
%define CP_UTF8               65001

section .bss
bytes_read resd 1

section .text

platform_init:
    push dword CP_UTF8
    call _SetConsoleCP@4

    push dword CP_UTF8
    call _SetConsoleOutputCP@4
    ret

; cdecl:
;   platform_read_file(path_wptr, buffer_ptr, max_len)
; returns:
;   EAX = bytes_read
;   EAX = -1 on failure
platform_read_file:
    push ebp
    mov  ebp, esp
    push ebx
    push esi
    push edi

    mov esi, [ebp+8]      ; path (WCHAR*)
    mov edi, [ebp+12]     ; buffer
    mov ecx, [ebp+16]     ; max_len

    cmp ecx, 1
    jbe .fail
    dec ecx               ; reserve 1 byte for zero terminator

    push dword 0
    push dword FILE_ATTRIBUTE_NORMAL
    push dword OPEN_EXISTING
    push dword 0
    push dword FILE_SHARE_READ
    or   dword [esp], FILE_SHARE_WRITE | FILE_SHARE_DELETE
    push dword GENERIC_READ
    push esi
    call _CreateFileW@28

    cmp eax, -1
    je .fail

    mov ebx, eax

    push dword 0
    lea  eax, [bytes_read]
    push eax
    push ecx
    push edi
    push ebx
    call _ReadFile@20

    test eax, eax
    jz .close_fail

    mov eax, [bytes_read]
    mov byte [edi+eax], 0

    push ebx
    call _CloseHandle@4

    mov eax, [bytes_read]
    jmp .done

.close_fail:
    push ebx
    call _CloseHandle@4

.fail:
    mov eax, -1

.done:
    pop edi
    pop esi
    pop ebx
    mov esp, ebp
    pop ebp
    ret