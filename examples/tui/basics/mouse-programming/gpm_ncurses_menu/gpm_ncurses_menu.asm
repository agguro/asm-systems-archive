; ==============================================================================
; Name:         gpm_ncurses_menu.asm
; Description:  A pure x86_64 assembly interactive TUI menu using GPM mouse events
;               and raw ANSI/VT100 escape sequences (no ncurses, no libgpm, no libc).
;               It renders a centered window box, handles highlighting on hover 
;               (GPM_MOVE), registers clicks (GPM_DOWN), and exits cleanly.
; Build:        nasm -f elf64 gpm_ncurses_menu.asm -o gpm_ncurses_menu.o
;               ld gpm_ncurses_menu.o -o gpm_ncurses_menu
; Usage:        sudo ./gpm_ncurses_menu
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

; --- GPM & UI Definitions ---
gpm_connect_sz  equ 16
gpm_event_sz    equ 26

GPM_MOVE        equ 0x0001
GPM_DOWN        equ 0x0002

MENU_WIDTH      equ 30
MENU_HEIGHT     equ 10
N_CHOICES       equ 5

; Centering math (assuming 80x24 terminal)
START_X         equ (80 - MENU_WIDTH) / 2
START_Y         equ (24 - MENU_HEIGHT) / 2

section .data
    sockaddr_un:
        dw AF_UNIX
        db "/dev/gpmctl", 0
    sockaddr_un_sz equ 13

    ; Menu Choices strings
    choice_1:       db "Choice 1", 0
    choice_2:       db "Choice 2", 0
    choice_3:       db "Choice 3", 0
    choice_4:       db "Choice 4", 0
    choice_5:       db "Exit", 0

    ; Array of pointers to choices
    choices:        dq choice_1, choice_2, choice_3, choice_4, choice_5
    
    ; Choices string lengths for boundary checking
    choice_lens:    db 8, 8, 8, 8, 4

    ; ANSI Escape Sequences
    cls:            db 0x1B, "[2J", 0x1B, "[H"      ; Clear screen & Home
    cls_len         equ $ - cls
    hide_cursor:    db 0x1B, "[?25l"                ; Hide blinking cursor
    hide_cursor_len equ $ - hide_cursor
    show_cursor:    db 0x1B, "[?25h"                ; Show blinking cursor
    show_cursor_len equ $ - show_cursor
    
    attr_reverse:   db 0x1B, "[7m"                  ; ncurses A_REVERSE
    attr_rev_len    equ $ - attr_reverse
    attr_reset:     db 0x1B, "[0m"                  ; Reset attributes
    attr_reset_len  equ $ - attr_reset

    ; UI Elements
    msg_err_gpm:    db "Cannot connect to mouse server", 10
    msg_err_gpm_len equ $ - msg_err_gpm
    
    msg_selection:  db "Choice made is : "
    msg_sel_len     equ $ - msg_selection
    msg_str_chosen: db " String Chosen is \""
    msg_str_len     equ $ - msg_str_chosen
    quote_newline:  db "\"", 10
    
    spaces_clear:   db "                                                                                "
    spaces_len      equ $ - spaces_clear

    box_top_bottom: db "+"
                    times MENU_WIDTH - 2 db "-"
                    db "+"
    box_tb_len      equ $ - box_top_bottom
    
    box_side:       db "|"
                    times MENU_WIDTH - 2 db " "
                    db "|"
    box_side_len    equ $ - box_side

section .bss
    gpm_fd:         resq 1
    poll_fds:       resb 16
    gpm_conn:       resb gpm_connect_sz
    gpm_event:      resb gpm_event_sz
    stdin_char:     resb 1
    
    current_hl:     resq 1      ; Currently highlighted index (1-based)
    fmt_buf:        resb 32     ; Buffer for coordinate moving sequences
    num_buf:        resb 16

