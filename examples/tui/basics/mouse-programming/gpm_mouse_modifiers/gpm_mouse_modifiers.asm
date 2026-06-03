; ==============================================================================
; Name:         gpm_mouse_modifiers.asm
; Description:  A pure x86_64 assembly GPM client using direct Linux syscalls.
;               It intercepts mouse clicks (GPM_DOWN), parses active keyboard
;               modifiers (Shift, Ctrl, Alt, AltGr) and buttons (Left, Right, 
;               Middle), and logs the structured combination to stdout.
; Build:        nasm -f elf64 gpm_mouse_modifiers.asm -o gpm_mouse_modifiers.o
;               ld gpm_mouse_modifiers.o -o gpm_mouse_modifiers
; Usage:        sudo ./gpm_mouse_modifiers
; ==============================================================================

global _start

; --- Constants & Syscall Numbers ---
sys_read        equ 0
sys_write       equ 1
sys_socket      equ 41
sys_connect     equ 42
sys_close       equ 3
sys_poll        equ 7
sys_exit        equ 60

stdin           equ 0
stdout          equ 1
stderr          equ 2

AF_UNIX         equ 1
SOCK_STREAM     equ 1
POLLIN          equ 0x0001

; --- GPM Definitions ---
gpm_connect_sz  equ 16
gpm_event_sz    equ 26

GPM_DOWN        equ 0x0002

; Button masks
GPM_B_LEFT      equ 4
GPM_B_MIDDLE    equ 2
GPM_B_RIGHT     equ 1

; Modifier bit positions: (1 << KG_XXX)
MASK_SHIFT      equ (1 << 0)
MASK_ALTGR      equ (1 << 1)
MASK_CTRL       equ (1 << 2)
MASK_ALT        equ (1 << 3)

section .data
    sockaddr_un:
        dw AF_UNIX
        db "/dev/gpmctl", 0
    sockaddr_un_sz equ 13

    ; Static interface logging messages
    msg_err_gpm:    db "Cannot connect to mouse server", 10
    msg_err_gpm_len equ $ - msg_err_gpm

    msg_report:     db "report string: "
    msg_report_len  equ $ - msg_report

    msg_shift:      db "Shift + "
    msg_shift_len   equ $ - msg_shift

    msg_ctrl:       db "Ctrl + "
    msg_ctrl_len    equ $ - msg_ctrl

    msg_alt:        db "Left Alt + "
    msg_alt_len     equ $ - msg_alt

    msg_altgr:      db "Right Alt + "
    msg_altgr_len   equ $ - msg_altgr

    msg_b_left:     db " Left Button click "
    msg_b_left_len  equ $ - msg_b_left

    msg_b_middle:   db " Middle Button click "
    msg_b_middle_len equ $ - msg_b_middle

    msg_b_right:    db " Right Button click "
    msg_b_right_len equ $ - msg_b_right

    newline:        db 10

section .bss
    gpm_fd:         resq 1
    poll_fds:       resb 16     ; room for stdin and gpm_fd poll structures
    gpm_conn:       resb gpm_connect_sz
    gpm_event:      resb gpm_event_sz
    stdin_char:     resb 1

section .text
_start:
    ; Secure strict 16-byte stack alignment
    mov rbp, rsp
    and rsp, -16

    ; 1. Allocate socket: socket(AF_UNIX, SOCK_STREAM, 0)
    mov rax, sys_socket
    mov rdi, AF_UNIX
    mov rsi, SOCK_STREAM
    xor rdx, rdx
    syscall
    test rax, rax
    js .err_connection
    mov [gpm_fd], rax

    ; 2. Connect to GPM daemon socket
    mov rax, sys_connect
    mov rdi, [gpm_fd]
    mov rsi, sockaddr_un
    mov rdx, sockaddr_un_sz
    syscall
    test rax, rax
    js .err_connection

    ; 3. Initialize and send Gpm_Connect option block
    mov rdi, gpm_conn
    mov word [rdi], 0xFFFF      ; eventMask = ~0
    mov word [rdi + 2], 0x0000  ; defaultMask = 0
    mov word [rdi + 4], 0x0000  ; minMod = 0
    mov word [rdi + 6], 0xFFFF  ; maxMod = ~0
    
    mov rax, 39                 ; sys_getpid
    syscall
    mov [gpm_conn + 8], eax     ; pid
    
    mov dword [gpm_conn + 12], 0 ; tty (0 = auto)

    mov rax, sys_write
    mov rdi, [gpm_fd]
    mov rsi, gpm_conn
    mov rdx, gpm_connect_sz
    syscall
    test rax, rax
    js .err_connection

    ; 4. Prepare sys_poll architecture parameters
    ; poll_fds[0] -> STDIN
    mov dword [poll_fds], stdin
    mov word [poll_fds + 4], POLLIN
    
    ; poll_fds[1] -> GPM Socket
    mov rax, [gpm_fd]
    mov dword [poll_fds + 8], eax
    mov word [poll_fds + 12], POLLIN

