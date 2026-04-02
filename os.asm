    .addr   0x80000
    movi    r8, start_message
    syscall 1

cmdloop:
    movi    r0, 0
    movi    r1, keybuffer
    stb     r0, [r1]

draw_cmdline:
    movi    r8, prompt ; '>'
    syscall 1 ; draw r8
    movi    r8, keybuffer ; key input contents
    syscall 1 ; show r8 pointing char

keyloop:
    syscall 3 ; get key input (1char)

    ; is pressed any key?
    sbti    r8, 0 ; is r8 zero?
    jpzi    keyloop ; if zero, jump to keyloop
    sbti    r8, 92 ; is Backslash?
    jpzi    keyloop

    ; is pressed Delete/Backspace key?
    sbti    r8, 8 ; BS
    jpzi    do_bs
    sbti    r8, 127 ; DEL
    jpzi    do_bs

    ; is pressed Enter key?
    sbti    r8, 10 ; LF
    jpzi    do_enter
    sbti    r8, 13 ; CR
    jpzi    do_enter

    ; is input length 80?
    sbti    r0, 80
    jpnui   draw_cmdline

    ;
    stb     r8, [r1] ; store byte
    inc     r0
    inc     r1
    movi    r8, 0
    stb     r8, [r1]
    jpi     draw_cmdline

do_bs:
    dec     r1
    dec     r0
    jpui    cmdloop
    movi    r2, 0 ; set 0 to r2
    stb     r2, [r1] ; store r2 to r1
    jpi     draw_cmdline

do_enter:
    movi    r8, 10 ; 10 == 改行文字
    syscall 0 ; show 改行文字
    ; jump to cmdloop if r0 == 0
    sbti    r0, 0
    jpzi    cmdloop
    ;
    movi    r2, 0
    stb     r2, [r1]
    movi    r8, keybuffer
    ; exit
    movi    r9, cmd_exit
    calli   cmp_str ; strcmp(r8, r9)
    jpzi    do_exit
    ; reg
    movi    r9, cmd_reg
    calli   cmp_str
    jpzi    do_reg
    ; ls
    movi    r9, cmd_ls
    calli   cmp_str
    jpzi    do_ls
    ;
    movi    r8, cmd_error1
    syscall 1
    movi    r8, keybuffer
    syscall 1
    movi    r8, cmd_error2
    syscall 1
    jpi     cmdloop

do_exit:
    movi    r8, end_message
    syscall 1
    halt
do_reg:
    syscall 20 ; show register
    jpi     cmdloop
do_ls:
    syscall 21 ; show ./dir
    jpi     cmdloop

halt ; これより先はデータ領域など

; DATA
start_message:
    .string "welcome to simple OS!\n"
prompt:
    .string "\033[2K\r> "
cmd_reg:
    .string "reg"
cmd_exit:
    .string "exit"
cmd_ls:
    .string "ls"
cmd_error1:
    .string "Command "
cmd_error2:
    .string " not found.\n"
end_message:
    .string "bye.\n\n"


; System Function
    .addr 0xB0000
cmp_str: ; compare string
    ; レジスタのデータをスタックに退避
    push    r0
    push    r1
    push    r2
    push    r3
    mov     r0, r8 ; r0 = r8
    mov     r1, r9
_cmp_loop:
    ldb     r2, [r0]
    ldb     r3, [r1]
    sbt     r2, r3 ; is r2==r3 ?
    jpnzi   _cmp_str_end ; 一致しなければend
    sbti    r2, 0 ; is r2==0 ? 終端判定
    jpzi    _cmp_str_end ; 一致すればend
    inc     r0
    inc     r1
    jpi     _cmp_loop
_cmp_str_end:
    ; レジスタの復帰
    pop     r3
    pop     r2
    pop     r1
    pop     r0
    ret

; Buffer
    .addr   0xc0000

keybuffer:
    .byte   0
