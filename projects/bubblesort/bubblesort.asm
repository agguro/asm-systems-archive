;name:        bubblesort_demo.asm
;description: Demonstration of 3 BubbleSort Algorithms in one single run to compare
;             iterations and swaps.
;
;build:       nasm -felf64 bubblesort_demo.asm -o bubblesort_demo.o
;             ld -s -melf_x86_64 -o bubblesort_demo bubblesort_demo.o

bits 64

[list -]
    %include "unistd.inc"
[list +]

%define TRUE      1
%define FALSE     0

%macro STRING 1
    .start:     db %1
    .length:    equ $-.start
%endmacro

%macro ARRAY 1-*
    %rep  %0
         dq  %1
         %rotate 1
    %endrep 
%endmacro

section .bss
Buffer:
    sign           resb      1              ; ascii sign
    decimal        resb     19              ; 20 bytes to store a 64 bits number + sign

; Een werkbuffer om de array in te kopiëren voor elke sortering
work_array:        resq     30

section .data

    datasize:      equ       8   
    ; De originele ongesorteerde array (wurst case)
    orig_array:    ARRAY     154,2144,119,98,4,520,2, 75, 15, 0, -85,-4, -78,-54, -485,-458,-25, -92,-233,720,368,547,758,8, -233,72,-36,854,-775,807
    .length        equ       ($-orig_array)/datasize

    title:         STRING    {"Bubblesort Algorithm Comparison - Agguro 2012 / Demo 2026",10,"==========================================================",10}

    opt0_str:      STRING    {10,"--- [RUN 1] Optimization step: no optimization ---",10}
    opt1_str:      STRING    {10,"--- [RUN 2] Optimization step: n-th pass finds the n-th largest ---",10}
    opt2_str:      STRING    {10,"--- [RUN 3] Optimization step: no check after last swap ---",10}

    unsorted:      STRING    {"The UNSORTED array:",10,"-------------------",10}
    sorted:        STRING    {10,"The SORTED array:",10,"-----------------",10}
    iterations:    STRING    {10,"Number of iterations: "}
    swaps:         STRING    {"Number of swaps     : "}
    lf:            STRING    {10}
     
section .text
    global _start
     
_start:
    ; Toon algemene titel
    mov        rsi, title
    mov        rdx, title.length
    call       Print.string

    ; ==========================================
    ; RUN 1: No Optimization
    ; ==========================================
    mov        rsi, opt0_str
    mov        rdx, opt0_str.length
    call       Print.string
    
    call       ResetWorkArray
    
    mov        rsi, unsorted
    mov        rdx, unsorted.length
    call       Print.string
    call       ShowArray
    
    call       BubbleSort0
    call       PrintResults

    ; ==========================================
    ; RUN 2: n-th pass finds n-th largest
    ; ==========================================
    mov        rsi, opt1_str
    mov        rdx, opt1_str.length
    call       Print.string
    
    call       ResetWorkArray
    
    mov        rsi, unsorted
    mov        rdx, unsorted.length
    call       Print.string
    call       ShowArray
    
    call       BubbleSort1
    call       PrintResults

    ; ==========================================
    ; RUN 3: No check after last swap
    ; ==========================================
    mov        rsi, opt2_str
    mov        rdx, opt2_str.length
    call       Print.string
    
    call       ResetWorkArray
    
    mov        rsi, unsorted
    mov        rdx, unsorted.length
    call       Print.string
    call       ShowArray
    
    call       BubbleSort2
    call       PrintResults

Exit:      
    syscall   exit, 0

; ==========================================
; ALGORITME SUBROUTINES
; ==========================================

; --- VARIANT 0: Geen optimalisatie ---
BubbleSort0:
    push       rbx
    push       rcx
    push       rdx
    push       rsi
    xor        r8,r8                         ; number of iterations
    xor        r9,r9                         ; number of swaps
.repeat:      
    mov        rdx, FALSE                    ; isSwapped = false
    mov        rcx,1                         ; i = 1
    mov        rsi,work_array                ; point to start of the array      
