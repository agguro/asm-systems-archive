; ==============================================================================
; Name:         gpm_roi_windows.asm
; Description:  A pure x86_64 assembly GPM client managing 4 split-screen windows 
;               using manual Region of Interest (ROI) tracking and raw ANSI 
;               sequences (no ncurses, no libgpm, no libc). It intercepts mouse 
;               movement, button ups, and downs, routing notifications to quadrants.
; Build:        nasm -f elf64 gpm_roi_windows.asm -o gpm_roi_windows.o
;               ld gpm_roi_windows.o -o gpm_roi_windows
; Usage:        sudo ./gpm_roi_windows  (Press CTRL+D to exit cleanly)
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

; --- GPM & Event Mask Codes ---
gpm_connect_sz  equ 16
gpm_event_sz    equ 26

GPM_MOVE        equ 0x0001
GPM_DOWN        equ 0x0002
GPM_UP          equ 0x0004

GPM_B_LEFT      equ 4
GPM_B_MIDDLE    equ 2
GPM_B_RIGHT     equ 1

CTRLD           equ 4

; --- Manual Grid Math Constraints (Based on typical 80x24 TTY footprint) ---
WIN_LINES       equ 10
WIN_COLS        equ 38

section .data
    sockaddr_un:
        dw AF_UNIX
        db "/dev/gpmctl", 0
    sockaddr_un_sz equ 13

    ; Layout Definition Array for our 4 Quadrant Windows
    ; struct WIN { int nlines; int ncols; int y; int x; } -> 16 bytes each
    windows_grid:
        dd WIN_LINES, WIN_COLS, 1,  1       ; Window 0: Top-Left
        dd WIN_LINES, WIN_COLS, 12, 1       ; Window 1: Bottom-Left
        dd WIN_LINES, WIN_COLS, 1,  40      ; Window 2: Top-Right
        dd WIN_LINES, WIN_COLS, 12, 40      ; Window 3: Bottom-Right

    ; ANSI Graphics Sequence Packs
    cls:            db 0x1B, "[2J", 0x1B, "[H"
    cls_len         equ $ - cls
    hide_cursor:    db 0x1B, "[?25l"
    hide_cursor_len equ $ - hide_cursor
    show_cursor:    db 0x1B, "[?25h"
    show_cursor_len equ $ - show_cursor

    ; Status Display Strings
    txt_entered:    db "Entered              ", 0
    txt_leaving:    db "Leaving              ", 0
    txt_btn_down:   db "Mouse button down    ", 0
    txt_btn_up:     db "Mouse button up      ", 0
    txt_b_left:     db "Left Button clicked  ", 0
    txt_b_middle:   db "Middle Button clicked", 0
    txt_b_right:    db "Right Button clicked ", 0
    txt_clear_ln:   db "                     ", 0

    msg_err_gpm:    db "Cannot connect to mouse server", 10
    msg_err_gpm_len equ $ - msg_err_gpm

section .bss
    gpm_fd:         resq 1
    poll_fds:       resb 16
    gpm_conn:       resb gpm_connect_sz
    gpm_event:      resb gpm_event_sz
    stdin_char:     resb 1
    
    active_win:     resq 1      ; Tracking scalar variable index (-1 to 3)
    fmt_buf:        resb 32

section .text
_start:
    mov rbp, rsp
    and rsp, -16

    ; 1. Clear terminal display layout canvas
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

    ; 2. Bridge connection onto Unix local /dev/gpmctl target interface
    mov rax, sys_socket
    mov rdi, AF_UNIX
    mov rsi, SOCK_STREAM
    xor rdx, rdx
    syscall
    test rax, rax
    js .err_out
    mov [gpm_fd], rax

    mov rax, sys_connect
    mov rdi, [gpm_fd]
    mov rsi, sockaddr_un
    mov rdx, sockaddr_un_sz
    syscall
    test rax, rax
    js .err_out

    ; 3. Standardize structure configurations options properties block mapping
    mov rdi, gpm_conn
    mov word [rdi], 0xFFFF
    mov word [rdi + 2], 0x0000
    mov word [rdi + 4], 0x0000
    mov word [rdi + 6], 0xFFFF
    mov rax, 39                 ; sys_getpid
    syscall
    mov [gpm_conn + 8], eax
    mov dword [gpm_conn + 12], 0

    mov rax, sys_write
    mov rdi, [gpm_fd]
    mov rsi, gpm_conn
    mov rdx, gpm_connect_sz
    syscall
    test rax, rax
    js .err_out

    ; Draw all four quad boundaries initial layouts frames
    call draw_all_windows
    mov qword [active_win], -1  ; Initialize out of active bounds

    ; 4. Multiplex multiplex streams inputs loops arrays configurations
    mov dword [poll_fds], stdin
    mov word [poll_fds + 4], POLLIN
    mov rax, [gpm_fd]
    mov dword [poll_fds + 8], eax
    mov word [poll_fds + 12], POLLIN

