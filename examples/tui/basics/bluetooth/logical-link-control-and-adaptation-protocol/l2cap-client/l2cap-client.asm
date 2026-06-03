; ==============================================================================
; Name:         l2cap_client.asm
; Description:  A pure x86_64 assembly Bluetooth L2CAP client using direct Linux
;               syscalls (no libc, no libbluetooth). It parses a target MAC address
;               from command-line arguments, connects to PSM 0x1001, sends a
;               "hello!" message, and exits.
; Build:        nasm -f elf64 l2cap_client.asm -o l2cap_client.o
;               ld l2cap_client.o -o l2cap_client
; Usage:        sudo ./l2cap_client A0:C5:89:BF:53:05
; ==============================================================================

global _start

; --- Constants & Syscall Numbers ---
sys_write       equ 1
sys_socket      equ 41
sys_connect     equ 42
sys_close       equ 3
sys_exit        equ 60

stderr          equ 2

AF_BLUETOOTH    equ 31
SOCK_SEQPACKET  equ 5
BTPROTO_L2CAP   equ 0

; --- Struct Sizes & Offsets ---
; struct sockaddr_l2 {
;     sa_family_t    l2_family;   (2 bytes)
;     unsigned short l2_psm;      (2 bytes, Big Endian)
;     bdaddr_t       l2_bdaddr;   (6 bytes)
;     unsigned short l2_cid;      (2 bytes)
; }; total = 12 bytes
sockaddr_l2_sz  equ 12

section .data
    hello_msg:      db "hello!"
    hello_msg_len   equ $ - hello_msg

    error_msg:      db "uh oh", 10
    error_msg_len   equ $ - error_msg

    usage_msg1:     db "usage: "
    usage_msg1_len  equ $ - usage_msg1
    usage_msg2:     db " <bt_addr>", 10
    usage_msg2_len  equ $ - usage_msg2

section .bss
    addr:           resb sockaddr_l2_sz
    client_fd:      resq 1

section .text
_start:
    ; Check command-line arguments directly from stack layout
    ; [rsp]     = argc
    ; [rsp + 8] = argv[0] (program name string pointer)
    ; [rsp + 16]= argv[1] (target mac string pointer)
    
    mov r8, [rsp]               ; r8 = argc
    cmp r8, 2
    jl .print_usage

    ; Save pointers before altering the stack alignment
    mov r14, [rsp + 8]          ; r14 = argv[0]
    mov r15, [rsp + 16]         ; r15 = argv[1]

    ; Guarantee strict 16-byte stack alignment for routine boundaries
    mov rbp, rsp
    and rsp, -16

    ; 1. Clear and construct sockaddr_l2 destination layout
    mov rdi, addr
    xor eax, eax
    mov rcx, sockaddr_l2_sz
    rep stosb

    mov word [addr], AF_BLUETOOTH
    mov word [addr + 2], 0x0110 ; l2_psm = htobs(0x1001) -> 0x0110

    ; Convert argument string to raw hardware array bytes: str2ba(argv[1], &addr.l2_bdaddr)
    ; addr + 4 points to l2_bdaddr field boundary (6 bytes)
    mov rsi, r15                ; rsi = argv[1]
    mov rdi, addr + 4
    call str2ba_internal
    test rax, rax
    js .handle_error            ; Trap invalid parsing structures

    ; 2. Allocate connection socket: socket(AF_BLUETOOTH, SOCK_SEQPACKET, BTPROTO_L2CAP)
    mov rax, sys_socket
    mov rdi, AF_BLUETOOTH
    mov rsi, SOCK_SEQPACKET
    mov rdx, BTPROTO_L2CAP
    syscall
    test rax, rax
    js .handle_error
    mov [client_fd], rax

    ; 3. Establish connection: connect(s, &addr, sizeof(addr))
    mov rax, sys_connect
    mov rdi, [client_fd]
    mov rsi, addr
    mov rdx, sockaddr_l2_sz
    syscall
    test rax, rax
    js .handle_error

    ; 4. Deliver payload buffer: write(s, "hello!", 6)
    mov rax, sys_write
    mov rdi, [client_fd]
    mov rsi, hello_msg
    mov rdx, hello_msg_len
    syscall
    test rax, rax
    js .handle_error

    ; Close socket and gracefully terminate
    mov rax, sys_close
    mov rdi, [client_fd]
    syscall
    jmp .exit_success

.print_usage:
    ; Print "usage: "
    mov rax, sys_write
    mov rdi, stderr
    mov rsi, usage_msg1
    mov rdx, usage_msg1_len
    syscall

    ; Print program name dynamically from argv[0]
    mov rsi, [rsp + 8]          ; Recover argv[0] directly from clean stack offset
    call get_strlen
    mov rdx, rax                ; rdx = length of argv[0]
    mov rax, sys_write
    mov rdi, stderr
    syscall

    ; Print " <bt_addr>\n"
    mov rax, sys_write
    mov rdi, stderr
    mov rsi, usage_msg2
    mov rdx, usage_msg2_len
    syscall

    mov rax, sys_exit
    mov rdi, 2                  ; Exit code 2 as requested in C source
    syscall

.handle_error:
    mov rax, sys_write
    mov rdi, stderr
    mov rsi, error_msg
    mov rdx, error_msg_len
    syscall

    mov rdi, [client_fd]
    test rdi, rdi
    jz .exit_fail
    mov rax, sys_close
    syscall

.exit_fail:
    mov rax, sys_exit
    mov rdi, 1                  ; Exit status 1
    syscall

.exit_success:
    mov rax, sys_exit
    xor rdi, rdi                ; Exit status 0
    syscall


; --- Helper Routine: str2ba_internal ---
; Description: Converts "AA:BB:CC:DD:EE:FF" text into 6-byte raw format backwards.
str2ba_internal:
    xor ecx, ecx
.parse_loop:
    mov r8, 5
    sub r8, rcx
    movzx eax, byte [rsi]
    call hex_char_to_val
    cmp eax, -1
    je .error
    shl eax, 4
    mov edx, eax
    inc rsi
    movzx eax, byte [rsi]
    call hex_char_to_val
    cmp eax, -1
    je .error
    or edx, eax
    mov [rdi + r8], dl
    inc rsi
    inc rcx
    cmp rcx, 6
    je .done
    cmp byte [rsi], ':'
    jne .error
    inc rsi
    jmp .parse_loop
.done:
    xor rax, rax
    ret
.error:
    mov rax, -1
    ret

; --- Helper Routine: hex_char_to_val ---
hex_char_to_val:
    cmp al, '0'
    jl .invalid
    cmp al, '9'
    jle .num
    cmp al, 'a'
    jl .check_upper
    cmp al, 'f'
    jg .invalid
    sub al, 32
.check_upper:
    cmp al, 'A'
    jl .invalid
    cmp al, 'F'
    jg .invalid
    sub al, 'A'
    add al, 10
    movzx eax, al
    ret
.num:
    sub al, '0'
    movzx eax, al
    ret
.invalid:
    mov eax, -1
    ret

; --- Helper Routine: get_strlen ---
; Input:  RSI = string pointer
; Output: RAX = length of string (excludes null terminator)
get_strlen:
    xor rax, rax
.loop:
    cmp byte [rsi + rax], 0
    jz .done
    inc rax
    jmp .loop
.done:
    ret