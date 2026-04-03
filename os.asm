    .addr   0x80000
    syscall 10 ; UNIX時刻をr8レジスタにセット
    stdi    r8, [basetime]
    movi    tp, 0
    movi    vt, vector_table
    ei
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
    ;
    movi    r8, 1
    movi    r9, keybuffer
    calli   get_nth_token
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
    ; exec
    movi    r9, cmd_exec
    calli   cmp_str
    jpzi    do_exec
    ; date
    movi    r9, cmd_date
    calli   cmp_str
    jpzi    do_date
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
do_exec:
    movi    r8, 2 ; token 2つ分
    movi    r9, keybuffer ; 対象文字列
    calli   get_nth_token
    syscall 22 ; dirフォルダ内のバイナリを実行
    jpi     cmdloop
do_date:
    lddi    r8, [basetime] ; r8にOS起動時点のUNIXタイムをセット
    syscall 11 ; 現在時刻を 2026-04-03 21:45:36 のように表示
    jpi     cmdloop

halt ; これより先はデータ領域など

; Handler
int_timer: ; interrpted timer event
    inc     tp
int_other:
    iret

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
cmd_exec:
    .string "exec"
cmd_date:
    .string "date"
basetime:
    .dword  0
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

    .addr   0xb1000
get_nth_token:
    push    r0
    push    r1
    push    r2
    push    r3
    mov     r0, r9 ; 入力文字列先頭ポインタをr0に格納
    movi    r1, 0
    movi    r2, 0
_get_token_addr:
_outer_loop:
    dec     r8 ; チェックするトークン数 (SPACE区切り)
    jpui    _outer_loop_end
_inner_loop:
    ldb     r3, [r0] ; r3 = *(r0)
    sbti    r3, 9 ; is SPACE?
    jpzi    _do_space
    sbti    r3, 32 ; is SPACE?
    jpzi    _do_space
    sbti    r3, 0
    jpzi    _null_return
    sbti    r2, 0
    jpnzi   _inner_loop_next ; r2 != 0 なら次へ
    not     r2
    mov     r1, r0
    jpi     _inner_loop_end
_do_space:
    sbti    r2, 0
    jpzi    _inner_loop_next
    not     r2
_inner_loop_next:
    inc     r0
    jpi     _inner_loop
_inner_loop_end:
    jpi     _outer_loop
_outer_loop_end:
    movi    r0, tokenbuffer
_copy_token:
    ldb     r2, [r1] ; r2 = *r1
    stb     r2, [r0] ; *r0 = r2
    sbti    r2, 9
    jpzi    _cut_token
    sbti    r2, 32
    jpzi    _cut_token
    sbti    r2, 0
    jpzi    _get_nth_token_end
    inc     r0
    inc     r1
    jpi     _copy_token
_null_return:
    movi    r0, tokenbuffer
_cut_token:
    movi    r2, 0
    stb     r2, [r0]
_get_nth_token_end:
    pop     r3
    pop     r2
    pop     r1
    pop     r0
    movi    r8, tokenbuffer
    ret

; Buffer
    .addr   0xc0000
keybuffer:
    .byte   0

    .addr   0xc1000
tokenbuffer:
    .byte   0

; Vector Table
    .addr   0xff800
vector_table:
    .dword  int_timer
    .dword  int_other
    .dword  int_other
    .dword  int_other
