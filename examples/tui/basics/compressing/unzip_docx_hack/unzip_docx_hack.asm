; ==============================================================================
; Name:         unzip_docx_hack.asm
; Description:  A pure x86_64 assembly utility demonstrating an MS Office hack.
;               Since .docx files are structured ZIP archives, this program forks
;               and executes the native unzip binary to extract 'testdoc.docx' 
;               into a target directory ('testdoc.docx-unzip') using direct syscalls.
; Build:        nasm -f elf64 unzip_docx_hack.asm -o unzip_docx_hack.o
;               ld unzip_docx_hack.o -o unzip_docx_hack
; Usage:        ./unzip_docx_hack
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
    ; Full path to the system execution binary
    command1:       db "/usr/bin/unzip", 0      
    
    ; Arguments formatted for: unzip testdoc.docx -d testdoc.docx-unzip
    arg_prog:       db "unzip", 0
    arg_source:     db "testdoc.docx", 0        
    arg_dir_flag:   db "-d", 0                  ; Extract into destination directory
    arg_dest_dir:   db "testdoc.docx-unzip", 0

    ; The argv array MUST be a NULL-terminated list of pointers.
    ; Order layout: argv[0]=program name, argv[1]=source, argv[2]=flag, argv[3]=destination
    argv1Ptr:       dq arg_prog                 
                    dq arg_source               
                    dq arg_dir_flag             
                    dq arg_dest_dir             
                    dq 0                        ; Mandatory NULL terminator

    ; Environment parameter list (Empty/NULL inherits base environment restrictions)
    envPtr:         dq 0                        ; Mandatory NULL terminator

    ; Diagnostic warning logs
    msg_err_fork:   db "fork error", 10
    len_err_fork    equ $ - msg_err_fork
    
    msg_err_exec:   db "execve error (not expected)", 10
    len_err_exec    equ $ - msg_err_exec
    
    msg_err_wait:   db "wait4 error", 10
    len_err_wait    equ $ - msg_err_wait

section .text
_start:
    ; Secure strict 16-byte stack alignment across operational scopes
    mov rbp, rsp
    and rsp, -16

    ; 1. Generate tracking fork child branch process context: fork()
    mov rax, sys_fork
    syscall
    
    test rax, rax
    js .handle_fork_error       ; Negative result maps to allocation failures
    jz .run_child               ; RAX == 0 indicates execution is within child path

    ; 2. Parent Process Scope: Block and await child resolution state: wait4(-1, NULL, 0, NULL)
    mov rax, sys_wait4
    mov rdi, -1                 ; Wait for any child process globally (wait emulation)
    xor rsi, rsi                ; wstatus = NULL
    xor rdx, rdx                ; options = 0
    xor r10, r10                ; rusage = NULL
    syscall
    
    test rax, rax
    js .handle_wait_error
    jmp .exit_success

.run_child:
    ; 3. Child Process Scope: Transmute execution space: execve(command1, argv1Ptr, envPtr)
    mov rax, sys_execve
    mov rdi, command1
    mov rsi, argv1Ptr
    mov rdx, envPtr
    syscall
    
    ; If execve hits error constraints, log fallback failure output onto stderr channel
    mov rax, sys_write
    mov rdi, stderr
    mov rsi, msg_err_exec
    mov rdx, len_err_exec
    syscall
    
    mov rax, sys_exit
    mov rdi, 1                  ; Die out with error signature status 1
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
    xor rdi, rdi                ; Success exit code status 0
    syscall