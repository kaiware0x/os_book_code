    .def    runnable        0
    .def    waiting         1
    .def    timeslice       50 ; 0.1s x 50 で最大5s実行可能
    .def    t0_stack_btm    0xff000
    .def    t1_stack_btm    0xf0000
    .def    t2_stack_btm    0xe8000
    .def    t3_stack_btm    0xe0000
    .def    t4_stack_btm    0xd8000

    .addr   0x80000
; Task1 setup
    movi    sp, t1_stack_btm
    movi    r0, print_t1_message
    push    r0 ; pc
    movi    r0, 0x4000
    muli    r0, 0x10000
    push    r0 ; cr
    movi    r0, 0 ; dummy data
    push    r0 ; r0
    push    r0 ; r1
    push    r0 ; r2
    push    r0 ; r3
    push    r0 ; r4
    push    r0 ; r5
    push    r0 ; r6
    push    r0 ; r7
    push    r0 ; r8
    push    r0 ; r9
    push    r0 ; pt
    movi    r0, vector_table
    push    r0 ; vt
    stdi    sp, [_t1_sp]
; Task2 setup
    movi    sp, t2_stack_btm
    movi    r0, print_t2_message
    push    r0 ; pc
    movi    r0, 0x4000
    muli    r0, 0x10000
    push    r0 ; cr
    movi    r0, 0 ; dummy data
    push    r0 ; r0
    push    r0 ; r1
    push    r0 ; r2
    push    r0 ; r3
    push    r0 ; r4
    push    r0 ; r5
    push    r0 ; r6
    push    r0 ; r7
    push    r0 ; r8
    push    r0 ; r9
    push    r0 ; pt
    movi    r0, vector_table
    push    r0 ; vt
    stdi    sp, [_t2_sp]
; Task3 setup
    movi    sp, t3_stack_btm
    movi    r0, print_t3_message
    push    r0 ; pc
    movi    r0, 0x4000
    muli    r0, 0x10000
    push    r0 ; cr
    movi    r0, 0 ; dummy data
    push    r0 ; r0
    push    r0 ; r1
    push    r0 ; r2
    push    r0 ; r3
    push    r0 ; r4
    push    r0 ; r5
    push    r0 ; r6
    push    r0 ; r7
    push    r0 ; r8
    push    r0 ; r9
    push    r0 ; pt
    movi    r0, vector_table
    push    r0 ; vt
    stdi    sp, [_t3_sp]
; Task4 setup
    movi    sp, t4_stack_btm
    movi    r0, idle_loop
    push    r0  ; PC 相当, idle_loop を実行させる
    movi    r0, 0x4000
    muli    r0, 0x10000
    push    r0      ; CR 相当
    movi    r0, 0   ; Dummy data
    push    r0      ; r0
    push    r0      ; r1
    push    r0      ; r2
    push    r0      ; r3
    push    r0      ; r4
    push    r0      ; r5
    push    r0      ; r6
    push    r0      ; r7
    push    r0      ; r8
    push    r0      ; r9
    push    r0      ; PT
    movi    r0, vector_table
    push    r0      ; VT
    stdi    sp, [_t4_sp]
; Start Task0
    movi    sp, t0_stack_btm
    stdi    sp, [_t0_sp]
    movi    r0, 0
    stbi    r0, [current_task]
    jpi     os_start
idle_loop:
    jpi     idle_loop

print_t1_message:
    ; print 'A'
    movi    r8, 0x41
    syscall 0
    ; 5秒Sleepして自己ループ
    movi    r8, 5
    calli   sleep
    jpi     print_t1_message
print_t2_message:
    ; print 'B'
    movi    r8, 0x42
    syscall 0
    ; 10秒Sleepして自己ループ
    movi    r8, 10
    calli   sleep
    jpi     print_t2_message
print_t3_message:
    ; print 'C'
    movi    r8, 0x43
    syscall 0
    ; 20秒Sleepして自己ループ
    movi    r8, 20
    calli   sleep
    jpi     print_t3_message

os_start:
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
    calli   key_input
    sbti    r8, 92 ; Ignore '\'
    jpzi    keyloop
    sbti    r8, 8
    jpzi    do_bs
    sbti    r8, 10
    jpzi    do_enter
    sbti    r8, 13
    jpzi    do_enter
    sbti    r0, 80 ; input length
    jpnui   draw_cmdline
    stb     r8, [r1]
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
    ; Tick の計算と Status の変更
_sleep_proc:
    push    r0 ; Stackに退避
    push    r1
    push    r2
    push    r3
    ; Loop に使う変数の用意
    movi    r1, task_sleep_ticks
    movi    r2, task_status
    movi    r3, 0 ; Loop Counter
_sleep_proc_loop:
    ; 残りtickが0なら次のタスクへ
    ldw     r0, [r1] ; r0 <- *r1
    sbti    r0, 0
    jpzi    _next_task

    dec     r0
    stw     r0, [r1] ; r0 -> *r1
    sbti    r0, 0
    jpnzi   _next_task

    movi    r0, runnable
    stb     r0, [r2] ; runnable -> *r2