.poll_loop:
    mov rax, sys_poll
    mov rdi, poll_fds
    mov rsi, 2
    mov rdx, -1
    syscall
    test rax, rax
    js .clean_shutdown

    ; Check stdin stream for potential breakdown interruption key signals escape combos
    mov ax, [poll_fds + 6]
    test ax, POLLIN
    jz .read_mouse_stream
    
    mov rax, sys_read
    mov rdi, stdin
    mov rsi, stdin_char
    mov rdx, 1
    syscall
    test rax, rax
    jle .clean_shutdown
    
    cmp byte [stdin_char], CTRLD
    je .clean_shutdown

.read_mouse_stream:
    mov ax, [poll_fds + 14]
    test ax, POLLIN
    jz .poll_loop

    mov rax, sys_read
    mov rdi, [gpm_fd]
    mov rsi, gpm_event
    mov rdx, gpm_event_sz
    syscall
    test rax, rax
    jle .poll_loop

    ; 5. Coordinate evaluation map layer calculation sequence routing matrix logic
    movzx edi, word [gpm_event + 8]  ; event->x
    movzx esi, word [gpm_event + 10] ; event->y
    call find_window_by_coords       ; Returns RAX = Window ID (0-3), or -1
    mov r12, rax                     ; R12 = target win evaluated index

    ; Process dynamic simulated Enter/Leave transitions events
    mov r13, [active_win]
    cmp r12, r13
    je .process_action_events        ; No layout sector change detected, move to clicks

    ; Mouse shifted bounds sector
    cmp r13, -1
    je .print_new_enter
    
    ; Left old zone context: Print "Leaving" inside old target active context
    push r12
    mov rdi, r13
    mov rsi, 1
    mov rdx, 1
    lea rcx, [txt_leaving]
    call print_in_window
    pop r12

.print_new_enter:
    cmp r12, -1
    je .update_active_cache
    
    ; Entered new zone context: Print "Entered" inside current active context
    push r12
    mov rdi, r12
    mov rsi, 1
    mov rdx, 1
    lea rcx, [txt_entered]
    call print_in_window
    pop r12

.update_active_cache:
    mov [active_win], r12

.process_action_events:
    cmp r12, -1
    je .poll_loop                   ; Outside any box boundary, skip text writing

    mov eax, [gpm_event + 12]       ; event->type
    
    ; Evaluate Down Click: event->type & GPM_DOWN
    test eax, GPM_DOWN
    jz .check_up_event
    
    mov rdi, r12
    mov rsi, WIN_LINES - 2
    mov rdx, 1
    lea rcx, [txt_btn_down]
    call print_in_window
    call handle_button_subtext
    jmp .poll_loop

.check_up_event:
    ; Evaluate Release Unclick: event->type & GPM_UP
    test eax, GPM_UP
    jz .poll_loop
    
    mov rdi, r12
    mov rsi, WIN_LINES - 2
    mov rdx, 1
    lea rcx, [txt_btn_up]
    call print_in_window
    call handle_button_subtext
    jmp .poll_loop

.clean_shutdown:
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

.err_out:
    mov rax, sys_write
    mov rdi, stderr
    mov rsi, msg_err_gpm
    mov rdx, msg_err_gpm_len
    syscall
    mov rdi, 1
    mov rax, sys_exit
    syscall


; --- Subroutine: find_window_by_coords ---
; Inputs:  EDI = X, ESI = Y
; Returns: RAX = Window Index (0-3), or -1 if out of grid bounds
find_window_by_coords:
    xor ecx, ecx
.loop:
    mov r8, rcx
    shl r8, 4                       ; Index scaling offset layout width (16 bytes per entry)
    lea r9, [windows_grid + r8]
    
    mov eax, [r9 + 12]              ; EAX = win.x
    cmp edi, eax
    jl .next
    add eax, [r9 + 4]               ; EAX = win.x + win.ncols
    cmp edi, eax
    jge .next
    
    mov eax, [r9 + 8]               ; EAX = win.y
    cmp esi, eax
    jl .next
    add eax, [r9]                   ; EAX = win.y + win.nlines
    cmp esi, eax
    jge .next
    
    mov rax, rcx                    ; Found bounding slot match index
    ret
.next:
    inc ecx
    cmp ecx, 4
    jl .loop
    mov rax, -1
    ret


