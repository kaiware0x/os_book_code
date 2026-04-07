    .def    sleep   0xb2000

    movi    r8, msg1
    syscall 1
    movi    r8, 1
    calli   sleep

    movi    r8, msg2
    syscall 1
    movi    r8, 5
    calli   sleep

    movi    r8, msg3
    syscall 1
    movi    r8, 10
    calli   sleep

    ret

msg1:
    .string "Waiting 1s\n"
msg2:
    .string "Waiting 5s\n"
msg3:
    .string "Waiting 10s\n"
