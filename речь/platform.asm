
BITS 32

extern _CreateFileW@28
extern _ReadFile@20
extern _CloseHandle@4
extern _SetConsoleCP@4
extern _SetConsoleOutputCP@4
extern _GetLastError@0
extern _GetProcessHeap@0
extern _HeapAlloc@12
extern _HeapReAlloc@16
extern _HeapFree@12
extern _GetFileSize@8

global platform_init
global platform_alloc
global platform_realloc
global platform_free
global platform_read_file
global platform_free_buffer
global platform_last_error
global platform_last_stage

%define GENERIC_READ          80000000h
%define FILE_SHARE_READ       1
%define FILE_SHARE_WRITE      2
%define FILE_SHARE_DELETE     4
%define OPEN_EXISTING         3
%define FILE_ATTRIBUTE_NORMAL  80h
%define CP_UTF8               65001

section .bss
platform_last_error resd 1
platform_last_stage  resd 1
bytes_read           resd 1
file_size            resd 1
heap_handle          resd 1

section .text

platform_init:
    ;push dword CP_UTF8
    ;call _SetConsoleCP@4

    ;push dword CP_UTF8
    ;call _SetConsoleOutputCP@4
    ret

; cdecl:
;   platform_alloc(bytes)
; returns:
;   EAX = pointer or 0
platform_alloc:
    push ebp
    mov ebp, esp
    push ebx

    call _GetProcessHeap@0
    test eax, eax
    jz .fail

    push dword [ebp+8]
    push dword 0
    push eax
    call _HeapAlloc@12
    jmp .done

.fail:
    xor eax, eax

.done:
    pop ebx
    mov esp, ebp
    pop ebp
    ret

; cdecl:
;   platform_realloc(ptr, bytes)
; returns:
;   EAX = pointer or 0
platform_realloc:
    push ebp
    mov ebp, esp
    push ebx

    call _GetProcessHeap@0
    test eax, eax
    jz .fail

    push dword [ebp+12]    ; bytes
    push dword [ebp+8]     ; ptr
    push dword 0
    push eax
    call _HeapReAlloc@16
    jmp .done

.fail:
    xor eax, eax

.done:
    pop ebx
    mov esp, ebp
    pop ebp
    ret

; cdecl:
;   platform_free(ptr)
platform_free:
    push ebp
    mov ebp, esp
    push ebx

    mov ebx, [ebp+8]
    test ebx, ebx
    jz .done

    call _GetProcessHeap@0
    test eax, eax
    jz .done

    push ebx
    push dword 0
    push eax
    call _HeapFree@12

.done:
    pop ebx
    mov esp, ebp
    pop ebp
    ret

; cdecl:
;   platform_free_buffer(ptr)
platform_free_buffer:
    jmp platform_free

; cdecl:
;   platform_read_file(path_wptr)
; returns:
;   EAX = pointer to loaded zero-terminated buffer
;   EAX = -1 on failure
platform_read_file:
    push ebp
    mov  ebp, esp
    push ebx
    push esi
    push edi

    mov dword [platform_last_error], 0
    mov dword [platform_last_stage], 0
    mov dword [bytes_read], 0
    mov dword [file_size], 0
    mov dword [heap_handle], 0

    mov esi, [ebp+8]      ; path (WCHAR*)

    mov dword [platform_last_stage], 1

    push dword 0
    push dword FILE_ATTRIBUTE_NORMAL
    push dword OPEN_EXISTING
    push dword 0
    mov eax, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE
    push eax
    push dword GENERIC_READ
    push esi
    call _CreateFileW@28

    cmp eax, -1
    jne .got_handle

    call _GetLastError@0
    mov [platform_last_error], eax
    jmp .fail

.got_handle:
    mov ebx, eax

    push dword 0
    push ebx
    call _GetFileSize@8

    cmp eax, 0FFFFFFFFh
    jne .size_ok

    call _GetLastError@0
    test eax, eax
    jnz .close_fail

.size_ok:
    mov [file_size], eax

    mov ecx, eax
    inc ecx                    ; +1 for zero terminator

    call _GetProcessHeap@0
    test eax, eax
    jz .close_fail

    mov [heap_handle], eax

    push ecx                   ; bytes
    push dword 0               ; flags
    push eax                   ; heap handle
    call _HeapAlloc@12
    test eax, eax
    jz .close_fail

    mov edi, eax               ; buffer pointer

    mov dword [platform_last_stage], 2

    push dword 0
    lea  eax, [bytes_read]
    push eax
    mov eax, [file_size]
    push eax
    push edi
    push ebx
    call _ReadFile@20

    test eax, eax
    jnz .read_ok

    call _GetLastError@0
    mov [platform_last_error], eax

    mov eax, [heap_handle]
    test eax, eax
    jz .close_fail_only

    push edi
    push dword 0
    push eax
    call _HeapFree@12

.close_fail_only:
    push ebx
    call _CloseHandle@4
    jmp .fail

.read_ok:
    mov eax, [bytes_read]
    mov byte [edi+eax], 0

    push ebx
    call _CloseHandle@4

    mov eax, edi
    jmp .done

.close_fail:
    call _GetLastError@0
    mov [platform_last_error], eax

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
