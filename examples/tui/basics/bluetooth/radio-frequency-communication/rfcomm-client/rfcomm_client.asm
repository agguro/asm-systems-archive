; ==============================================================================
; Name:         rfcomm_client.asm
; Description:  A pure x86_64 assembly Bluetooth RFCOMM client using direct Linux
;               syscalls (no libc, no libbluetooth). It parses a MAC address string,
;               connects to channel 1 of the target device, transmits a "hello!"
;               message, and cleanly exits.
; Build:        nasm -f elf64 rfcomm_client.asm -o rfcomm_client.o
;               ld rfcomm_client.o -o rfcomm_client
; ==============================================================================

global _start

; --- Constants & Syscall Numbers ---
sys_write       equ 1
sys_socket      equ 41
sys_connect     equ 42
sys_close       equ 3
sys_exit        equ 60

AF_BLUETOOTH    equ 31
SOCK_STREAM     equ 1
BTPROTO_RFCOMM  equ 3

; --- Struct Sizes & Offsets ---
; struct sockaddr_rc {
;     sa_family_t rc_family;    (2 bytes)
;     bdaddr_t    rc_bdaddr;    (6 bytes)
;     uint8_t     rc_channel;   (1 byte)
; }; total = 9 bytes (packed/aligned to 10 bytes or raw size, we use 10 for safety)
sockaddr_rc_sz  equ 10

section .data
    ; Destination MAC address string to be parsed
    dest_mac:       db "A0:C5:89:BF:53:05", 0
    
    ; Message to transmit upon successful connection
    hello_msg:      db "hello!"
    hello_msg_len   equ $ - hello_msg

    error_msg:      db "uh oh", 10
    error_msg_len   equ $ - error_msg

section .bss
    ; Preallocated space for structural address parameters
    addr:           resb sockaddr_rc_sz
    client_fd:      resq 1

section .text
_start:
    ; Secure strict 16-byte stack alignment for routine calls
    mov rbp, rsp
    and rsp, -16

    ; 1. Construct target sockaddr_rc structure manually
    ; Zero out the structure first
    mov rdi, addr
    xor eax, eax
    mov rcx, sockaddr_rc_sz
    rep stosb

    ; Set address family: addr.rc_family = AF_BLUETOOTH
    mov word [addr], AF_BLUETOOTH

    ; Set RFCOMM channel: addr.rc_channel = 1
    mov byte [addr + 8], 1

    ; Convert MAC string to raw bytes: str2ba(dest_mac, &addr.rc_bdaddr)
    ; addr + 2 points directly to the rc_bdaddr field (6 bytes)
    mov rsi, dest_mac
    mov rdi, addr + 2
    call str2ba_internal
    test rax, rax
    js .handle_error            ; If parsing failed (invalid hex), abort

    ; 2. Allocate endpoint socket: socket(AF_BLUETOOTH, SOCK_STREAM, BTPROTO_RFCOMM)
    mov rax, sys_socket
    mov rdi, AF_BLUETOOTH
    mov rsi, SOCK_STREAM
    mov rdx, BTPROTO_RFCOMM
    syscall
    test rax, rax
    js .handle_error
    mov [client_fd], rax

    ; 3. Initiate remote connection: connect(s, &addr, sizeof(addr))
    mov rax, sys_connect
    mov rdi, [client_fd]
    mov rsi, addr
    mov rdx, sockaddr_rc_sz
    syscall
    test rax, rax
    js .handle_error

    ; 4. Transmit payload: write(s, "hello!", 6)
    mov rax, sys_write
    mov rdi, [client_fd]
    mov rsi, hello_msg
    mov rdx, hello_msg_len
    syscall
    test rax, rax
    js .handle_error

    ; Close client socket and exit clean
    mov rax, sys_close
    mov rdi, [client_fd]
    syscall
    jmp .exit_success

.handle_error:
    ; Print failure diagnostic string "uh oh\n" to stderr
    mov rax, sys_write
    mov rdi, 2                  ; stderr
    mov rsi, error_msg
    mov rdx, error_msg_len
    syscall

    ; If socket was allocated, ensure it is freed before dying
    mov rdi, [client_fd]
    test rdi, rdi
    jz .exit_fail
    mov rax, sys_close
    syscall

.exit_fail:
    mov rax, sys_exit
    mov rdi, 1                  ; exit status 1
    syscall

.exit_success:
    mov rax, sys_exit
    xor rdi, rdi                ; exit status 0
    syscall


; --- Helper Routine: str2ba_internal ---
; Description: Parses standard "AA:BB:CC:DD:EE:FF" string format into 6-byte 
;              raw hardware address array in reverse (Little Endian) order.
; Inputs:      RSI = Pointer to null-terminated MAC address string
;              RDI = Pointer to 6-byte destination buffer
; Outputs:     RAX = 0 on success, -1 on parsing format error
; Destroys:    RAX, RCX, RDX, R8, RSI, RDI
str2ba_internal:
    xor ecx, ecx                ; RCX = Byte position tracker (0 to 5)
    
.parse_loop:
    ; Compute target byte index in reverse order (5 - RCX)
    mov r8q, 5
    sub r8q, rcx

    ; Process high nibble char
    movzx eax, byte [rsi]
    call hex_char_to_val
    cmp eax, -1
    je .error
    shl eax, 4
    mov edx, eax                ; Store high nibble value temporarily in EDX

    inc rsi                     ; Shift to low nibble char
    movzx eax, byte [rsi]
    call hex_char_to_val
    cmp eax, -1
    je .error
    or edx, eax                 ; Combine low nibble to complete the full byte

    ; Write completed byte to appropriate reverse offset target buffer
    mov [rdi + r8q], dl
    
    inc rsi                     ; Point to potential separating colon ':' or null-terminator
    inc rcx                     ; Target next segment byte
    cmp rcx, 6
    je .done

    ; Verify correct syntax separating character delimiter
    cmp byte [rsi], ':'
    jne .error
    inc rsi                     ; Skip over the colon token separator
    jmp .parse_loop

.done:
    xor rax, rax                ; Return status success indicator
    ret

.error:
    mov rax, -1                 ; Return syntax fault status indicator
    ret


; --- Sub-Helper Routine: hex_char_to_val ---
; Input:  AL = ASCII character byte code ('0'-'9', 'A'-'F', 'a'-'f')
; Output: EAX = Integer scalar numeric value (0-15), or -1 if invalid token
hex_char_to_val:
    cmp al, '0'
    jl .invalid
    cmp al, '9'
    jle .num
    
    ; Convert lowercase letters inline to uppercase variants
    cmp al, 'a'
    jl .check_upper
    cmp al, 'f'
    jg .invalid
    sub al, 32                  ; Normalize down to uppercase range match

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