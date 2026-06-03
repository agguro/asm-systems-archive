; ====================================================================
; Title:        64-bit CGI Raw POST Hex/Char Dump Engine (NASM)
; Build:        nasm -felf64 hexdump.asm -o hexdump.o
;               ld -s -melf_x86_64 -o hexdump hexdump.o
; Description:  Captures incoming raw POST payload data and outputs
;               a clean, side-by-side HTML character and hex grid.
; ====================================================================

BITS 64

%define MAX_FILESIZE    1024*1024       ; Strict 1 MB ceiling limit
%define COLUMNS         32              ; 32 bytes wide per row line

section .bss
    oldbrkaddr:    resq    1
    contentsize:   resq    1

section .data
    requestmethod: db      'REQUEST_METHOD=POST'
    .length:       equ     $-requestmethod

    contentlength: db      'CONTENT_LENGTH='
    .length:       equ     $-contentlength

    top:           db      'Content-type: text/html', 0x0A, 0x0A
                   db      '<!DOCTYPE html><html><head>'
                   db      '<title>Show RAW POST DATA</title>'
                   db      '</head><body>'
                   db      '<pre><div id="chars" style="float:left;margin-right:100px;">'
    .length:       equ     $-top

    middle:        db      '</div><div id="hex" style="float:left; border-left: 1px solid #ccc;padding-left: 10px;">'
    .length:       equ     $-middle

    bottom:        db      '</div></pre></body></html>'
    .length:       equ     $-bottom

    break_tag:     db      '<br />'
    .length:       equ     $-break_tag

    sizelimited:   db      'Content-type: text/html', 0x0A, 0x0A
                   db      'This file is too long, sorry.'
    .length:       equ     $-sizelimited

    ; Templates for formatting data out to stdout
    align 2
    charbuffer:    db      '&#x'
    .value:        dw      0
    .length:       equ     $-charbuffer

    hexbuffer:     db      ' '
    .value:        dw      0
    .length:       equ     $-hexbuffer

section .text
     global _start

_start:
    ; 1. Inspect environment stack vectors to find REQUEST_METHOD=POST
    pop       rax                             ; Pop argc
    pop       rax                             ; Pop argv[0]
    push      rsp                             ; Preserve base environment stack reference
    pop       r9                              
    cld

searchpostvar:
    pop       rsi
    or        rsi, rsi                        ; Hit the end of environment space?
    jz        Exit                            ; If null terminator hit -> exit directly
    
    mov       rdi, requestmethod
    mov       rcx, requestmethod.length
    rep       cmpsb
    jne       searchpostvar                   ; Mis-match -> evaluate next entry item

    ; 2. Match found! Reset stack layout metrics to look for CONTENT_LENGTH
    mov       rsp, r9                         

find_len_loop:
    pop       rsi
    or        rsi, rsi                        ; End of environment reached?
    jz        Exit                            
    
    mov       rdi, contentlength
    mov       rcx, contentlength.length
    rep       cmpsb
    jne       find_len_loop                   ; Try next environment string element

    ; 3. CONTENT_LENGTH found. Convert ASCII numbers string to pure raw binary index
    xor       rcx, rcx
    xor       rax, rax

readdigit:
    lodsb
    and       al, al                          ; String null terminator check
    jz        endofdigits
    and       al, 0x0F                        ; Un-ascii conversion filter
    xor       rdx, rdx
    mov       rbx, 10
    imul      rcx, rbx
    add       rcx, rax                        ; total = (total * 10) + current digit
    jmp       readdigit

