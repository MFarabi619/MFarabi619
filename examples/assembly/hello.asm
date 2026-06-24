.global _main
.extern _printf
.extern _exit
.align 2

_main:
    adrp    x0, msg@page
    add     x0, x0, msg@pageoff
    bl      _printf

    mov     w0, 0
    bl      _exit

.section __DATA,__data
msg:
    .asciz "Hello, world!\n"
