        .DEF    n_digits 1000
        .DEF    val_f 10000
        .DEF    block_size 14

        MOVI    R1, (n_digits / 4 + 2) * block_size
        MOVI    R2, 0
        MOVI    R3, 0
        SUBI    R1, 14
        MOV     R0, R1
        DEC     R0
first_loop:
        SBTI    R0, 1
        JPUI    first_result
        MUL     R2, R0
        MOVI    R5, 2000
        MOVI    R6, val_f
        MUL     R6, R5
        ADD     R2, R6
        MOV     R4, R0
        ADD     R4, R0
        DEC     R4
        MOV     R5, R2
        MOD     R5, R4
        MOV     R6, R0
        MULI    R6, 4
        ADDI    R6, arr
        STD     R5, [R6]
        DIV     R2, R4
        DEC     R0
        JPI     first_loop
first_result:
        MOV     R5, R2
        DIVI    R5, val_f
        ADD     R5, R3
        MOV     R8, R5
        DIVI    R8, 1000
        MOVI    R9, format_str1
        SYSCALL 2
        MOVI    R8, 46
        SYSCALL 0
        MOV     R8, R5
        MODI    R8, 1000
        MOVI    R9, format_str3
        SYSCALL 2
        MOVI    R7, n_digits
        SUBI    R7, 3
        MOV     R3, R2
        MODI    R3, val_f
        MOV     R2, R3
        SUBI    R1, 14
        MOV     R0, R1
second_loop_outer:
        SBTI    R0, 1
        JPUI    end
        DEC     R0
second_loop_inner:
        SBTI    R0, 1
        JPUI    second_result
        MUL     R2, R0
        MOV     R5, R0
        MULI    R5, 4
        ADDI    R5, arr
        LDD     R6, [R5]
        MULI    R6, val_f
        ADD     R2, R6
        MOV     R4, R0
        ADD     R4, R0
        DEC     R4
        MOV     R6, R2
        MOD     R6, R4
        STD     R6, [R5]
        DIV     R2, R4
        DEC     R0
        JPI     second_loop_inner
second_result:
        MOV     R5, R2
        DIVI    R5, val_f
        ADD     R5, R3
        SBTI    R7, 5
        JPNUI   result_normal
        SBTI    R7, 4
        JPZI    print_4digits
        SBTI    R7, 3
        JPZI    print_3digits
        SBTI    R7, 2
        JPZI    print_2digits
print_1digit:
        DIVI    R5, 1000
        MOV     R8, R5
        MOVI    R9, format_str1
        SYSCALL 2
        JPI     end
print_2digits:
        DIVI    R5, 100
        MOV     R8, R5
        MOVI    R9, format_str2
        SYSCALL 2
        JPI     end
print_3digits:
        DIVI    R5, 10
        MOV     R8, R5
        MOVI    R9, format_str3
        SYSCALL 2
        JPI     end
print_4digits:
        MOV     R8, R5
        MOVI    R9, format_str4
        SYSCALL 2
        JPI     end
result_normal:
        MOV     R8, R5
        MOVI    R9, format_str4
        SYSCALL 2
        MOV     R3, R2
        MODI    R3, val_f
        MOV     R2, R3
        SUBI    R1, 14
        MOV     R0, R1
        SUBI    R7, 4
        JPI     second_loop_outer
end:
        MOVI    R8, 10
        SYSCALL 0
        ret

format_str1:
        .STRING "#01"
format_str2:
        .STRING "#02"
format_str3:
        .STRING "#03"
format_str4:
        .STRING "#04"
; 配列用の領域
        .ADDR   0x08000
arr:
        .ADDR   0x0FFFF
        .BYTE   0
