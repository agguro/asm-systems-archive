; ==============================================================================
; Name:         sudoku_solver.asm
; Description:  A pure x86_64 assembly Sudoku solver using a recursive backtracking 
;               algorithm via direct Linux syscalls (no libc, no c++ streams). 
;               It takes a hardcoded partially filled 9x9 grid, solves it in-place,
;               and prints the initial and completed boards cleanly to stdout.
; Build:        nasm -f elf64 sudoku_solver.asm -o sudoku_solver.o
;               ld sudoku_solver.o -o sudoku_solver
; Usage:        ./sudoku_solver
; ==============================================================================

global _start

; --- Constants & Syscall Numbers ---
sys_write       equ 1
sys_exit        equ 60
stdout          equ 1

DIM             equ 9
BLANK           equ 0

section .data
    msg_header:     db "********************************", 10
                    db "        Sudoku Solver", 10
                    db "********************************", 10, 10
    msg_header_len  equ $ - msg_header

    msg_no_sol:     db "No solution exists for the given Sudoku", 10, 10
    msg_no_sol_len  equ $ - msg_no_sol

    row_divider:    db "-------------------------------------", 10
    row_divider_len equ $ - row_divider

    pipe_char:      db "|"
    space_char:     db " "
    newline_char:   db 10

    ; Initial Sudoku Puzzle Grid (9x9 dword array -> 4 bytes per element)
    grid:
        dd 0, 9, 0, 0, 0, 0, 8, 5, 3
        dd 0, 0, 0, 8, 0, 0, 0, 0, 4
        dd 0, 0, 8, 2, 0, 3, 0, 6, 9
        dd 5, 7, 4, 0, 0, 2, 0, 0, 0
        dd 0, 0, 0, 0, 0, 0, 0, 0, 0
        dd 0, 0, 0, 9, 0, 0, 6, 4, 7
        dd 9, 4, 0, 1, 0, 8, 5, 0, 0
        dd 7, 0, 0, 0, 0, 6, 0, 0, 0
        dd 6, 8, 2, 0, 0, 0, 0, 9, 0

section .bss
    num_char_buf:   resb 2

section .text
_start:
    ; Secure strict 16-byte stack alignment
    mov rbp, rsp
    and rsp, -16

    ; Print Title Header Banner
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, msg_header
    mov rdx, msg_header_len
    syscall

    ; Print Initial Unsolved Grid state
    mov rdi, grid
    call print_grid

    ; Execute Solver engine: solve_sudoku(grid)
    mov rdi, grid
    call solve_sudoku
    
    cmp rax, 1                  ; Check if return code is true (1)
    jne .no_solution

    ; Print Solved Grid state
    mov rdi, grid
    call print_grid
    jmp .exit_success

.no_solution:
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, msg_no_sol
    mov rdx, msg_no_sol_len
    syscall
    mov rdi, 1                  ; Exit code 1
    jmp .exit

.exit_success:
    xor rdi, rdi                ; Exit code 0
.exit:
    mov rax, sys_exit
    syscall


; --- Function: solve_sudoku ---
; Inputs:  RDI = pointer to 9x9 int grid
; Returns: RAX = 1 (true) if solved, 0 (false) if unsolvable
solve_sudoku:
    push rbp
    mov rbp, rsp
    push r12                    ; R12 = row tracking variable
    push r13                    ; R13 = col tracking variable
    push r14                    ; R14 = num index loop counter (1 to 9)
    push rbx                    ; RBX = grid pointer backup
    
    mov rbx, rdi                ; Keep grid address safe in RBX

    ; Check for unassigned location: get_unassigned_location(grid)
    mov rdi, rbx
    call get_unassigned_location
    cmp rax, -1
    je .solved_complete         ; If no blank slots are left, Sudoku is solved!

    mov r12, rax                ; R12 = row
    mov r13, rdx                ; R13 = col
    mov r14, 1                  ; num = 1

.backtrack_loop:
    cmp r14, 10
    jge .fail_backtrack         ; Tried digits 1-9 without success, backtrack!

    ; Verify safety constraints: is_safe(grid, row, col, num)
    mov rdi, rbx                ; grid
    mov rsi, r12                ; row
    mov rdx, r13                ; col
    mov rcx, r14                ; num
    call is_safe
    cmp rax, 1
    jne .next_digit             ; If unsafe, proceed immediately to next number

    ; Make tentative assignment: grid[row][col] = num
    mov rax, r12
    imul rax, 9
    add rax, r13
    mov dword [rbx + rax * 4], r14d

    ; Recurse deeper into tree path: solve_sudoku(grid)
    mov rdi, rbx
    call solve_sudoku
    cmp rax, 1
    je .solved_complete         ; Propagation check success, bubble up true!

    ; Tentative assignment failed, clear slot out: grid[row][col] = BLANK
    mov rax, r12
    imul rax, 9
    add rax, r13
    mov dword [rbx + rax * 4], BLANK

.next_digit:
    inc r14                     ; num++
    jmp .backtrack_loop

.fail_backtrack:
    xor rax, rax                ; Return 0 (false)
    jmp .pop_cleanup

.solved_complete:
    mov rax, 1                  ; Return 1 (true)

.pop_cleanup:
    pop rbx
    pop r14
    pop r13
    pop r12
    pop rbp
    ret


