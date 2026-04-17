    movi    r0, 0x12345

    ; emu.py で 0x20000 pageを未割当にしているので Page Fault が起きる
    movi    r8, msg1
    syscall 1
    stdi    r0, [0x23000]

    movi    r8, msg2
    syscall 1
    lddi    r1, [0x23000]

    mov     r8, r1
    movi    r9, fmt_str
    syscall 2
    movi    r8, 10
    syscall 0
    ret

msg1:
    .string "stdi   r0, [0x23000]\n"
msg2:
    .string "lddi   r0, [0x23000]\n"

fmt_str:
    .string "05X"
