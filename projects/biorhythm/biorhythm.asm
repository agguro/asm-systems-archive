# ====================================================================
# Title:        Zero-Libc 64-bit Biorhythm Calculator (GNU as)
# Description:  Calculates Physical, Emotional, and Intellectual 
#               biorhythm percentages for the current day based on an
#               input birthdate (YYYYMMDD) via CLI parameters.
# ====================================================================

.intel_syntax noprefix

.section .rodata
usage_msg:
    .string "Usage: ./biorhythm YYYYMMDD\n"
usage_len = . - usage_msg

err_msg:
    .string "Error: Invalid date format. Use YYYYMMDD.\n"
err_len = . - err_msg

# UI Text Output Labels
txt_header:   .string "--- Biorhythm Status for Today ---\n"
txt_header_len = . - txt_header
lbl_physical: .string "Physical Energy: "
lbl_phys_len   = . - lbl_physical
lbl_emotional:.string "Emotional Mood:  "
lbl_emot_len   = . - lbl_emotional
lbl_intellect:.string "Intellectual:    "
lbl_intel_len  = . - lbl_intellect
pct_sign:     .string "%\n"

# Biorhythm math constants
const_2pi:    .double 6.283185307179586
period_phys:  .double 23.0
period_emot:  .double 28.0
period_intel: .double 33.0
const_100:    .double 100.0

.section .data
.align 8
timeval:
    .quad 0   # tv_sec (seconds since Jan 1, 1970)
    .quad 0   # tv_usec

.section .bss
.lcomm out_buf, 32

.section .text
.global _start

_start:
    # 1. Inspect stack for argc
    mov rax, [rsp]
    cmp rax, 2
    je .parse_args
    
    # Show usage if argc != 2
    mov rdi, 1
    lea rsi, [rip + usage_msg]
    mov rdx, usage_len
    mov rax, 1                 # sys_write
    syscall
    jmp .exit_error

.parse_args:
    # 2. Extract argv[1]
    mov rsi, [rsp + 16]        # Pointer to YYYYMMDD string
    
    # Verify string length is exactly 8 bytes (plus look for null terminator)
    xor rcx, rcx
.len_loop:
    cmp byte ptr [rsi + rcx], 0
    jz .len_checked
    inc rcx
    cmp rcx, 9
    jg .invalid_input
    jmp .len_loop
.len_checked:
    cmp rcx, 8
    jne .invalid_input

    # Parse Year (4 digits)
    xor rbx, rbx
    movzx rax, byte ptr [rsi]
    sub rax, '0'
    imul rax, 1000
    add rbx, rax
    movzx rax, byte ptr [rsi + 1]
    sub rax, '0'
    imul rax, 100
    add rbx, rax
    movzx rax, byte ptr [rsi + 2]
    sub rax, '0'
    imul rax, 10
    add rbx, rax
    movzx rax, byte ptr [rsi + 3]
    sub rax, '0'
    add rbx, rax               # rbx = Year

    # Parse Month (2 digits)
    xor rdx, rdx
    movzx rax, byte ptr [rsi + 4]
    sub rax, '0'
    imul rax, 10
    add rdx, rax
    movzx rax, byte ptr [rsi + 5]
    sub rax, '0'
    add rdx, rax               # rdx = Month

    # Parse Day (2 digits)
    xor rbp, rbp
    movzx rax, byte ptr [rsi + 6]
    sub rax, '0'
    imul rax, 10
    add rbp, rax
    movzx rax, byte ptr [rsi + 7]
    sub rax, '0'
    add rbp, rax               # rbp = Day

    # Validate dynamic raw bounds
    cmp rdx, 12
    ja .invalid_input
    cmp rbp, 31
    ja .invalid_input

    # Compute birthday absolute epoch day count
    mov rdi, rbx
    mov rsi, rdx
    mov rdx, rbp
    call calculate_epoch_days
    mov r14, rax               # r14 = Birthday absolute index

    # 3. Retrieve system date dynamically via kernel
    lea rdi, [rip + timeval]
    xor rsi, rsi               # timezone = NULL
    mov rax, 96                # sys_gettimeofday
    syscall
    
    # Convert Unix timestamp (seconds) in timeval to calendar days
    mov rax, [rip + timeval]   
    mov rdx, 0
    mov rbx, 86400             # Seconds in one standard day
    div rbx                    # rax = days passed since Jan 1, 1970
    
    # Unix Epoch (1970-01-01) index offset modification
    # 1970 years * 365.2425 days is roughly 719468 absolute days since year 0
    add rax, 719468            # rax = Today absolute index
    
    # Calculate delta delta days lived
    sub rax, r14
    js .invalid_input          # If negative, user entered a future birthdate
    mov r15, rax               # r15 = total days lived (integer)

    # Print out UI Header
    mov rdi, 1
    lea rsi, [rip + txt_header]
    mov rdx, txt_header_len
    mov rax, 1
    syscall

    # 4. Math execution block via FPU
    finit                      # Reset hardware FPU state machine

    # --- PHYSICAL WAVE ---
    mov rdi, 1
    lea rsi, [rip + lbl_physical]
    mov rdx, lbl_phys_len
    mov rax, 1
    syscall
    lea rbx, [rip + period_phys]
    call compute_wave
    call print_percentage

    # --- EMOTIONAL WAVE ---
    mov rdi, 1
    lea rsi, [rip + lbl_emotional]
    mov rdx, lbl_emot_len
    mov rax, 1
    syscall
    lea rbx, [rip + period_emot]
    call compute_wave
    call print_percentage

    # --- INTELLECTUAL WAVE ---
    mov rdi, 1
    lea rsi, [rip + lbl_intellect]
    mov rdx, lbl_intel_len
    mov rax, 1
    syscall
    lea rbx, [rip + period_intel]
    call compute_wave
    call print_percentage

    # Success Termination
    mov rdi, 0
    mov rax, 60
    syscall