section .text
_start:
    ; Secure 16-byte stack alignment
    mov rbp, rsp
    and rsp, -16

    ; 1. Setup raw terminal UI state
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, cls
    mov rdx, cls_len
    syscall
    
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, hide_cursor
    mov rdx, hide_cursor_len
    syscall

    ; 2. Connect to GPM Socket
    mov rax, sys_socket
    mov rdi, AF_UNIX
    mov rsi, SOCK_STREAM
    xor rdx, rdx
    syscall
    test rax, rax
    js .err_connection
    mov [gpm_fd], rax

    mov rax, sys_connect
    mov rdi, [gpm_fd]
    mov rsi, sockaddr_un
    mov rdx, sockaddr_un_sz
    syscall
    test rax, rax
    js .err_connection

    ; 3. Gpm_Connect configuration
    mov rdi, gpm_conn
    mov word [rdi], 0xFFFF      ; eventMask
    mov word [rdi + 2], 0x0000  ; defaultMask
    mov word [rdi + 4], 0x0000  ; minMod
    mov word [rdi + 6], 0xFFFF  ; maxMod
    mov rax, 39                 ; sys_getpid
    syscall
    mov [gpm_conn + 8], eax
    mov dword [gpm_conn + 12], 0 ; auto TTY

    mov rax, sys_write
    mov rdi, [gpm_fd]
    mov rsi, gpm_conn
    mov rdx, gpm_connect_sz
    syscall
    test rax, rax
    js .err_connection

    ; Render base initial menu frame with choice 1 highlighted
    mov qword [current_hl], 1
    call draw_menu

    ; 4. Multiplexing main loop via sys_poll
    mov dword [poll_fds], stdin
    mov word [poll_fds + 4], POLLIN
    mov rax, [gpm_fd]
    mov dword [poll_fds + 8], eax
    mov word [poll_fds + 12], POLLIN

.main_loop:
    mov rax, sys_poll
    mov rdi, poll_fds
    mov rsi, 2
    mov rdx, -1
    syscall
    test rax, rax
    js .close_and_exit

    ; Flush stdin to prevent terminal blocking
    mov ax, [poll_fds + 6]
    test ax, POLLIN
    jz .check_gpm_socket
    mov rax, sys_read
    mov rdi, stdin
    mov rsi, stdin_char
    mov rdx, 1
    syscall

.check_gpm_socket:
    mov ax, [poll_fds + 14]
    test ax, POLLIN
    jz .main_loop

    mov rax, sys_read
    mov rdi, [gpm_fd]
    mov rsi, gpm_event
    mov rdx, gpm_event_sz
    syscall
    test rax, rax
    jle .main_loop

    ; 5. Evaluate hover/movement matrix: event->type & GPM_MOVE
    mov eax, [gpm_event + 12]   ; event->type
    test eax, GPM_MOVE
    jz .check_click

    ; Calculate if mouse is inside choices box boundaries
    movzx edi, word [gpm_event + 8]  ; event->x
    movzx esi, word [gpm_event + 10] ; event->y
    call report_choice
    test rax, rax
    js .main_loop               ; Mouse outside options range
    
    cmp rax, [current_hl]
    je .main_loop               ; Already highlighted, skip redraw
    mov [current_hl], rax
    call draw_menu
    jmp .main_loop

.check_click:
    test eax, GPM_DOWN
    jz .main_loop

    movzx edi, word [gpm_event + 8]  ; event->x
    movzx esi, word [gpm_event + 10] ; event->y
    call report_choice
    test rax, rax
    js .main_loop
    
    ; If 'Exit' (Choice 5) is clicked, break loop
    cmp rax, N_CHOICES
    je .close_and_exit
    
    ; Otherwise, print report text on row 23
    push rax                    ; Save selected index
    call clear_row_23
    
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, msg_selection
    mov rdx, msg_sel_len
    syscall
    
    pop r12                     ; Restore selected index
    push r12
    mov rdi, r12
    call print_unsigned_int
    
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, msg_str_chosen
    mov rdx, msg_str_len
    syscall
    
    pop r12
    dec r12                     ; 0-indexed array pointer
    mov rsi, [choices + r12 * 8]
    push rsi
    call get_strlen
    mov rdx, rax
    mov rax, sys_write
    mov rdi, stdout
    pop rsi
    syscall
    
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, quote_newline
    mov rdx, 2
    syscall
    
    jmp .main_loop

.close_and_exit:
    ; Restore original screen conditions
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, cls
    mov rdx, cls_len
    syscall
    
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, show_cursor
    mov rdx, show_cursor_len
    syscall

    mov rax, sys_close
    mov rdi, [gpm_fd]
    syscall
    xor rdi, rdi
    mov rax, sys_exit
    syscall

.err_connection:
    mov rax, sys_write
    mov rdi, stderr
    mov rsi, msg_err_gpm
    mov rdx, msg_err_gpm_len
    syscall
    mov rdi, 1
    mov rax, sys_exit
    syscall


; --- Subroutine: report_choice ---
; Inputs:  EDI = mouse_x, ESI = mouse_y
; Returns: RAX = choice index (1 to 5), or -1 if out of bounds
report_choice:
    ; check X boundary: must be between (START_X + 2) and (START_X + MENU_WIDTH - 2)
    cmp edi, START_X + 2
    jl .out
    cmp edi, START_X + MENU_WIDTH - 2
    jg .out

    ; check Y boundary against options stacked rows
    ; starty + 3 matches the offset location of the first item
    mov ecx, 0                  ; index loop counter
