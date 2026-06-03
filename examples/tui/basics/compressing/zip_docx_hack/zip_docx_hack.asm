; ==============================================================================
; Name:         zip_docx_hack.asm
; Description:  A pure x86_64 assembly utility that demonstrates how to create
;               a compressed zip archive by invoking the system's native zip binary.
;               Useful for repacking extracted MS Office XML directories back into
;               valid .docx/.xlsx files. Uses direct Linux syscalls.
; Build:        nasm -f elf64 zip_docx_hack.asm -o zip_docx_hack.o
;               ld zip_docx_hack.o -o zip_docx_hack
; Usage:        ./zip_docx_hack
; ==============================================================================

bits 64

global _start

; --- Constants & Syscall Numbers ---
sys_write       equ 1
sys_fork        equ 57
sys_execve      equ 59
sys_wait4       equ 61
sys_exit        equ 60

stderr          equ 2

section .data
    ; Full binary path required for the execve environment
    command:        db "/usr/bin/zip", 0        
    
    ; Arguments formatted for: zip -r example.zip example/
    arg_prog:       db "zip", 0
    arg_recurse:    db "-r", 0                  ; Process directories recursively
    arg_archive:    db "example.zip", 0         ; Output file target
    arg_source:     db "example/", 0            ; Target directory to pack

    ; The argv array MUST be a NULL-terminated list of pointers.
    ; Layout map: argv[0]=name, argv[1]=flag, argv[2]=output, argv[3]=source
    argvPtr:        dq arg_prog                 
                    dq arg_recurse              
                    dq arg_archive              
                    dq arg_source               
                    dq 0                        ; Mandatory NULL terminator

    ; Environment string pointer array (Empty list inherits base environment defaults)
    envPtr:         dq 0                        ; Mandatory NULL terminator

    ; Error tracking diagnostics
    msg_err_fork:   db "fork error", 10
    len_err_fork    equ $ - msg_err_fork
    
    msg_err_exec:   db "execve error (not expected)", 10
    len_err_exec    equ $ - msg_err_exec
    
    msg_err_wait:   db "wait4 error", 10
    len_err_wait    equ $ - msg_err_wait

section .text
_start:
    ; Secure operational boundaries with strict 16-byte stack alignment
    mov rbp, rsp
    and rsp, -16

    ; 1. Initiate process splitting: fork()
    mov rax, sys_fork
    syscall
    
    test rax, rax
    js .handle_fork_error       ; Jump if minus sign flag triggered (allocation failure)
    jz .run_child               ; RAX == 0 indicates execution focus inside child path

    ; 2. Parent Scope: Wait globally for compression to wrap up: wait4(-1, NULL, 0, NULL)
    mov rax, sys_wait4
    mov rdi, -1                 ; Wait for any child process execution change
    xor rsi, rsi                ; wstatus = NULL
    xor rdx, rdx                ; options = 0
    xor r10, r10                ; rusage = NULL
    syscall
    
    test rax, rax
    js .handle_wait_error
    jmp .exit_success

.run_child:
    ; 3. Child Scope: Swaps binary mapping: execve(command, argvPtr, envPtr)
    mov rax, sys_execve
    mov rdi, command
    mov rsi, argvPtr
    mov rdx, envPtr
    syscall
    
    ; If hardware execution enters this track, the system engine execution failed
    mov rax, sys_write
    mov rdi, stderr
    mov rsi, msg_err_exec
    mov rdx, len_err_exec
    syscall
    
    mov rax, sys_exit
    mov rdi, 1                  ; Kill child lane with exit code 1
    syscall

.handle_fork_error:
    mov rax, sys_write
    mov rdi, stderr
    mov rsi, msg_err_fork
    mov rdx, len_err_fork
    syscall
    jmp .exit_failure

.handle_wait_error:
    mov rax, sys_write
    mov rdi, stderr
    mov rsi, msg_err_wait
    mov rdx, len_err_wait
    syscall
    jmp .exit_failure

.exit_failure:
    mov rax, sys_exit
    mov rdi, 1
    syscall

.exit_success:
    mov rax, sys_exit
    xor rdi, rdi                ; Return graceful clean termination code 0
    syscall