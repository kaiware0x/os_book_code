        MOVI    R8, hello_str
        SYSCALL 1 ; print string in r8
        ret

hello_str:
        .STRING "Hello, World!\n"