endofdigits:
    cmp       rcx, MAX_FILESIZE               ; Is payload size safe?
    jg        SizeLimited
    mov       qword[contentsize], rcx         ; Save off verified integer count

    ; 4. Dynamic heap space allocation via sys_brk syscall profiles
    mov       rdi, 0
    mov       rax, 12                         ; sys_brk (query base execution line offset)
    syscall   
    mov       qword[oldbrkaddr], rax          ; Save current base index
    
    add       rax, qword[contentsize]         ; Calculate target heap expansion break boundary          
    mov       rdi, rax
    mov       rax, 12                         ; sys_brk (allocate requested space bump)
    syscall   
    
    cmp       rax, rdi
    jne       Exit                            ; OOM or address fault error -> safe exit

    ; 5. Pull raw data packets cleanly straight from stdin stream channels
    mov       rdi, 0                          ; stdin
    mov       rsi, qword[oldbrkaddr]          ; target buffer address
    mov       rdx, qword[contentsize]         ; buffer size capacity metric
    mov       rax, 0                          ; sys_read
    syscall   

    ; Print HTML structural layout header data out
    mov       rdi, 1                          ; stdout
    mov       rsi, top
    mov       rdx, top.length
    mov       rax, 1                          ; sys_write
    syscall   
          
    ; 6. Double-Pass Matrix Grid Processing Blocks
    mov       r10, 0                          ; Flag: 0 = Print Clean Readable Characters
    call      ConvertBuffer
     
    ; Close characters container panel, open right hexadecimal container panel
    mov       rdi, 1
    mov       rsi, middle
    mov       rdx, middle.length
    mov       rax, 1                          ; sys_write
    syscall   
     
    mov       r10, 1                          ; Flag: 1 = Print Clean Hex Bytes Format Streams
    call      ConvertBuffer
     
    ; Output final closing HTML structures suffix tags elements
    mov       rdi, 1                          ; stdout
    mov       rsi, bottom
    mov       rdx, bottom.length
    mov       rax, 1                          ; sys_write
    syscall   
     
    ; Reset program breaks down to baseline values to drop allocated memory
    mov       rdi, qword[oldbrkaddr]
    mov       rax, 12                         ; sys_brk
    syscall   
    jmp       Exit
    
SizeLimited:
    mov       rdi, 1
    mov       rsi, sizelimited
    mov       rdx, sizelimited.length
    mov       rax, 1                          ; sys_write
    syscall   

Exit:    
    mov       rdi, 0
    mov       rax, 60                         ; sys_exit
    syscall   
     
; ====================================================================
; Function: ConvertBuffer
; Iterates through memory arrays and outputs formatted matrix layouts
; ====================================================================
ConvertBuffer:
    mov       rsi, qword[oldbrkaddr]
    mov       rcx, qword[contentsize]
    xor       r8, r8                          ; Clear dynamic tracking column width loops

.repeat:    
    xor       rax, rax
    lodsb                                     ; Read exactly 1 byte out from data array to AL
    inc       r8
    
    cmp       r10, 1
    je        .convert                        ; Pass 2 active -> bypass clean character filter maps
    
    ; Protect HTML rendering layouts by stripping control characters out
    cmp       al, 0x20
    jb        .changetodot
    cmp       al, 0x7E
    jbe       .convert

.changetodot:
    mov       al, '.'                         ; Replace problematic binaries with space dots

.convert:    
    push      rcx                             ; Protect loop registers context spaces
    push      rsi                             

    ; Hex mask assembly optimization routines
    mov       dl, al
    and       dl, 0x0F                        ; Isolate lower nibble value block
    cmp       dl, 9
    jle       .low_digit
    add       dl, 7
.low_digit:
    add       dl, '0'

    mov       dh, al
    shr       dh, 4                           ; Isolate upper nibble value block
    cmp       dh, 9
    jle       .high_digit
    add       dh, 7
.high_digit:
    add       dh, '0'

    ; Unify values back inside the AX variables configuration space
    mov       al, dh
    mov       ah, dl

    cmp       r10, 1
    je        .toHex

    ; Pass 1 rendering process (Characters outputs pipeline)
    mov       word[charbuffer.value], ax
    mov       rsi, charbuffer
    mov       rdx, charbuffer.length
    jmp       .write

.toHex:
    ; Pass 2 rendering process (Hexadecimal outputs pipeline)
    mov       word[hexbuffer.value], ax
    mov       rsi, hexbuffer
    mov       rdx, hexbuffer.length

.write:
    mov       rdi, 1                          ; stdout
    mov       rax, 1                          ; sys_write
    syscall   

    pop       rsi                             ; Safely reload position counters references
    pop       rcx
    
    cmp       r8, COLUMNS                     ; Has row successfully filled 32 items wide?
    jl        .continue
    
    ; Row full. Inject an HTML break element line to roll grid alignment
    xor       r8, r8                          ; Reset column tracker
    push      rsi
    push      rcx
    mov       rdi, 1
    mov       rsi, break_tag
    mov       rdx, break_tag.length
    mov       rax, 1                          ; sys_write
    syscall   
    pop       rcx
    pop       rsi

.continue:
    dec       rcx
    and       rcx, rcx
    jnz       .repeat
    ret