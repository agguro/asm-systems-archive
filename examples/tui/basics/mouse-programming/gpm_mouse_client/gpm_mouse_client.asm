; ==============================================================================
; Name:         gpm_mouse_client.asm
; Description:  A pure x86_64 assembly GPM (General Purpose Mouse) client using 
;               direct Linux syscalls (no libgpm, no libc). It connects to the 
;               Unix socket /dev/gpmctl, uses sys_poll to multiplex stdin and 
;               the mouse socket, and prints coordinates upon mouse events.
; Build:        nasm -f elf64 gpm_mouse_client.asm -o gpm_mouse_client.o
;               ld gpm_mouse_client.o -o gpm_mouse_client
; Usage:        sudo ./gpm_mouse_client  (Requires running gpm daemon on a TTY)
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

; --- GPM Specific Struct Sizes ---
; struct Gpm_Connect {
;     unsigned short eventMask;   (2 bytes)
;     unsigned short defaultMask; (2 bytes)
;     unsigned short minMod;      (2 bytes)
;     unsigned short maxMod;      (2 bytes)
;     int pid;                    (4 bytes)
;     int tty;                    (4 bytes)
; }; Total size = 16 bytes
gpm_connect_sz  equ 16

; struct Gpm_Event {
;     unsigned char buttons, modifiers; (2 bytes)
;     unsigned short vc;                (2 bytes)
;     short dx, dy, x, y;               (8 bytes)
;     enum Gpm_Etype type;              (4 bytes - int)
;     int clicks;                       (4 bytes)
;     if numeric margin adjustments: margin, wmargin (4 bytes)
; }; Total active footprint evaluated for basic TTY streaming = 26 bytes
gpm_event_sz    equ 26

POLLIN          equ 0x0001

section .data
    gpm_socket_path: db "/dev/gpmctl", 0
    gpm_path_len     equ $ - gpm_socket_path

    ; struct sockaddr_un for Unix domain socket
    ; sun_family (2 bytes) + sun_path (108 bytes)
    sockaddr_un:
        dw AF_UNIX
        db "/dev/gpmctl", 0
    sockaddr_un_sz equ 2 + 11   ; family + length of path string including null

    ; Static messages
    msg_err_gpm:    db "Cannot connect to mouse server", 10
    msg_err_gpm_len equ $ - msg_err_gpm

    msg_event:      db "Event Type: "
    msg_event_len   equ $ - msg_event
    
    msg_at_x:       db " at x="
    msg_at_x_len    equ $ - msg_at_x
    
    msg_y:          db " y="
    msg_y_len       equ $ - msg_y

    newline:        db 10

section .bss
    gpm_fd:         resq 1
    
    ; Multiplexing storage structure for sys_poll
    ; struct pollfd { int fd; short events; short revents; } -> 8 bytes each
    poll_fds:       resb 16     ; Room for 2 pollfd structures (stdin and gpm_fd)
    
    gpm_conn:       resb gpm_connect_sz
    gpm_event:      resb gpm_event_sz
    
    ; Local string formatting workspace
    num_buf:        resb 16
    stdin_char:     resb 1

section .text
_start:
    ; Secure 16-byte stack alignment
    mov rbp, rsp
    and rsp, -16

    ; 1. Open Unix Domain Socket: socket(AF_UNIX, SOCK_STREAM, 0)
    mov rax, sys_socket
    mov rdi, AF_UNIX
    mov rsi, SOCK_STREAM
    xor rdx, rdx
    syscall
    test rax, rax
    js .err_connection
    mov [gpm_fd], rax

    ; 2. Connect to /dev/gpmctl
    mov rax, sys_connect
    mov rdi, [gpm_fd]
    mov rsi, sockaddr_un
    mov rdx, sockaddr_un_sz
    syscall
    test rax, rax
    js .err_connection

    ; 3. Initialize and transmit the Gpm_Connect option block
    ; eventMask = ~0 (0xFFFF), defaultMask = 0, minMod = 0, maxMod = ~0 (0xFFFF)
    mov rdi, gpm_conn
    mov word [rdi], 0xFFFF      ; eventMask
    mov word [rdi + 2], 0x0000  ; defaultMask
    mov word [rdi + 4], 0x0000  ; minMod
    mov word [rdi + 6], 0xFFFF  ; maxMod
    
    ; pid field (offset 8)
    mov rax, 39                 ; sys_getpid
    syscall
    mov [gpm_conn + 8], eax
    
    ; tty field (offset 12). Setting to 0 tells GPM to auto-detect current TTY
    mov dword [gpm_conn + 12], 0

    ; Send Gpm_Connect packet to the daemon
    mov rax, sys_write
    mov rdi, [gpm_fd]
    mov rsi, gpm_conn
    mov rdx, gpm_connect_sz
    syscall
    test rax, rax
    js .err_connection

    ; 4. Set up the sys_poll active array structures
    ; poll_fds[0] -> STDIN (file descriptor 0)
    mov dword [poll_fds], stdin
    mov word [poll_fds + 4], POLLIN
    
    ; poll_fds[1] -> GPM Socket descriptor
    mov rax, [gpm_fd]
    mov dword [poll_fds + 8], eax
    mov word [poll_fds + 12], POLLIN