; --- Function: is_safe ---
; Inputs: RDI = grid, RSI = row, RDX = col, RCX = num
; Returns: RAX = 1 (safe), 0 (unsafe)
is_safe:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    push rbx

    mov rbx, rdi                ; RBX = grid
    mov r12, rsi                ; R12 = row
    mov r13, rdx                ; R13 = col
    mov r14, rcx                ; R14 = num

    ; 1. Check Row: used_in_row(grid, row, num)
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r14
    call used_in_row
    cmp rax, 1
    je .unsafe_out

    ; 2. Check Column: used_in_col(grid, col, num)
    mov rdi, rbx
    mov rsi, r13
    mov rdx, r14
    call used_in_col
    cmp rax, 1
    je .unsafe_out

    ; 3. Check Box: used_in_box(grid, box_start_row, box_start_col, num)
    ; box_start_row = row - row % 3
    mov rax, r12
    xor rdx, rdx
    mov r8, 3
    div r8                      ; rax = row / 3, rdx = row % 3
    sub r12, rdx                ; R12 = box_start_row

    ; box_start_col = col - col % 3
    mov rax, r13
    xor rdx, rdx
    div r8                      ; rax = col / 3, rdx = col % 3
    sub r13, rdx                ; R13 = box_start_col

    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    mov rcx, r14
    call used_in_box
    cmp rax, 1
    je .unsafe_out

    mov rax, 1                  ; Safe! Return 1
    jmp .safe_cleanup

.unsafe_out:
    xor rax, rax                ; Unsafe! Return 0

.safe_cleanup:
    pop rbx
    pop r14
    pop r13
    pop r12
    pop rbp
    ret


; --- Function: used_in_row ---
used_in_row:
    xor ecx, ecx                ; col = 0
.loop:
    cmp ecx, DIM
    jge .not_found
    mov rax, rsi                ; row
    imul rax, 9
    add rax, rcx                ; row * 9 + col
    cmp dword [rdi + rax * 4], edx ; grid[row][col] == num?
    je .found
    inc ecx
    jmp .loop
.found:
    mov rax, 1
    ret
.not_found:
    xor rax, rax
    ret


; --- Function: used_in_col ---
used_in_col:
    xor ecx, ecx                ; row = 0
.loop:
    cmp ecx, DIM
    jge .not_found
    mov rax, rcx                ; row
    imul rax, 9
    add rax, rsi                ; row * 9 + col
    cmp dword [rdi + rax * 4], edx ; grid[row][col] == num?
    je .found
    inc ecx
    jmp .loop
.found:
    mov rax, 1
    ret
.not_found:
    xor rax, rax
    ret


; --- Function: used_in_box ---
; Inputs: RDI=grid, RSI=box_start_row, RDX=box_start_col, RCX=num
used_in_box:
    xor r8d, r8d                ; r8 = internal row (0-2)
.row_loop:
    cmp r8d, 3
    jge .not_found
    xor r9d, r9d                ; r9 = internal col (0-2)
.col_loop:
    cmp r9d, 3
    jge .next_row

    mov rax, rsi                ; box_start_row
    add rax, r8                 ; + internal row
    imul rax, 9
    add rax, rdx                ; box_start_col
    add rax, r9                 ; + internal col

    cmp dword [rdi + rax * 4], ecx ; grid element == num?
    je .found
    inc r9d
    jmp .col_loop
.next_row:
    inc r8d
    jmp .row_loop
.found:
    mov rax, 1
    ret
.not_found:
    xor rax, rax
    ret


; --- Function: get_unassigned_location ---
; Returns: RAX = row, RDX = col (or RAX = -1 if full)
get_unassigned_location:
    xor rsi, rsi                ; row = 0
.row_l:
    cmp rsi, DIM
    jge .full
    xor rdx, rdx                ; col = 0
.col_l:
    cmp rdx, DIM
    jge .next_row
    mov rax, rsi
    imul rax, 9
    add rax, rdx
    cmp dword [rdi + rax * 4], BLANK
    je .found                   ; Found a blank! RAX row is setup via calculation chain
    inc rdx
    jmp .col_l
.next_row:
    inc rsi
    jmp .row_l
.found:
    mov rax, rsi                ; RAX = row, RDX = col (already set)
    ret
.full:
    mov rax, -1                 ; Code -1 for full grid conditions
    ret


; --- Function: print_grid ---
; Inputs: RDI = pointer to grid
print_grid:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push rbx
    
    mov rbx, rdi                ; Save grid pointer
    xor r12, r12                ; r12 = row = 0

.row_loop:
    cmp r12, DIM
    jge .done

    ; Print Row Divider Line
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, row_divider
    mov rdx, row_divider_len
    syscall

    ; Print Opening Line Character "|"
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, pipe_char
    mov rdx, 1
    syscall

    xor r13, r13                ; r13 = col = 0
.col_loop:
    cmp r13, DIM
    jge .end_row

    ; Print space
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, space_char
    mov rdx, 1
    syscall

    ; Extract cell element
    mov rax, r12
    imul rax, 9
    add rax, r13
    mov eax, [rbx + rax * 4]

    cmp eax, BLANK
    jne .print_digit

    ; Cell is blank, print empty placeholder space
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, space_char
    mov rdx, 1
    syscall
    jmp .print_delimiter

.print_digit:
    ; Convert raw digit integer to ASCII single character inline
    add al, '0'
    mov [num_char_buf], al
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, num_char_buf
    mov rdx, 1
    syscall

.print_delimiter:
    ; Print trailing spacing space and structural column pipe "| "
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, space_char
    mov rdx, 1
    syscall

    mov rax, sys_write
    mov rdi, stdout
    mov rsi, pipe_char
    mov rdx, 1
    syscall

    inc r13
    jmp .col_loop

.end_row:
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, newline_char
    mov rdx, 1
    syscall

    inc r12
    jmp .row_loop

.done:
    ; Finish grid representation block with final closing line divider
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, row_divider
    mov rdx, row_divider_len
    syscall
    
    mov rax, sys_write
    mov rdi, stdout
    mov rsi, newline_char
    mov rdx, 1
    syscall

    pop rbx
    pop r13
    pop r12
    pop rbp
    ret