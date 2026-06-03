; ====================================================================
; Title:        Mersenne Twister 64-bit PRNG (MT19937-64)
; Build:        nasm -felf64 mt19937_64.asm -o mt19937_64.o
;               ld -s -melf_x86_64 -o mt19937_64 mt19937_64.o
; References:   Takuji Nishimura and Makoto Matsumoto (2004/9/29 C Version)
;               http://www.math.hiroshima-u.ac.jp/~m-mat/MT/emt.html
; ====================================================================

BITS 64
GLOBAL _start

; Algorithm Constants Definitions
%define NN          312
%define MM          156
%define MATRIX_A    0xB5026F5AA96619E9
%define UM          0xFFFFFFFF80000000
%define LM          0x000000007FFFFFFF

section .bss
    align 8
    mt:             resq    NN              ; The internal state vector array
    mti:            resd    1               ; State tracking index (32-bit int)
    ascii_buf:      resb    32              ; Buffer zone for textual formatting

section .data
    align 8
    init_array:     dq      0x12345, 0x23456, 0x34567, 0x45678
    init_len:       dq      4

    txt_title:      db      "1000 outputs of genrand64_int64()", 10
    .len:           equ     $-txt_title
    
    space:          db      " "
    newline:        db      10

section .text

_start:
    ; 1. Initialize the internal PRNG vector engine using the array block
    mov     rdi, init_array
    mov     rsi, [init_len]
    call    init_by_array64

    ; 2. Print out structural presentation title banner string
    mov     rdi, 1                          ; stdout
    mov     rsi, txt_title
    mov     rdx, txt_title.len
    mov     rax, 1                          ; sys_write
    syscall

    ; 3. Core Loop: Generate and display exactly 1000 values
    xor     r12, r12                        ; Loop iterator index i = 0

.generation_loop:
    call    genrand64_int64                 ; Returns 64-bit random number inside rax
    
    ; Save loop metrics before handing control to the console I/O subsystem
    push    rax
    
    ; Convert raw value inside RAX into an aligned ASCII output string
    call    print_uint64
    
    ; Print space padding separator
    mov     rdi, 1
    mov     rsi, space
    mov     rdx, 1
    mov     rax, 1                          ; sys_write
    syscall

    ; Check layout configurations: if (i % 5 == 4) print a newline element
    mov     rax, r12
    xor     rdx, rdx
    mov     rcx, 5
    div     rcx                             ; Remainder drops into RDX
    cmp     rdx, 4
    jne     .skip_newline

    mov     rdi, 1
    mov     rsi, newline
    mov     rdx, 1
    mov     rax, 1                          ; sys_write
    syscall

.skip_newline:
    pop     rax
    inc     r12
    cmp     r12, 1000
    jl      .generation_loop

    ; Extra structural spacer format line
    mov     rdi, 1
    mov     rsi, newline
    mov     rdx, 1
    mov     rax, 1
    syscall

    ; 4. Execution context wrap-up
    mov     rdi, 0                          ; safe zero status return code
    mov     rax, 60                         ; sys_exit
    syscall


; ====================================================================
; Function: init_genrand64
; Input:    rdi = 64-bit unsigned integer seed value
; ====================================================================
init_genrand64:
    mov     qword [mt], rdi                 ; mt[0] = seed
    mov     ecx, 1                          ; mti loop counter tracking
    mov     r8, 6364136223846793005         ; Constant multiplier element

.init_loop:
    mov     rax, qword [mt + rcx*8 - 8]     ; Fetch mt[mti-1]
    mov     rdx, rax
    shr     rdx, 62                         ; mt[mti-1] >> 62
    xor     rax, rdx                        ; (mt[mti-1] ^ (mt[mti-1] >> 62))
    imul    rax, r8                         ; Multiplied by magic constant
    add     rax, rcx                        ; + mti
    mov     qword [mt + rcx*8], rax         ; Store inside mt[mti]
    
    inc     rcx
    cmp     rcx, NN
    jl      .init_loop

    mov     dword [mti], NN                 ; Set global index state flag
    ret