.poll_loop:
    mov rax, sys_poll
    mov rdi, poll_fds
    mov rsi, 2
    mov rdx, -1                 ; Infinite block wait timeout
    syscall
    test rax, rax
    js .close_and_exit

    ; Check stdin data presence
    mov ax, [poll_fds + 6]
    test ax, POLLIN
    jz .check_gpm

    ; Read character and discard (Emulating raw empty consumption loop while statement)
    mov rax, sys_read
    mov rdi, stdin
    mov rsi, stdin_char
    mov rdx, 1
    syscall
    test rax, rax
    jle .close_and_exit

.check_gpm:
    ; Check GPM socket data presence
    mov ax, [poll_fds + 14]
    test ax, POLLIN
    jz .poll_loop

    ; Read event structure data packet block
    mov rax, sys_read
    mov rdi, [gpm_fd]
    mov rsi, gpm_event
    mov rdx, gpm_event_sz
    syscall
    test rax, rax
    jle .poll_loop

    ; 5. Evaluate Event Type filter: event->type & GPM_DOWN
    ; In Gpm_Event, 'type' is a 4-byte integer located at offset 12
    mov eax, [gpm_event + 12]
    test eax, GPM_DOWN
    jz .poll_loop               ; If it's not a button-down event, skip extraction

    ; Start printing sequence for the "report string: "
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, msg_report
    mov rdx, msg_report_len
    syscall

    ; Extract modifier byte at offset 1
    movzx r12d, byte [gpm_event + 1]

    ; Check Shift Key
    test r12d, MASK_SHIFT
    jz .check_ctrl
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, msg_shift
    mov rdx, msg_shift_len
    syscall

.check_ctrl:
    ; Check Ctrl Key
    test r12d, MASK_CTRL
    jz .check_alt
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, msg_ctrl
    mov rdx, msg_ctrl_len
    syscall

.check_alt:
    ; Check Left Alt Key
    test r12d, MASK_ALT
    jz .check_altgr
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, msg_alt
    mov rdx, msg_alt_len
    syscall

.check_altgr:
    ; Check Right Alt (AltGr) Key
    test r12d, MASK_ALTGR
    jz .parse_buttons
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, msg_altgr
    mov rdx, msg_altgr_len
    syscall

.parse_buttons:
    ; Extract buttons byte at offset 0
    movzx r13d, byte [gpm_event + 0]

    ; Check Left Button click
    test r13d, GPM_B_LEFT
    jz .check_btn_middle
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, msg_b_left
    mov rdx, msg_b_left_len
    syscall

.check_btn_middle:
    ; Check Middle Button click
    test r13d, GPM_B_MIDDLE
    jz .check_btn_right
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, msg_b_middle
    mov rdx, msg_b_middle_len
    syscall

.check_btn_right:
    ; Check Right Button click
    test r13d, GPM_B_RIGHT
    jz .end_report_line
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, msg_b_right
    mov rdx, msg_b_right_len
    syscall

.end_report_line:
    ; Append terminating newline to complete line logging block
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, newline
    mov rdx, 1
    syscall

    jmp .poll_loop

.close_and_exit:
    mov rax, sys_close
    mov rdi, [gpm_fd]
    syscall
    xor rdi, rdi
    jmp .exit

.err_connection:
    mov rax, sys_write
    mov rdi, stderr
    mov rsi, msg_err_gpm
    mov rdx, msg_err_gpm_len
    syscall
    mov rdi, 1

.exit:
    mov rax, sys_exit
    syscall