.invalid_input:
    mov rdi, 2
    lea rsi, [rip + err_msg]
    mov rdx, err_len
    mov rax, 1
    syscall
.exit_error:
    mov rdi, 1
    mov rax, 60
    syscall

# ====================================================================
# Function: compute_wave
# Inputs:   r15 = days lived (int), rbx = pointer to cycle period (double)
# Outputs:  Returns an integer (-100 to 100) inside rax
# ====================================================================
compute_wave:
    push rbp
    mov rbp, rsp
    sub rsp, 8
    mov [rsp], r15
    fild qword ptr [rsp]       # ST(0) = days
    fld qword ptr [rip + const_2pi] # ST(0) = 2*PI, ST(1) = days
    fmulp                      # ST(0) = 2*PI*days
    fld qword ptr [rbx]        # ST(0) = period, ST(1) = 2*PI*days
    fdivp                      # ST(0) = (2*PI*days)/period
    fsin                       # ST(0) = sin(...)
    fld qword ptr [rip + const_100] # ST(0) = 100.0, ST(1) = sin(...)
    fmulp                      # ST(0) = sin(...)*100.0
    fistp qword ptr [rsp]      # Store away as rounded integer
    mov rax, [rsp]
    add rsp, 8
    pop rbp
    ret

# ====================================================================
# Function: calculate_epoch_days
# Inputs:   rdi = year, rsi = month, rdx = day
# Outputs:  rax = absolute day index count since year 0000
# ====================================================================
calculate_epoch_days:
    push rbx
    # Adjust month framework logic: if month <= 2, shift year down 1, add 12 to month
    cmp rsi, 2
    jg .no_adjust
    dec rdi
    add rsi, 12
.no_adjust:
    # Gregorian magic formula: Day + (13*Month + 3)/5 + Year + Year/4 - Year/100 + Year/400
    mov rax, rsi
    imul rax, 13
    add rax, 3
    mov rbx, 5
    xor rdx, rdx
    div rbx                    # rax = (13*Month + 3)/5
    
    mov rbx, [rsp + 8]         # restore rdx input context safely if changed
    add rax, rbp               # Add raw day value
    add rax, rdi               # Add structural year factor
    
    # Add leap variations
    mov rcx, rdi
    shr rcx, 2                 # Year / 4
    add rax, rcx
    
    # Year / 100 tracking
    mov rcx, rdi
    mov rbx, 100
    xor rdx, rdx
    div rbx
    sub rax, rcx               # subtract century anomalies
    
    # Year / 400 tracking
    mov rax, rdi
    mov rbx, 400
    xor rdx, rdx
    div rbx
    add rax, rcx               # rax holds final raw linear day index
    
    pop rbx
    ret

# ====================================================================
# Function: print_percentage
# Inputs:   rax = signed integer coefficient (-100 to 100)
# ====================================================================
print_percentage:
    push rbx
    lea rdi, [rip + out_buf + 24]
    mov byte ptr [rdi], 0      # Null terminator string layout
    
    xor rbx, rbx
    cmp rax, 0
    jge .pos_convert
    neg rax
    mov rbx, 1                 # Register flag for sign tracking

.pos_convert:
    mov rcx, 10
.string_loop:
    xor rdx, rdx
    div rcx
    add dl, '0'
    dec rdi
    mov [rdi], dl
    and rax, rax
    jnz .string_loop

    cmp rbx, 1
    jne .flush_out
    dec rdi
    mov byte ptr [rdi], '-'

.flush_out:
    # Compute active runtime string string offset metrics
    lea rsi, [rip + out_buf + 24]
    sub rsi, rdi
    mov rdx, rsi               # rdx = length
    mov rsi, rdi               # rsi = buffer address
    mov rdi, 1                 # stdout
    mov rax, 1                 # sys_write
    syscall
    
    # Print clean terminal suffix percent notation
    mov rdi, 1
    lea rsi, [rip + pct_sign]
    mov rdx, 2
    mov rax, 1
    syscall

    pop rbx
    ret