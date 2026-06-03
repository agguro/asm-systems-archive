; ==============================================================================
; Name:         hci_inquiry_scan.asm
; Description:  A pure x86_64 assembly Bluetooth inquiry scanner using direct 
;               Linux raw HCI sockets (no libc, no libbluetooth). It scans for nearby
;               devices, extracts their MAC addresses, requests their remote names,
;               and prints them to stdout.
; Build:        nasm -f elf64 hci_inquiry_scan.asm -o hci_inquiry_scan.o
;               ld hci_inquiry_scan.o -o hci_inquiry_scan
; Usage:        sudo ./hci_inquiry_scan
; ==============================================================================

global _start

; --- Constants & Syscall Numbers ---
sys_read        equ 0
sys_write       equ 1
sys_socket      equ 41
sys_bind        equ 49
sys_close       equ 3
sys_exit        equ 60

stdout          equ 1
stderr          equ 2

AF_BLUETOOTH    equ 31
SOCK_RAW        equ 3
BTPROTO_HCI     equ 1

; --- HCI Opcode & Event Definitions ---
OGF_LINK_CTL    equ 0x01
OCF_INQUIRY     equ 0x0001
OCF_REMOTE_NAME_REQ equ 0x0019

HCI_COMMAND_PKT equ 0x01
HCI_EVENT_PKT   equ 0x04

EVT_INQUIRY_COMP     equ 0x01
EVT_INQUIRY_RESULT   equ 0x02
EVT_CMD_STATUS       equ 0x0f
EVT_REMOTE_NAME_COMP equ 0x07

section .data
    ; Lap parameter for general inquiry: 0x9E8B33
    general_lap:    db 0x33, 0x8B, 0x9E
    
    hex_chars:      db "0123456789ABCDEF"
    unknown_name:   db "[unknown]"
    unknown_len     equ $ - unknown_name
    
    msg_err_sock:   db "opening socket failed", 10
    msg_err_sock_len equ $ - msg_err_sock
    
    two_spaces:     db "  "
    newline:        db 10

section .bss
    sockaddr_hci:   resb 6
    hci_fd:         resq 1
    
    ; Storage for up to 16 discovered MAC addresses (6 bytes each)
    dev_count:      resq 1
    dev_list:       resb 6 * 16
    
    ; Buffers for packets and string manipulation
    tx_packet:      resb 64
    rx_packet:      resb 512
    mac_str_buf:    resb 18
    name_buf:       resb 248

section .text
_start:
    ; Guarantee strict 16-byte stack alignment
    mov rbp, rsp
    and rsp, -16

    ; 1. Allocate raw HCI socket: socket(AF_BLUETOOTH, SOCK_RAW, BTPROTO_HCI)
    mov rax, sys_socket
    mov rdi, AF_BLUETOOTH
    mov rsi, SOCK_RAW
    mov rdx, BTPROTO_HCI
    syscall
    test rax, rax
    js .err_socket
    mov [hci_fd], rax

    ; 2. Bind to local adapter 0 (hci0)
    mov word [sockaddr_hci], AF_BLUETOOTH
    mov word [sockaddr_hci + 2], 0 ; dev_id = 0
    mov word [sockaddr_hci + 4], 0 ; channel = 0 (RAW)
    
    mov rax, sys_bind
    mov rdi, [hci_fd]
    mov rsi, sockaddr_hci
    mov rdx, 6
    syscall
    test rax, rax
    js .err_socket

    ; 3. Build & send HCI_Inquiry command packet
    ; Layout: [0]=0x01 (Type), [1-2]=Opcode (0x0001 | (0x01 << 10) = 0x0401)
    ;         [3]=Length (5 bytes), [4-6]=LAP, [7]=Duration (8 * 1.28s), [8]=Max Responses (0)
    mov rdi, tx_packet
    mov byte [rdi], HCI_COMMAND_PKT
    mov word [rdi + 1], 0x0401  ; Opcode for Inquiry
    mov byte [rdi + 3], 5       ; Parameter len
    mov al, [general_lap]
    mov [rdi + 4], al
    mov al, [general_lap + 1]
    mov [rdi + 5], al
    mov al, [general_lap + 2]
    mov [rdi + 6], al
    mov byte [rdi + 7], 8       ; Inquiry length (~10 seconds)
    mov byte [rdi + 8], 0       ; Unlimited responses
    
    mov rax, sys_write
    mov rdi, [hci_fd]
    mov rsi, tx_packet
    mov rdx, 9
    syscall

    mov qword [dev_count], 0

    ; 4. Inquiry Event Listening Loop
.inquiry_loop:
    mov rax, sys_read
    mov rdi, [hci_fd]
    mov rsi, rx_packet
    mov rdx, 512
    syscall
    test rax, rax
    js .close_and_exit

    cmp byte [rx_packet], HCI_EVENT_PKT
    jne .inquiry_loop

    mov rbx, rx_packet
    movzx eax, byte [rbx + 1]    ; EAX = Event code

    cmp al, EVT_INQUIRY_COMP
    je .inquiry_finished

    cmp al, EVT_INQUIRY_RESULT
    jne .inquiry_loop

    ; Parse EVT_INQUIRY_RESULT
    ; rbx + 3 points to number of responses in this event packet
    movzx ecx, byte [rbx + 3]
    test ecx, ecx
    jz .inquiry_loop

    ; rbx + 4 points to the first bdaddr
    add rbx, 4

