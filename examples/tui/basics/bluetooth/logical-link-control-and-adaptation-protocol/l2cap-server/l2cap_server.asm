; ==============================================================================
; Name:         set_flush_timeout.asm
; Description:  A pure x86_64 assembly Bluetooth HCI utility using direct Linux
;               syscalls. It requests the connection handle for a remote MAC address
;               via ioctl(HCIGETCONNINFO), builds an HCI host control command packet,
;               sends it via a raw HCI socket to set the flush timeout, and exits.
; Build:        nasm -f elf64 set_flush_timeout.asm -o set_flush_timeout.o
;               ld set_flush_timeout.o -o set_flush_timeout
; ==============================================================================

global _start

; --- Constants & Syscall Numbers ---
sys_read        equ 0
sys_write       equ 1
sys_socket      equ 41
sys_bind        equ 49
sys_ioctl       equ 16
sys_close       equ 3
sys_exit        equ 60

AF_BLUETOOTH    equ 31
SOCK_RAW        equ 3
BTPROTO_HCI     equ 1

; IOCTL code: HCIGETCONNINFO -> _IOR('H', 213, struct hci_conn_info_req)
HCIGETCONNINFO  equ 0x800448d5  

ACL_LINK        equ 1
OGF_HOST_CTL    equ 0x03        ; Host Control OGF
OCF_WRITE_FLUSH_TIMEOUT equ 0x28

HCI_COMMAND_PKT equ 0x01
HCI_EVENT_PKT   equ 0x04
EVT_CMD_COMPLETE equ 0x0e

section .data
    ; Example remote MAC address to target (Change this to your target)
    target_mac:     db 0x05, 0x53, 0xBF, 0x89, 0xC5, 0xA0  ; Reverse order (A0:C5:89:BF:53:05)
    test_timeout:   equ 4000     ; Flush timeout value

    msg_ok:         db "Flush timeout successfully configured!", 10
    msg_ok_len      equ $ - msg_ok

    msg_err:        db "An error occurred during execution.", 10
    msg_err_len     equ $ - msg_err

section .bss
    ; Layout for struct sockaddr_hci
    ; struct sockaddr_hci { sa_family_t hci_family; uint16_t hci_dev; uint16_t hci_channel; }
    sockaddr_hci:   resb 6

    ; Layout for ioctl: struct hci_conn_info_req + struct hci_conn_info
    ; bdaddr (6 bytes) + type (1 byte) + padding/alignment + hci_conn_info (handle at offset 8, etc)
    ; Total allocation size: 48 bytes is safe for requirements
    conn_info_req:  resb 64

    ; Transmit / Receive internal buffers for raw HCI packets
    tx_packet:      resb 32
    rx_packet:      resb 260

section .text
_start:
    ; Guarantee strict 16-byte stack alignment
    mov rbp, rsp
    and rsp, -16

    ; Set up arguments to execute function: set_flush_timeout(target_mac, test_timeout)
    mov rdi, target_mac
    mov rsi, test_timeout
    call set_flush_timeout
    
    test rax, rax
    js .error

    ; Print success message
    mov rax, sys_write
    mov rdi, 1                  ; stdout
    mov rsi, msg_ok
    mov rdx, msg_ok_len
    syscall
    
    xor rdi, rdi                ; Exit code 0
    jmp .exit

.error:
    ; Print error message
    mov rax, sys_write
    mov rdi, 2                  ; stderr
    mov rsi, msg_err
    mov rdx, msg_err_len
    syscall
    mov rdi, 1                  ; Exit code 1

.exit:
    mov rax, sys_exit
    syscall