; --- Subroutine: handle_button_subtext ---
; Inputs:  R12 = Window ID (0-3)
handle_button_subtext:
    movzx eax, byte [gpm_event + 0] ; event->buttons
    mov rsi, WIN_LINES / 2          ; Target vertical center split line offset row
    
    test al, GPM_B_LEFT
    jz .mid
    mov rdi, r12
    mov rdx, 1
    lea rcx, [txt_b_left]
    jmp print_in_window
.mid:
    test al, GPM_B_MIDDLE
    jz .right
    mov rdi, r12
    mov rdx, 1
    lea rcx, [txt_b_middle]
    jmp print_in_window
.right:
    test al, GPM_B_RIGHT
    jz .clear
    mov rdi, r12
    mov rdx, 1
    lea rcx, [txt_b_right]
    jmp print_in_window
.clear:
    mov rdi, r12
    mov rdx, 1
    lea rcx, [txt_clear_ln]
    jmp print_in_window


; --- Subroutine: print_in_window ---
; Description: Renders text relative to window offsets
; Inputs:      RDI = Win ID (0-3), RSI = Rel Y, RDX = Rel X, RCX = String pointer
print_in_window:
    push rcx
    shl rdi, 4
    lea r8, [windows_grid + rdi]
    mov eax, [r8 + 8]               ; win.y
    add rsi, rax                    ; Absolute Y coordinate
    mov eax, [r8 + 12]              ; win.x
    add rdx, rax                    ; Absolute X coordinate
    
    mov rdi, rdx
    call move_cursor
    
    pop rsi                         ; Restore string pointer location target to RSI
    push rsi
    call get_strlen
    mov rdx, rax
    mov rax, sys_write
    mov rdi, stdout
    pop rsi
    syscall
    ret


; --- Subroutine: draw_all_windows ---
draw_all_windows:
    xor r14, r14                    ; Loop index tracking counter
.loop:
    mov r8, r14
    shl r8, 4
    lea r15, [windows_grid + r8]
    
    ; Draw Top Horizon Line
    mov dword [fmt_buf], 0          ; reset buffer string space lengths counter
    mov rdi, [r15 + 12]             ; win.x
    mov rsi, [r15 + 8]              ; win.y
    call move_cursor
    call draw_horizontal_edge

    ; Draw Vertical Side Walls
    mov r13d, [r15 + 8]             ; Start Y
    inc r13d
    mov ecx, [r15]                  ; nlines
    sub ecx, 2                      ; subtract borders footprints
.sides:
    push rcx
    mov rdi, [r15 + 12]
    mov rsi, r13
    call move_cursor
    mov rax, sys_write
    mov rdi, stdout
    lea rsi, [txt_clear_ln]         ; use clean row sequence as blank filler spacing bars
    mov byte [rsi], '|'
    mov r8d, [r15 + 4]              ; win.ncols
    dec r8d
    mov byte [rsi + r8], '|'        ; Cap trailing layout boundary token character element
    mov dword rdx, [r15 + 4]
    syscall
    mov byte [rsi], ' '             ; restore to space char
    mov byte [rsi + r8], ' '
    inc r13
    pop rcx
    dec ecx
    jnz .sides

    ; Draw Bottom Horizon Line
    mov rdi, [r15 + 12]             ; win.x
    mov rsi, [r15 + 8]              ; win.y
    add rsi, [r15]                  ; + nlines
    dec rsi
    call move_cursor
    call draw_horizontal_edge

    inc r14
    cmp r14, 4
    jl .loop
    ret

draw_horizontal_edge:
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, fmt_buf
    mov byte [rsi], '+'             ; Edge junction character layout anchor
    mov ecx, [r15 + 4]              ; ncols
    sub ecx, 2
    mov rdx, 1
.fill:
    mov byte [rsi + rdx], '-'
    inc rdx
    dec ecx
    jnz .fill
    mov byte [rsi + rdx], '+'
    inc rdx                         ; Account total frame sizing boundaries width string length
    syscall
    ret


; --- Helper: move_cursor ---
move_cursor:
    push rdi
    push rsi
    mov rdi, fmt_buf
    mov byte [rdi], 0x1B
    mov byte [rdi + 1], '['
    add rdi, 2
    pop rax
    call int_to_ascii_inline
    mov byte [rdi], ';'
    inc rdi
    pop rax
    call int_to_ascii_inline
    mov byte [rdi], 'H'
    inc rdi
    mov rdx, rdi
    sub rdx, fmt_buf
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, fmt_buf
    syscall
    ret

int_to_ascii_inline:
    mov r8, 10
    push 0xFFFF
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
    jmp .loop
.done:
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