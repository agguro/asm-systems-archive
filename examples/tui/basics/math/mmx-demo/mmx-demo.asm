# ====================================================================
# Title:        Visible 64-bit MMX Packed Addition (GNU as)
# Description:  Executes a legacy MMX parallel addition and explicitly
#               converts the raw binary results into human-readable 
#               ASCII integers for terminal display. No libc.
# ====================================================================

.intel_syntax noprefix

.section .rodata
.align 8
val_a:  .word 9, 15, 99, 1234      # 4 distinct packed 16-bit values
val_b:  .word 1,  5,  1,    2      # Values to add to them

txt_header:
    .string "--- MMX Parallel Addition Results ---\n"
txt_header_len = . - txt_header

lane_prefix:
    .string "Lane Output: "
lane_prefix_len = . - lane_prefix

newline:
    .string "\n"

.section .bss
.align 8
.lcomm result_buf, 8               # Buffer for raw MMX output
.lcomm ascii_buf, 16               # Conversion buffer for printing digits

.section .text
.global _start

_start:
    # 1. Print application header
    mov rdi, 1
    lea rsi, [rip + txt_header]
    mov rdx, txt_header_len
    mov rax, 1                  # sys_write
    syscall

    # 2. Process Parallel Math via MMX Hardware
    movq        mm0, [rip + val_a]  # Load first 4 packed values
    movq        mm1, [rip + val_b]  # Load second 4 packed values

    paddw       mm0, mm1            # Add lanes: [9+1, 15+5, 99+1, 1234+2]
                                    # Expected:  [10,   20,   100,  1236]

    movq        [rip + result_buf], mm0 # Drop raw binary registers to RAM
    emms                            # Clear FPU tags immediately

    # 3. Unpack and Convert Each Lane Separately to ASCII
    lea rbx, [rip + result_buf]     # Point to start of array data
    mov rcx, 4                      # Loop counter for 4 lanes

.print_lanes_loop:
    push rcx                        # Save loop counter from syscall shifts
    push rbx                        # Save array position pointer

    # Print "Lane Output: " prefix string
    mov rdi, 1
    lea rsi, [rip + lane_prefix]
    mov rdx, lane_prefix_len
    mov rax, 1
    syscall

    # Fetch current lane value (16-bit unsigned integer)
    mov rbx, [rsp]                  # Get array pointer back from stack temporarily
    movzx rax, word ptr [rbx]       # Load exactly 1 word into rax
    
    # Convert rax register integer to ASCII characters
    call integer_to_ascii           # Returns buffer address in rsi, length in rdx

    # Print the numeric digits string to stdout
    mov rdi, 1                      # rsi and rdx are already filled by the function
    mov rax, 1                      # sys_write
    syscall

    # Print clean trailing newline character
    mov rdi, 1
    lea rsi, [rip + newline]
    mov rdx, 1
    mov rax, 1
    syscall

    pop rbx                         # Restore array address context
    pop rcx                         # Restore current loop cycle limit
    add rbx, 2                      # Advance array index forward by 16 bits (1 word)
    loop .print_lanes_loop

    # 4. Safe Kernel Native Termination Exit
    mov rdi, 0
    mov rax, 60                     # sys_exit
    syscall

# ====================================================================
# Function: integer_to_ascii
# Inputs:   rax = raw positive binary integer to process
# Outputs:  rsi = pointer to parsed character string inside ascii_buf
#           rdx = string byte count length
# ====================================================================
integer_to_ascii:
    lea rsi, [rip + ascii_buf + 15] # Target end of workspace buffer
    mov byte ptr [rsi], 0           # String terminator placeholder
    mov rcx, 10                     # Divide by base 10 framework
    xor rdx, rdx                    # Length counter tracking resets

.convert_loop:
    xor rdx, rdx                    # Clear rdx upper register sector before idiv
    div rcx                         # rax = quotient, rdx = remainder
    add dl, '0'                     # Map single digit integer value to ASCII byte
    dec rsi                         # Recede pointer backward
    mov [rsi], dl                   # Drop character down to RAM space
    inc qword ptr [rsp - 8]         # Quick dynamic scratchpad length tracker variable updates
    and rax, rax                    # Is quotient zero?
    jnz .convert_loop

    # Calculate final functional string offset block dimensions
    lea rdx, [rip + ascii_buf + 15]
    sub rdx, rsi                    # Total character width length goes into rdx
    ret
    