; --- Function: set_flush_timeout ---
; Inputs:  RDI = pointer to 6-byte remote bdaddr_t
;          RSI = integer timeout value
; Returns: RAX = 0 on success, negative error code on failure
; Destroys: RAX, RCX, RDX, RSI, RDI, R8, R9, R10, R11, R12
set_flush_timeout:
    push rbp
    mov rbp, rsp
    push r12                    ; Save r12 (will store socket file descriptor)
    push rbx                    ; Save rbx (will store temporary parameters)
    
    mov rbx, rsi                ; Save timeout in rbx
    mov r12, -1                 ; Initialize socket fd as -1

    ; 1. Copy remote MAC to our conn_info_req structure
    mov rax, [rdi]
    mov [conn_info_req], eax    ; Copy first 4 bytes
    movzx eax, word [rdi + 4]
    mov [conn_info_req + 4], ax ; Copy remaining 2 bytes
    
    ; Set link type: cr->type = ACL_LINK
    mov byte [conn_info_req + 6], ACL_LINK

    ; 2. Open raw HCI socket (hci_open_dev replacement)
    mov rax, sys_socket
    mov rdi, AF_BLUETOOTH
    mov rsi, SOCK_RAW
    mov rdx, BTPROTO_HCI
    syscall
    test rax, rax
    js .cleanup_err
    mov r12, rax                ; r12 = dd (device descriptor)

    ; 3. Bind socket to local adapter 0 (hci_get_route bypass)
    mov word [sockaddr_hci], AF_BLUETOOTH
    mov word [sockaddr_hci + 2], 0 ; hci_dev = 0 (hci0)
    mov word [sockaddr_hci + 4], 0 ; hci_channel = 0 (HCI_CHANNEL_USER/RAW)
    
    mov rax, sys_bind
    mov rdi, r12
    mov rsi, sockaddr_hci
    mov rdx, 6
    syscall
    test rax, rax
    js .cleanup_err

    ; 4. Execute ioctl to fetch active connection handle: ioctl(dd, HCIGETCONNINFO, cr)
    mov rax, sys_ioctl
    mov rdi, r12
    mov rdx, HCIGETCONNINFO
    mov rsi, conn_info_req
    syscall
    test rax, rax
    js .cleanup_err

    ; Connection handle is located inside struct hci_conn_info at offset 8 of req
    movzx ecx, word [conn_info_req + 8] ; ECX = handle

    ; 5. Assemble Raw HCI Command Packet (hci_send_req replacement)
    ; Layout of raw command packet payload to controller:
    ; [0]: Packet Type Indicator (1 byte -> HCI_COMMAND_PKT = 0x01)
    ; [1-2]: Opcode (2 bytes -> OCF | (OGF << 10)) -> 0x28 | (0x03 << 10) = 0x0C28
    ; [3]: Parameter Total Length (1 byte -> 4 bytes payload)
    ; [4-5]: Connection Handle (2 bytes)
    ; [6-7]: Flush Timeout Value (2 bytes, Little Endian for HCI controller transport)
    
    mov rdi, tx_packet
    mov byte [rdi], HCI_COMMAND_PKT
    mov word [rdi + 1], 0x0C28  ; Opcode for Write Flush Timeout
    mov byte [rdi + 3], 4       ; Length of parameters
    mov [rdi + 4], cx           ; Connection handle
    mov [rdi + 6], bx           ; Timeout value (HCI expects Little Endian raw)

    ; Send raw command packet via sys_write
    mov rax, sys_write
    mov rdi, r12
    mov rsi, tx_packet
    mov rdx, 8                  ; Total packet size (1 + 2 + 1 + 4)
    syscall
    test rax, rax
    js .cleanup_err

    ; 6. Await EVT_CMD_COMPLETE response loop from hardware controller
.read_evt_loop:
    mov rax, sys_read
    mov rdi, r12
    mov rsi, rx_packet
    mov rdx, 260
    syscall
    test rax, rax
    js .cleanup_err

    ; Validate incoming frame signature
    ; rx_packet[0] = Packet type (Must be HCI_EVENT_PKT = 0x04)
    ; rx_packet[1] = Event code (Must be EVT_CMD_COMPLETE = 0x0e)
    cmp byte [rx_packet], HCI_EVENT_PKT
    jne .read_evt_loop
    cmp byte [rx_packet + 1], EVT_CMD_COMPLETE
    jne .read_evt_loop

    ; Structural offset map for EVT_CMD_COMPLETE layout:
    ; rx_packet[3] = Number of allowed command packets
    ; rx_packet[4-5] = Command Opcode match check (Must match 0x0C28)
    ; rx_packet[6] = Status Code returned from controller (0x00 = SUCCESS)
    cmp word [rx_packet + 4], 0x0C28
    jne .read_evt_loop          ; If response belongs to another command, continue reading

    ; Check status byte result
    movzx eax, byte [rx_packet + 6]
    test al, al
    jz .success                 ; Status 0 = Success

    ; Status error translation fallback
    mov rax, -1
    jmp .cleanup

.success:
    xor rax, rax                ; Return 0

.cleanup:
    mov rbx, rax                ; Save return state
    test r12, r12
    js .pop_exit
    mov rax, sys_close
    mov rdi, r12
    syscall
.pop_exit:
    mov rax, rbx                ; Restore return state
    pop rbx
    pop r12
    pop rbp
    ret

.cleanup_err:
    mov rbx, -1                 ; Set error flag
    jmp .cleanup