.loop:
    mov edx, START_Y + 3
    add edx, ecx                ; EDX = row for choice[ecx]
    cmp esi, edx
    jne .next
    
    ; check if X is within the length of this specific string choice
    movzx r8d, byte [choice_lens + ecx]
    add r8d, START_X + 2
    cmp edi, r8d
    jg .out                     ; Past text boundary
    
    lea rax, [rcx + 1]          ; Return 1-based choice index
    ret
.next:
    inc ecx
    cmp ecx, N_CHOICES
    jl .loop
.out:
    mov rax, -1
    ret


; --- Subroutine: draw_menu ---
draw_menu:
    ; 1. Draw outer frame box boundary lines
    mov r12d, START_Y
    mov rdi, START_X
    mov rsi, r12d
    call move_cursor
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, box_top_bottom
    mov rdx, box_tb_len
    syscall
    inc r12d

    mov ecx, MENU_HEIGHT - 2
.box_sides:
    push rcx
    mov rdi, START_X
    mov rsi, r12d
    call move_cursor
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, box_side
    mov rdx, box_side_len
    syscall
    inc r12d
    pop rcx
    dec ecx
    jnz .box_sides

    mov rdi, START_X
    mov rsi, r12d
    call move_cursor
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, box_top_bottom
    mov rdx, box_tb_len
    syscall

    ; 2. Print choices strings inside the box frame
    mov r12d, START_Y + 3      ; Starting row for items
    mov r13, 0                  ; Array loop counter index

.print_choices_loop:
    mov rdi, START_X + 2
    mov rsi, r12d
    call move_cursor

    mov rax, r13
    inc rax                     ; convert to 1-based
    cmp rax, [current_hl]       ; check highlight match status
    jne .print_normal

    ; Print highlighted inverse video item
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, attr_reverse
    mov rdx, attr_rev_len
    syscall

    mov rsi, [choices + r13 * 8]
    push rsi
    call get_strlen
    mov rdx, rax
    mov rax, sys_write
    mov rdi, stdout
    pop rsi
    syscall

    mov rax, sys_write
    mov rdi, stdout
    mov rsi, attr_reset
    mov rdx, attr_reset_len
    syscall
    jmp .next_choice

.print_normal:
    mov rsi, [choices + r13 * 8]
    push rsi
    call get_strlen
    mov rdx, rax
    mov rax, sys_write
    mov rdi, stdout
    pop rsi
    syscall

.next_choice:
    inc r12d
    inc r13
    cmp r13, N_CHOICES
    jl .print_choices_loop
    ret


; --- Helper: move_cursor ---
; Inputs: RDI = X, RSI = Y
move_cursor:
    ; Generates string representation: "\033[Y;XH"
    push rdi
    push rsi
    
    mov rdi, fmt_buf
    mov byte [rdi], 0x1B
    mov byte [rdi + 1], '['
    add rdi, 2
    
    pop rax                     ; Pop Y coordinate value
    call int_to_ascii_inline
    
    mov byte [rdi], ';'
    inc rdi
    
    pop rax                     ; Pop X coordinate value
    call int_to_ascii_inline
    
    mov byte [rdi], 'H'
    inc rdi
    
    ; Transmit movement escape block string sequence
    mov rdx, rdi
    sub rdx, fmt_buf            ; calculate total dynamic sequence string length
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, fmt_buf
    syscall
    ret

int_to_ascii_inline:
    ; Quick inline base-10 parsing utility for coordinates conversion
    mov r8, 10
    push 0xFFFF                 ; stack end sentinel token marker
.div:
    xor rdx, rdx
    div r8
    add dl, '0'
    push rdx
    test rax, rax
    jnz .div
.pop_loop:
    pop rdx
    cmp dx, 0xFFFF
    je .done
    mov [rdi], dl
    inc rdi
    jmp .pop_loop
.done:
    ret

clear_row_23:
    mov rdi, 1
    mov rsi, 23
    call move_cursor
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, spaces_clear
    mov rdx, spaces_len
    syscall
    mov rdi, 1
    mov rsi, 23
    call move_cursor
    ret

print_unsigned_int:
    mov rax, rdi
    mov rcx, num_buf
    add rcx, 15
    mov byte [rcx], 0
    mov rdi, 10
.div_l:
    xor rdx, rdx
    div rdi
    add dl, '0'
    dec rcx
    mov [rcx], dl
    test rax, rax
    jnz .div_l
    push rcx
    mov rsi, rcx
    call get_strlen
    mov rdx, rax
    mov rax, sys_write
    mov rdi, stdout
    pop rsi
    syscall
    ret

get_strlen:
    xor rax, rax
.loop:
    cmp byte [rsi + rax], 0
    jz .done
    inc rax
    jmp .loop
.done:
    ret