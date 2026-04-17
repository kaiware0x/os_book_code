    .def    sleep   0xb2000

    movi    r8, hello_str
    syscall 1
    movi    r8, 600
    calli   sleep
loop:
    jpi     loop
hello_str:
    .string "Hello, World!\n"
