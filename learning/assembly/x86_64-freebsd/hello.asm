.section .data
msg:
    .ascii "Hello, world!\n"
len = . - msg

.section .text
.global _start

_start:
    # write(1, msg, len)
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rel msg]
    mov     rdx, len
    syscall

    # exit(0)
    mov     rax, 1
    xor     rdi, rdi
    syscall
