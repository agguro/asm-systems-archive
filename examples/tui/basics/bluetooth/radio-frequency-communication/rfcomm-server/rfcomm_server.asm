; ==============================================================================
; Name:         rfcomm_server.asm
; Description:  A pure x86_64 assembly Bluetooth RFCOMM server using direct Linux
;               syscalls (no libc, no libbluetooth). It binds to channel 1,
;               accepts a connection, prints the remote MAC address, reads incoming
;               data from the client, and cleanly exits.
; Build:        nasm -f elf64 rfcomm_server.asm -o rfcomm_server.o
;               ld rfcomm_server.o -o rfcomm_server
; ==============================================================================

global _start

; --- Constants & Syscall Numbers ---
sys_read        equ 0
sys_write       equ 1
sys_socket      equ 41
sys_accept      equ 43
sys_bind        equ 49
sys_listen      equ 50
sys_close       equ 3
sys_exit        equ 60

stdout          equ 1
stderr          equ 2

AF_BLUETOOTH    equ 31
SOCK_STREAM     equ 1
BTPROTO_RFCOMM  equ 3

; --- Struct Sizes & Offsets ---
; struct sockaddr_rc {
;     sa_family_t rc_family;    (2 bytes)
;     bdaddr_t    rc_bdaddr;    (6 bytes)
;     uint8_t     rc_channel;   (1 byte)
; }; total = 10 bytes for structural safety
sockaddr_rc_sz  equ 10

section .data
    ; loc_addr construction:
    ; rc_family   = AF_BLUETOOTH (2 bytes)
    ; rc_bdaddr   = BDADDR_ANY   (6 bytes, all zeros)
    ; rc_channel  = 1            (1 byte)
    loc_addr:
        dw AF_BLUETOOTH     ; rc_family
        db 0,0,0,0,0,0      ; rc_bdaddr (BDADDR_ANY)
        db 1                ; rc_channel
        db 0                ; padding byte for 10-byte boundary alignment

    hex_chars:      db "0123456789ABCDEF"
    
    msg_accept:     db "accepted connection from "
    msg_accept_len  equ $ - msg_accept
    
    msg_recv:       db "received ["
    msg_recv_len    equ $ - msg_recv
    
    msg_recv_end:   db "]", 10
    msg_recv_end_len equ $ - msg_recv_end
    
    newline:        db 10

section .bss
    rem_addr:       resb sockaddr_rc_sz
    rem_addr_opt:   resd 1
    
    server_fd:      resq 1
    client_fd:      resq 1
    
    buf:            resb 1024
    mac_str_buf:    resb 18     ; Space for "XX:XX:XX:XX:XX:XX\0"

section .text
_start:
    ; Guarantee strict 16-byte stack alignment for safety
    mov rbp, rsp
    and rsp, -16

    ; 1. Allocate socket: socket(AF_BLUETOOTH, SOCK_STREAM, BTPROTO_RFCOMM)
    mov rax, sys_socket
    mov rdi, AF_BLUETOOTH
    mov rsi, SOCK_STREAM
    mov rdx, BTPROTO_RFCOMM
    syscall
    test rax, rax
    js .exit_error
    mov [server_fd], rax

    ; 2. Bind socket: bind(s, &loc_addr, sizeof(loc_addr))
    mov rax, sys_bind
    mov rdi, [server_fd]
    mov rsi, loc_addr
    mov rdx, sockaddr_rc_sz
    syscall
    test rax, rax
    js .exit_error

    ; 3. Put socket in listening mode: listen(s, 1)
    mov rax, sys_listen
    mov rdi, [server_fd]
    mov rsi, 1
    syscall
    test rax, rax
    js .exit_error

    ; 4. Accept connection: accept(s, &rem_addr, &opt)
    mov dword [rem_addr_opt], sockaddr_rc_sz
    mov rax, sys_accept
    mov rdi, [server_fd]
    mov rsi, rem_addr
    mov rdx, rem_addr_opt
    syscall
    test rax, rax
    js .exit_error
    mov [client_fd], rax

    ; 5. Convert incoming client MAC address to string (ba2str alternative)
    ; rem_addr + 2 points directly to the 6-byte rc_bdaddr array
    mov rsi, rem_addr + 2
    mov rdi, mac_str_buf
    call bdaddr_to_str

    ; 6. Print connection info to stderr
    mov rax, sys_write
    mov rdi, stderr
    mov rsi, msg_accept
    mov rdx, msg_accept_len
    syscall

    mov rax, sys_write
    mov rdi, stderr
    mov rsi, mac_str_buf
    mov rdx, 17                 ; Length of "XX:XX:XX:XX:XX:XX"
    syscall

    mov rax, sys_write
    mov rdi, stderr
    mov rsi, newline
    mov rdx, 1
    syscall

    ; 7. Read data from client socket: read(client, buf, sizeof(buf))
    mov rax, sys_read
    mov rdi, [client_fd]
    mov rsi, buf
    mov rdx, 1024
    syscall
    test rax, rax
    jle .close_all              ; If bytes_read <= 0, skip printing sequence
    mov r12, rax                ; Save total bytes_read in r12

    ; 8. Format and print the "received [data]" output to stdout
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, msg_recv
    mov rdx, msg_recv_len
    syscall

    mov rax, sys_write
    mov rdi, stdout
    mov rsi, buf
    mov rdx, r12                ; Actual payload length received
    syscall

    mov rax, sys_write
    mov rdi, stdout
    mov rsi, msg_recv_end
    mov rdx, msg_recv_end_len
    syscall

.close_all:
    ; 9. Close client connection file descriptor
    mov rax, sys_close
    mov rdi, [client_fd]
    syscall

    ; 10. Close listening server file descriptor
    mov rax, sys_close
    mov rdi, [server_fd]
    syscall

.exit_success:
    mov rax, sys_exit
    xor rdi, rdi                ; exit code 0
    syscall

.exit_error:
    mov rax, sys_exit
    mov rdi, 1                  ; exit code 1
    syscall


; --- Helper Routine: bdaddr_to_str ---
; Inputs:  RSI = pointer to 6-byte BDADDR (stored in reverse-endian order)
;          RDI = pointer to destination buffer (minimum 18 bytes)
; Destroys: RAX, RCX, RDX, RSI, RDI
bdaddr_to_str:
    mov rcx, 5                  ; Index loop from 5 down to 0 (Bluetooth MACs are reversed)
.loop:
    movzx eax, byte [rsi + rcx] ; Extract single hardware byte
    
    ; Parse high nibble half-byte
    mov edx, eax
    shr edx, 4
    mov dl, [hex_chars + rdx]
    mov [rdi], dl
    inc rdi
    
    ; Parse low nibble half-byte
    and eax, 0x0F
    mov al, [hex_chars + rax]
    mov [rdi], al
    inc rdi
    
    ; Inject formatting colons between individual hex pairs, except trailing byte
    test rcx, rcx
    jz .done
    mov byte [rdi], ':'
    inc rdi
    dec rcx
    jmp .loop

.done:
    mov byte [rdi], 0           ; Append null-terminator for safety
    ret