.poll_loop:
    ; Invoke sys_poll(poll_fds, 2, -1 [infinite timeout])
    mov rax, sys_poll
    mov rdi, poll_fds
    mov rsi, 2
    mov rdx, -1
    syscall
    test rax, rax
    js .close_and_exit

    ; Check if STDIN received data (poll_fds[0].revents)
    mov ax, [poll_fds + 6]
    test ax, POLLIN
    jz .check_gpm

    ; Read character from stdin and mirror it out to stdout (Emulating Gpm_Getc loop)
    mov rax, sys_read
    mov rdi, stdin
    mov rsi, stdin_char
    mov rdx, 1
    syscall
    test rax, rax
    jle .close_and_exit         ; If EOF or error, break loop
    
    ; Echo out char
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, stdin_char
    mov rdx, 1
    syscall

.check_gpm:
    ; Check if GPM Socket received data (poll_fds[1].revents)
    mov ax, [poll_fds + 14]
    test ax, POLLIN
    jz .poll_loop

    ; Read the raw Gpm_Event record block
    mov rax, sys_read
    mov rdi, [gpm_fd]
    mov rsi, gpm_event
    mov rdx, gpm_event_sz
    syscall
    test rax, rax
    jle .poll_loop              ; Intercept transient drop misreads

    ; Execute print block: "Event Type : %d at x=%d y=%d\n"
    ; Print "Event Type: "
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, msg_event
    mov rdx, msg_event_len
    syscall

    ; Extract and print event.type (Offset 12, size 4 bytes int)
    mov rdi, [gpm_event + 12]   ; Fetch sign extended value variant context safely
    and rdi, 0xFFFFFFFF         ; Normalize integer value bounds
    call print_unsigned_int

    ; Print " at x="
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, msg_at_x
    mov rdx, msg_at_x_len
    syscall

    ; Extract and print event.x (Offset 8, size 2 bytes short signed)
    movsx rdi, word [gpm_event + 8]
    call print_unsigned_int

    ; Print " y="
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, msg_y
    mov rdx, msg_y_len
    syscall

    ; Extract and print event.y (Offset 10, size 2 bytes short signed)
    movsx rdi, word [gpm_event + 10]
    call print_unsigned_int

    ; Print newline
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


; --- Helper Routine: print_unsigned_int ---
; Inputs:  RDI = Integer number scalar value to print
; Destroys: RAX, RCX, RDX, RDI
print_unsigned_int:
    mov rax, rdi
    mov rcx, num_buf
    add rcx, 15                 ; Direct pointer to terminal trailing address byte offset
    mov byte [rcx], 0           ; Initialize string termination token
    mov rdi, 10                 ; Base radix operand

.div_loop:
    xor rdx, rdx
    div rdi                     ; Divide RAX by 10. Quotient -> RAX, Remainder -> RDX
    add dl, '0'                 ; Map raw scalar into valid ASCII char
    dec rcx
    mov [rcx], dl
    test rax, rax
    jnz .div_loop

    ; Write numeric string output using calculated dynamically string boundaries
    push rcx                    ; Save base pointer state tracking address
    mov rsi, rcx
    call get_strlen
    mov rdx, rax                ; RDX = string output width
    mov rax, sys_write
    mov rdi, stdout
    pop rsi                     ; Recover clean pointer reference string address
    syscall
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