; ====================================================================
; Function: init_by_array64
; Inputs:   rdi = init_key[] array base pointer, rsi = key_length
; ====================================================================
init_by_array64:
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, rdi                        ; r12 = init_key base address
    mov     r13, rsi                        ; r13 = key_length

    ; Run foundational seed setup routine first
    mov     rdi, 19650218
    call    init_genrand64

    mov     r14, 1                          ; i = 1
    xor     r15, r15                        ; j = 0

    ; Set loop index k limits framework: k = (NN > key_length ? NN : key_length)
    mov     rcx, NN
    cmp     rcx, r13
    cmovb   rcx, r13                        ; rcx = Loop limit counter 'k'
    mov     r11, 3935559000370003845        ; Multiplier constant setup

.array_pass_1:
    push    rcx
    mov     rax, qword [mt + r14*8 - 8]     ; mt[i-1]
    mov     rdx, rax
    shr     rdx, 62
    xor     rax, rdx
    imul    rax, r11                        ; (...) * constant
    xor     rax, qword [mt + r14*8]         ; mt[i] ^ (...)
    add     rax, qword [r12 + r15*8]        ; + init_key[j]
    add     rax, r15                        ; + j
    mov     qword [mt + r14*8], rax         ; Save back to mt[i]

    inc     r14                             ; i++
    inc     r15                             ; j++
    
    cmp     r14, NN
    jl      .skip_i_reset_1
    mov     rax, qword [mt + NN*8 - 8]
    mov     qword [mt], rax                 ; mt[0] = mt[NN-1]
    mov     r14, 1                          ; i = 1
.skip_i_reset_1:

    cmp     r15, r13
    jl      .skip_j_reset_1
    xor     r15, r15                        ; j = 0
.skip_j_reset_1:
    pop     rcx
    dec     rcx
    jnz     .array_pass_1

    ; Secondary Non-linear Pass Implementation
    mov     rcx, NN - 1                     ; k = NN - 1
    mov     r11, 2862933555777941757        ; New multiplier constant factor

.array_pass_2:
    push    rcx
    mov     rax, qword [mt + r14*8 - 8]     ; mt[i-1]
    mov     rdx, rax
    shr     rdx, 62
    xor     rax, rdx
    imul    rax, r11
    xor     rax, qword [mt + r14*8]
    sub     rax, r14                        ; - i
    mov     qword [mt + r14*8], rax

    inc     r14                             ; i++
    cmp     r14, NN
    jl      .skip_i_reset_2
    mov     rax, qword [mt + NN*8 - 8]
    mov     qword [mt], rax
    mov     r14, 1
.skip_i_reset_2:
    pop     rcx
    dec     rcx
    jnz     .array_pass_2

    ; Assure that the MSB bit remains locked high to guarantee safe non-zero state matrices
    mov     rax, 1
    shl     rax, 63
    mov     qword [mt], rax

    pop     r15
    pop     r14
    pop     r13
    pop     r12
    ret


; ====================================================================
; Function: genrand64_int64
; Output:   rax = 64-bit pseudo-random unsigned integer value
; ====================================================================
genrand64_int64:
    mov     r8d, dword [mti]
    cmp     r8d, NN
    jae     .twist_required                 ; Trigger generation block if index past limit

.extract_and_temper:
    movzx   r8, r8d
    mov     rax, qword [mt + r8*8]          ; Extract value from vector indices
    inc     r8d
    mov     dword [mti], r8d                ; Save back updated mti step increment
    
    ; Tempered operations sequences matrix pipeline transforms
    mov     rdx, rax
    shr     rdx, 29
    mov     rcx, 0x5555555555555555
    and     rdx, rcx
    xor     rax, rdx

    mov     rdx, rax
    shl     rdx, 17
    mov     rcx, 0x71D67FFFEDA60000
    and     rdx, rcx
    xor     rax, rdx

    mov     rdx, rax
    shl     rdx, 37
    mov     rcx, 0xFFF7EEE000000000
    and     rdx, rcx
    xor     rax, rdx

    mov     rdx, rax
    shr     rdx, 43
    xor     rax, rdx
    ret                                     ; Fully tempered value returned in RAX