.process_responses:
    ; Check if our local storage array is full (max 16)
    mov r8, [dev_count]
    cmp r8, 16
    jge .inquiry_loop

    ; Calculate destination pointer in dev_list (r8 * 6)
    lea rdi, [dev_list]
    mov rax, r8
    mov r9, 6
    mul r9
    add rdi, rax                ; RDI = address inside dev_list

    ; Copy 6 bytes of the found MAC address
    mov rax, [rbx]
    mov [rdi], ax
    shr rax, 16
    mov [rdi + 2], eax

    inc qword [dev_count]
    add rbx, 14                 ; Advance pointer to next inquiry response entry struct size
    dec ecx
    jnz .process_responses
    jmp .inquiry_loop

.inquiry_finished:
    ; 5. Remote Name Resolution Loop for discovered devices
    mov r12, 0                  ; R12 = current loop index loop counter

.name_resolution_loop:
    cmp r12, [dev_count]
    jge .close_and_exit

    ; Calculate pointer to current MAC address in dev_list
    lea rsi, [dev_list]
    mov rax, r12
    mov r9, 6
    mul r9
    add rsi, rax                ; RSI = pointer to current 6-byte MAC
    mov r13, rsi                ; Save MAC pointer in R13

    ; Send Remote Name Request command packet
    ; Layout: Opcode = 0x0019 | (0x01 << 10) = 0x0419
    ; Params: 6 bytes BDADDR, 1 byte Page Scan Rep Mode, 1 byte Reserved, 2 bytes Clock Offset
    mov rdi, tx_packet
    mov byte [rdi], HCI_COMMAND_PKT
    mov word [rdi + 1], 0x0419  ; Opcode
    mov byte [rdi + 3], 10      ; Parameter length (6 + 1 + 1 + 2)
    
    ; Copy MAC bytes into parameters
    mov rax, [rsi]
    mov [rdi + 4], ax
    shr rax, 16
    mov [rdi + 6], eax
    
    mov byte [rdi + 10], 0x02   ; Page scan repetition mode (R2)
    mov byte [rdi + 11], 0x00   ; Reserved
    mov word [rdi + 12], 0x0000 ; Clock offset

    mov rax, sys_write
    mov rdi, [hci_fd]
    mov rsi, tx_packet
    mov rdx, 14
    syscall

    ; Clear name buffer with zeros
    mov rdi, name_buf
    xor eax, eax
    mov rcx, 248
    rep stosb

.read_name_evt_loop:
    mov rax, sys_read
    mov rdi, [hci_fd]
    mov rsi, rx_packet
    mov rdx, 512
    syscall
    test rax, rax
    js .name_timeout_fallback

    cmp byte [rx_packet], HCI_EVENT_PKT
    jne .read_name_evt_loop
    
    cmp byte [rx_packet + 1], EVT_REMOTE_NAME_COMP
    jne .read_name_evt_loop

    ; Check status byte of the Name Request Complete packet at offset 3
    cmp byte [rx_packet + 3], 0
    jne .name_timeout_fallback

    ; Copy string name from response packet offset 10 (max 248 bytes) into name_buf
    lea rsi, [rx_packet + 10]
    mov rdi, name_buf
    mov rcx, 248
.copy_name:
    lodsb
    mov [rdi], al
    test al, al
    jz .print_result
    inc rdi
    dec rcx
    jnz .copy_name
    jmp .print_result

.name_timeout_fallback:
    ; Copy "[unknown]" string into name_buf on failure
    lea rsi, [unknown_name]
    mov rdi, name_buf
    mov rcx, unknown_len
    rep movsb

.print_result:
    ; Convert raw target MAC to format string layout output
    mov rsi, r13
    mov rdi, mac_str_buf
    call bdaddr_to_str

    ; Output formatted MAC string to terminal screen
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, mac_str_buf
    mov rdx, 17
    syscall

    ; Output separating spacer columns
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, two_spaces
    mov rdx, 2
    syscall

    ; Output extracted Device Friendly Name string representation
    mov rsi, name_buf
    call get_strlen
    mov rdx, rax
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, name_buf
    syscall

    ; Print terminating newline tracking marker character
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, newline
    mov rdx, 1
    syscall

    inc r12
    jmp .name_resolution_loop

.close_and_exit:
    mov rax, sys_close
    mov rdi, [hci_fd]
    syscall
    xor rdi, rdi
    jmp .exit

.err_socket:
    mov rax, sys_write
    mov rdi, stderr
    mov rsi, msg_err_sock
    mov rdx, msg_err_sock_len
    syscall
    mov rdi, 1

.exit:
    mov rax, sys_exit
    syscall


; --- Helper Routine: bdaddr_to_str ---
bdaddr_to_str:
    mov rcx, 5
.loop:
    movzx eax, byte [rsi + rcx]
    mov edx, eax
    shr edx, 4
    mov dl, [hex_chars + rdx]
    mov [rdi], dl
    inc rdi
    and eax, 0x0F
    mov al, [hex_chars + rax]
    mov [rdi], al
    inc rdi
    test rcx, rcx
    jz .done
    mov byte [rdi], ':'
    inc rdi
    dec rcx
    jmp .loop
.done:
    mov byte [rdi], 0
    ret

; --- Helper Routine: get_strlen ---
get_strlen:
    xor rax, rax
.loop:
    cmp byte [rsi + rax], 0
    jz .done
    inc rax
    jmp .loop
.done:
    ret