_next_task:
    inc     r3
    ; 4回LoopしたらEnd
    sbti    r3, 4
    jpzi    _sleep_proc_end

    addi    r1, 2 ; task_sleep_ticksはWordなので2Byte足す
    inc     r2
    jpi     _sleep_proc_loop
_sleep_proc_end:
    pop     r3
    pop     r2
    pop     r1
    pop     r0

_timeslice_proc:
    push    r0
    push    r1
    ; basetick が0でないなら _check_timeslice へ jump
    lddi    r0, [basetick]
    sbti    r0, 0
    jpnzi   _check_timeslice
    ; basetick が0(初期値)なら tp のデータを basetick へ保存
    mov     r0, tp ; r0 = tp
    stdi    r0, [basetick]
_check_timeslice:
    mov     r1, tp ; r1 = tp
    sub     r1, r0 ; r1 -= r0
    ; r1 - timeslice < 0 なら _no_task_switch へJump
    sbti    r1, timeslice
    jpui    _no_task_switch
    ; basetick を0にして _task_switch へ
    movi    r0, 0
    stdi    r0, [basetick]
    pop     r1
    pop     r0
    jpi     _task_switch
_no_task_switch:
    pop     r1
    pop     r0
    iret

_task_switch:
    push    r0
    push    r1
    push    r2
    push    r3
    push    r4
    push    r5
    push    r6
    push    r7
    push    r8
    push    r9
    push    pt
    push    vt

_save_sp:
    ; Task毎のSPアドレスを計算する
    ; r1 = 4 * r0 + sp
    ldbi    r0, [current_task]
    mov     r1, r0
    muli    r1, 4
    addi    r1, task_stack_pointer
    std     sp, [r1] ; 現在の SP の値を計算したアドレスへ書き込み
; _find_loop の準備
    movi    r2, 0 ; Loop Counter の用意
    inc     r0 ; Task番号r0をincし次のタスクへ
    modi    r0, 4 ; r0を0~3に収める
_find_loop:
    movi    r1, task_status ; r1 = task_status 配列の先頭ポインタ
    add     r1, r0 ; r1 += r0 (タスク番号分ポインタをずらす)
    ldb     r3, [r1] ; ポインタから Load Byte して r3 へ
    sbti    r3, runnable ; Status が Runnable か
    jpzi    _select_next
    ; Task0~3 全てがWaitingだったら Task4 へ
    inc     r2
    sbti    r2, 4
    jpui    _another_cand
    movi    r0, 4
    jpi     _select_next
_another_cand:
    inc     r0
    modi    r0, 4
    jpi     _find_loop ; Loop 続行

_select_next:
    stbi    r0, [current_task] ; r0 -> *current_task
    mov     r8, r0 ; r8 <- r0
    syscall 30
    ; Task毎のSPを計算して格納
    ; sp = r0 * 4 + task_stack_pointer
    muli    r0, 4
    addi    r0, task_stack_pointer
    ldd     sp, [r0]

_int_timer_end:
    pop     vt
    pop     pt
    pop     r9
    pop     r8
    pop     r7
    pop     r6
    pop     r5
    pop     r4
    pop     r3
    pop     r2
    pop     r1
    pop     r0
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
cmd_error1:
    .string "Command "
cmd_error2:
    .string " not found.\n"
end_message:
    .string "bye.\n\n"
basetime:
    .dword  0
basetick:
    .dword  0

; Task DATA
current_task:
    .byte   0 ; 0~4?

task_status:
_t0_status:
    .byte   runnable
_t1_status:
    .byte   runnable
_t2_status:
    .byte   runnable
_t3_status:
    .byte   runnable
_t4_status:
    .byte   waiting

task_sleep_ticks:
_t0_sleep_ticks:
    .word   0
_t1_sleep_ticks:
    .word   0
_t2_sleep_ticks:
    .word   0
_t3_sleep_ticks:
    .word   0
_t4_sleep_ticks:
    .word   0

task_stack_pointer:
_t0_sp:
    .dword  0
_t1_sp:
    .dword  0
_t2_sp:
    .dword  0
_t3_sp:
    .dword  0
_t4_sp:
    .dword  0


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

    .addr   0xb2000
sleep:
    push    r0
    push    r1

    ldbi    r0, [current_task] ; ro <- *current_task
    mov     r1, r0
    ; task_sleep_ticks は 2Byte 配列なのでOffsetを2倍する
    muli    r1, 2
    addi    r1, task_sleep_ticks
    muli    r8, 10 ; r8は引数s. 10倍してs->tickへ単位変換
    stw     r8, [r1] ; r8 -> *r1
    addi    r0, task_status ; r0 <- task_status[current_task]
    movi    r8, waiting
    stb     r8, [r0] ; waiting -> task_status[current_task]

    pop     r1
    pop     r0
    movi    r8, _sleep_end
    push    r8 ; pc <- _sleep_end
    push    cr
    di
    jpi     _task_switch
_sleep_end:
    ret

    .addr   0xb3000
key_input:
    syscall 3
    sbti    r8, 0
    jpnzi   _got_key
_do_yield:
    movi    r8, _resume_point
    push    r8
    push    cr
    di
    jpi     _task_switch
_resume_point:
    syscall 3
    sbti    r8, 0
    jpzi    _do_yield
_got_key:
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