.twist_required:
    ; Verify that baseline setups have occurred, otherwise apply default seed fallback
    cmp     r8d, NN + 1
    jne     .run_twist_loop
    mov     rdi, 5489
    call    init_genrand64

.run_twist_loop:
    xor     ecx, ecx                        ; Loop counter variable 'i' = 0
    mov     r9, UM
    mov     r10, LM

.twist_block_1:
    mov     rax, qword [mt + rcx*8]
    and     rax, r9                         ; mt[i] & UM
    mov     rdx, qword [mt + rcx*8 + 8]
    and     rdx, r10                        ; mt[i+1] & LM
    or      rax, rdx                        ; rax = x = (mt[i]&UM)|(mt[i+1]&LM)
    
    mov     rdx, rax
    shr     rdx, 1                          ; x >> 1
    
    ; Process mag01 array mappings inline without conditional branching anomalies
    test    rax, 1
    jz      .no_matrix_a_1
    xor     rdx, MATRIX_A
.no_matrix_a_1:
    xor     rdx, qword [mt + rcx*8 + MM*8]  ; ^ mt[i+MM]
    mov     qword [mt + rcx*8], rdx
    
    inc     rcx
    cmp     rcx, NN - MM
    jl      .twist_block_1

.twist_block_2:
    mov     rax, qword [mt + rcx*8]
    and     rax, r9
    mov     rdx, qword [mt + rcx*8 + 8]
    and     rdx, r10
    or      rax, rdx                        ; x assembled
    
    mov     rdx, rax
    shr     rdx, 1
    test    rax, 1
    jz      .no_matrix_a_2
    xor     rdx, MATRIX_A
.no_matrix_a_2:
    xor     rdx, qword [mt + rcx*8 + (MM-NN)*8] ; ^ mt[i+(MM-NN)]
    mov     qword [mt + rcx*8], rdx
    
    inc     rcx
    cmp     rcx, NN - 1
    jl      .twist_block_2

    ; Final boundary anomalies execution step row wrap up
    mov     rax, qword [mt + (NN-1)*8]
    and     rax, r9
    mov     rdx, qword [mt]
    and     rdx, r10
    or      rax, rdx                        ; Final 'x' value assembled
    
    mov     rdx, rax
    shr     rdx, 1
    test    rax, 1
    jz      .no_matrix_a_final
    xor     rdx, MATRIX_A
.no_matrix_a_final:
    xor     rdx, qword [mt + (MM-1)*8]      ; ^ mt[MM-1]
    mov     qword [mt + (NN-1)*8], rdx

    mov     dword [mti], 0                  ; Reset index matrix reference parameters
    mov     r8d, 0
    jmp     .extract_and_temper


; ====================================================================
; Function: print_uint64
; Input:    rax = 64-bit integer payload value to print to screen
; ====================================================================
print_uint64:
    lea     rdi, [ascii_buf + 31]
    mov     byte [rdi], 0                   ; Inject string line suffix bounds terminator
    mov     rcx, 10                         ; Base 10 division configuration

    ; Explicit loop to implement aligned width output padding metrics
    mov     r11, 20                         ; We enforce a 20-character width space layout

.conversion_loop:
    xor     rdx, rdx
    div     rcx                             ; rax = quotient, rdx = remainder character numeric value
    add     dl, '0'
    dec     rdi
    mov     [rdi], dl
    dec     r11
    test    rax, rax
    jnz     .conversion_loop

    ; Apply character spacing layout padding overrides to clean up formatting
    test    r11, r11
    jz      .flush_buffer
.pad_loop:
    dec     rdi
    mov     byte [rdi], ' '                 ; Pad spaces to align rows cleanly
    dec     r11
    jnz     .pad_loop

.flush_buffer:
    lea     rdx, [ascii_buf + 31]
    sub     rdx, rdi                        ; Calculate visual buffer character length width
    mov     rsi, rdi
    mov     rdi, 1                          ; stdout
    mov     rax, 1                          ; sys_write
    syscall
    ret