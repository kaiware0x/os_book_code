    movi    r8, lmem_msg
    syscall 1
    movi    r8, 0x10000 ; 論理アドレス
    movi    r9, 1
    syscall 40

    movi    r8, pmem_msg
    syscall 1
    movi    r8, 0x90000 ; 物理アドレス
    movi    r9, 0
    syscall 40

    ret

lmem_msg:
    .string "[Logical Memory Dump]\n"
pmem_msg:
    .string "[Physical Memory Dump]\n"