.for:
    lodsq                                    ; RBX = array[i]
    mov        rbx, rax
    lodsq                                    ; RAX = array[i+1]
    cmp        rax, rbx                      ; if array[i+1] >= array[i]
    jge        .next
    xor        rax, rbx                      ; if less then swap both values            
    xor        rbx, rax
    xor        rax, rbx
    mov        qword [rsi-datasize*2], rbx   ; and store swapped values in array
    mov        qword [rsi-datasize], rax
    mov        rdx,TRUE                      ; isSwapped = true
    inc        r9                            ; increment number of swaps
.next:
    inc        r8                            ; increment number of iterations
    sub        rsi,datasize                  ; adjust pointer in array      
    inc        rcx                           ; i++
    cmp        rcx,orig_array.length-1       ; if i <= arrayLength-1
    jle        .for                          ; next comparison
.until:
    cmp        rdx,TRUE                      ; if isSwapped == true
    je         .repeat                       ; then repeat sort algorithm
    pop        rsi
    pop        rdx
    pop        rcx
    pop        rbx
    ret

; --- VARIANT 1: n-de pass vindt n-de grootste ---
BubbleSort1:
    push       rbx
    push       rcx
    push       rdx
    push       rsi
    push       r10
    xor        r8,r8                         ; number of iterations
    xor        r9,r9                         ; number of swaps
    mov        r10, orig_array.length        
.repeat:      
    mov        rdx, FALSE                    ; isSwapped = false
    mov        rcx,1                         ; i = 1
    mov        rsi,work_array                ; point to start of the array      
.for:
    lodsq                                    ; RBX = array[i]
    mov        rbx, rax
    lodsq                                    ; RAX = array[i+1]
    cmp        rax, rbx                      ; if array[i+1] >= array[i]
    jge        .next
    xor        rax, rbx                      ; then swap both values            
    xor        rbx, rax
    xor        rax, rbx
    mov        qword [rsi-datasize*2], rbx   ; and store swapped values in array
    mov        qword [rsi-datasize], rax
    mov        rdx,TRUE                      ; isSwapped = true
    inc        r9                            ; increment number of swaps
.next:
    inc        r8                            ; increment number of iterations
    sub        rsi,datasize                  ; adjust pointer in array     
    inc        rcx                           ; i++
    cmp        rcx,r10                       ; if i <= arrayLength-1
    jle        .for                          ; next comparison
.until:
    dec        r10                           
    cmp        rdx,TRUE                      ; if isSwapped == true
    je         .repeat                       ; then repeat sort algorithm
    pop        r10
    pop        rsi
    pop        rdx
    pop        rcx
    pop        rbx
    ret

; --- VARIANT 2: Geen controle na laatste swap ---
BubbleSort2:
    push       rbx
    push       rcx
    push       rdx
    push       rsi
    push       r10
    push       r11
    xor        r8,r8                         ; number of iterations
    xor        r9,r9                         ; number of swaps
    mov        r10, orig_array.length        ; r10 = n = arrayLength
.repeat:
    mov        r11, 0                        ; r11 = newn = 0
    mov        rcx,1                         ; i = 1
    mov        rsi,work_array                ; point to start of the array      
.for:
    lodsq                                    ; RBX = array[i]
    mov        rbx, rax
    lodsq                                    ; RAX = array[i+1]
    cmp        rax, rbx                      ; if array[i+1] >= array[i]
    jge        .next
    xor        rax, rbx                      ; then swap both values            
    xor        rbx, rax
    xor        rax, rbx
    mov        r11, rcx                      ; newn = i
    mov        qword [rsi-datasize*2], rbx   ; and store swapped values in array
    mov        qword [rsi-datasize], rax
    inc        r9                            ; increment number of swaps
.next:
    inc        r8                            ; increment number of iterations
    sub        rsi,datasize                  ; adjust pointer in array
    inc        rcx                           ; i++
    cmp        rcx, r10                      ; if i <= arrayLength-1
    jle        .for
    mov        r10, r11                      ; n = newn
.until:
    dec        r10
    cmp        r10, 0                        ; if r10 > 0
    jg         .repeat                       ; then repeat sort algorithm
    pop        r11
    pop        r10
    pop        rsi
    pop        rdx
    pop        rcx
    pop        rbx
    ret

