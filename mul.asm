; 計算部分
        MOVI    R0, 256
        MOVI    R1, 16
        MUL     R0, R1

; 結果表示部分
        ; 10進数で表示
        MOV     R8, R0
        MOVI    R9, fmt_str1
        SYSCALL 2
        ; 改行
        MOVI    R8, 10
        SYSCALL 0
        ; 16進数で表示
        MOV     R8, R0
        MOVI    R9, fmt_str2
        SYSCALL 2
        ; 改行
        MOVI    R8, 10
        SYSCALL 0
; 終了
        ret

; 書式指定用文字列
fmt_str1:
        .STRING ""
fmt_str2:
        .STRING "#04x"