; ==========================================
; HULPFUNCTIES
; ==========================================

; Kopieert de originele array naar de werk-array
ResetWorkArray:
    push       rcx
    push       rsi
    push       rdi
    mov        rcx, orig_array.length
    mov        rsi, orig_array
    mov        rdi, work_array
    cld
    rep movsq
    pop        rdi
    pop        rsi
    pop        rcx
    ret

; Print de resultaten van een run (gesorteerde array + stats)
PrintResults:
    push       rax
    push       rdx
    push       rsi
    
    mov        rsi, sorted
    mov        rdx, sorted.length
    call       Print.string
    call       ShowArray
    
    ; toon aantal iteraties (staat in R8)
    mov        rsi, iterations
    mov        rdx, iterations.length
    call       Print.string
    mov        rax, r8                       
    call       Convert                       
    call       Print.integer
    call       ClearBuffer                   
    
    ; toon aantal swaps (staat in R9)
    mov        rsi, swaps
    mov        rdx, swaps.length
    call       Print.string
    mov        rax, r9                       
    call       Convert                       
    call       Print.integer
    call       Print.linefeed
    
    pop        rsi
    pop        rdx
    pop        rax
    ret

ShowArray:
    push       rcx
    push       rsi
    mov        rcx, orig_array.length        ; show all integers
    mov        rsi, work_array               ; start of the work array
.nextInteger:      
    lodsq                                    ; get integer
    call       Convert                       ; RAX contains the number to convert
    call       Print.integer
    call       ClearBuffer                   ; clear buffer for next use
    loop       .nextInteger
    pop        rsi
    pop        rcx
    ret

Convert:
    push       rax
    push       rbx
    push       rdx
    push       rdi
    push       rcx
    mov        rdi,sign
    mov        byte[rdi]," "                 ; default no sign
    cmp        rax, 0
    jge        .noSign
    mov        byte[rdi],"-"                 ; number is negative
    neg        rax                           ; make positive
.noSign:
    mov        rdi, decimal                  ; address of buffer in RDI 
    add        rdi, 18                       ; 0..18 = 19 bytes of storage
.repeat:      
    xor        rdx, rdx                      ; remainder will be in RDX
    mov        rbx, 10
    div        rbx                           ; RDX = remainder of division
    or         dl,"0"                        ; make remainder decimal ASCII
    mov        byte[rdi],dl                  ; and store
    dec        rdi                           ; go to previous position
    cmp        rax, 0                        ; RAX = quotient of division, if zero stop
    jnz        .repeat
    
    mov        dl ,byte[sign]                ; copy sign character in [RDI] just before the number
    mov        byte[rdi], dl
    dec        rdi                           ; point to position before the sign character
    mov        rcx, rdi                      ; calculate remaining bytes
    sub        rcx, sign
    cmp        rcx, 0
    jle        .end
    inc        rcx
    mov        al," "                        ; fill remaining bytes with spaces
    std
.fill:      
    stosb
    loop       .fill
.end:      
    pop        rcx
    pop        rdi
    pop        rdx
    pop        rbx
    pop        rax
    ret
     
ClearBuffer:
    push       rax
    push       rcx
    push       rdi
    mov        rdi, Buffer
    mov        rcx, 20                       ; 20 bytes to clear
    xor        rax, rax
    cld                                      ; begin at lowest address
.repeat:      
    stosb                                    ; erase [RDI]
    loop       .repeat
    pop        rdi
    pop        rcx
    pop        rax
    ret

Print:
.integer:
    push       rdx
    push       rsi
    mov        rsi,Buffer
    mov        rdx, 20                       ; 20 bytes to display
    call       Print.string
    call       Print.linefeed
    pop        rsi
    pop        rdx
    ret
.linefeed:
    mov        rsi, lf
    mov        rdx, lf.length
.string:  
    push       rax
    push       rdi
    push       rcx                           ; RCX is changed after syscall
    syscall    write, stdout
    pop        rcx
    pop        rdi
    pop        rax
    ret
