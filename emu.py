import multiprocessing as mp
import time
import sys
import termios
import tty
import os
import re
from queue import Empty
from pathlib import Path
from datetime import datetime, timezone, timedelta

# シミュレータの設定
registers_name = ['R0', 'R1', 'R2', 'R3', 'R4', 'R5', 'R6', 'R7', 'R8', 'R9',
                  'TP', 'SP', 'PC', 'PT', 'VT', 'CR']
registers = {
    'R0':  0,
    'R1':  0,
    'R2':  0,
    'R3':  0,
    'R4':  0,
    'R5':  0,
    'R6':  0,
    'R7':  0,
    'R8':  0,
    'R9':  0,
    'TP':  0,
    'SP':  0xFF000,
    'PC':  0x80000,
    'PT':  0x00000,
    'VT':  0x00000,
    'CR':  0x00000000,
}

mp.set_start_method('fork')
int_flag = mp.Value('I', 0)    # 0=Disable 1=Enable
int_queue = mp.Queue()

memory = bytearray(1048576)
mmu_flag = 0
pagetable = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
page_bases = [i << 16 for i in range(16)]  # 論理ページに対応する物理ページの先頭アドレスを保持
task_pt_addr = [ 0, 0, 0, 0 ]
pagefault_laddr = 0

# ====== 仮想コンソール設定 ======
NUM_VC = 4
key_queues = [mp.Queue() for _ in range(NUM_VC)]
vc_switch_queue = mp.Queue()
active_vc_shared = mp.Value('i', 0)
vc_buffers = ['' for _ in range(NUM_VC)]
current_task_id = 0
def _task_to_vc(tid: int):
    # 0..3 のタスクは同番号のVCに固定、4=スリープは固定なし
    return tid if 0 <= tid < NUM_VC else None

_active_vc = 0  # メインプロセス内でのみ更新
MAX_VC_BUFFER = 200000  # 保持上限（必要に応じて調整）

def _vc_trunc(s: str) -> str:
    if len(s) <= MAX_VC_BUFFER:
        return s
    return s[-MAX_VC_BUFFER:]

def _tty_show_vc(idx: int):
    sys.stdout.write("\033[2J\033[H")            # clear screen + home
    sys.stdout.write(f"\n\033[90m[VC {idx} | Ctrl+]に続いて0～3で切替]\033[0m\n")
    buf = vc_buffers[idx]
    buf_norm = buf.replace('\r\n', '\n').replace('\r', '\n')
    try:
        rend = buf_norm.encode('utf-8', errors='backslashreplace').decode('unicode_escape')
    except Exception:
        rend = buf_norm
    sys.stdout.write(rend.replace('\n', '\r\n'))
    sys.stdout.flush()

def switch_vc(idx: int):
    global _active_vc
    if 0 <= idx < NUM_VC and idx != _active_vc:
        _active_vc = idx
        active_vc_shared.value = idx
        _tty_show_vc(_active_vc)

def vc_write(s):
    global vc_buffers
    global current_task_id

    # 仮想コンソールの切り替え
    vc_idx = _task_to_vc(current_task_id)
    if vc_idx is None:
        vc_idx = _active_vc

    # 型/エンコーディングを整える
    if isinstance(s, (bytes, bytearray)):
        s = bytes(s).decode('utf-8', errors='replace')
    else:
        s = str(s)

    # 改行を正規化（内部は \n）
    s = s.replace('\r\n', '\n').replace('\r', '\n')

    # バックスラッシュ表記（\n, \r, \t, \b, \x1b, \033, \uXXXX など）を実体化
    try:
        s_render = s.encode('utf-8', errors='backslashreplace').decode('unicode_escape')
    except Exception:
        s_render = s  # 念のためフォールバック

    # バッファ更新（必要なら上限でトリム）
    vc_buffers[vc_idx] = _vc_trunc(vc_buffers[vc_idx] + s)

    # VCがアクティブなら端末に出力（端末にANSI解釈を任せる）
    if vc_idx == _active_vc:
        out = s_render.replace('\n', '\r\n')
        sys.stdout.write(out)
        sys.stdout.flush()

def print_registers():
    """レジスタの現在の状態を出力"""
    for reg in registers_name:
        vc_write(f"{reg}: {registers[reg]:08X}\n")

def get_paddr(laddr):
    global pagefault_laddr
    lpn = (laddr >> 16) & 0xF
    if mmu_flag:
        ppn = pagetable[lpn]
        if ppn == 0xFF:
            pagefault_laddr = laddr & 0xFFFFF
            raise PageFault()
    else:
        ppn = lpn
    return (ppn << 16) | (laddr & 0xFFFF)

# read_lmemとwrite_lmemは仮想メモリーとデータをやり取りする関数
# 有効なnum_bytesは1、2、4のいずれか。
# read_lmemの戻り値と、write_lmemのdataは32ビット長の整数
def read_lmem(laddr, num_bytes):
    laddr &= 0xFFFFF
    off = laddr & 0xFFFF
    if off + num_bytes <= 0x10000:
        p = get_paddr(laddr)
        if num_bytes == 1:
            return memory[p]
        elif num_bytes == 2:
            return (memory[p] << 8) | memory[p+1]
        else:  # num_bytes == 4
            return (memory[p] << 24) | (memory[p+1] << 16) | (memory[p+2] << 8) | memory[p+3]
    # ページ境界をまたぐ場合の処理
    if num_bytes == 1:
        return memory[get_paddr(laddr)]
    elif num_bytes == 2:
        b0 = memory[get_paddr(laddr)]
        b1 = memory[get_paddr(laddr + 1)]
        return (b0 << 8) | b1
    else:  # num_bytes == 4
        b0 = memory[get_paddr(laddr)]
        b1 = memory[get_paddr(laddr + 1)]
        b2 = memory[get_paddr(laddr + 2)]
        b3 = memory[get_paddr(laddr + 3)]
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3

def write_lmem(laddr, data, num_bytes):
    laddr &= 0xFFFFF
    off = laddr & 0xFFFF
    if off + num_bytes <= 0x10000:
        p = get_paddr(laddr)
        if num_bytes == 1:
            memory[p] = data & 0xFF
        elif num_bytes == 2:
            memory[p  ] = (data >> 8) & 0xFF
            memory[p+1] =  data       & 0xFF
        else:
            memory[p  ] = (data >> 24) & 0xFF
            memory[p+1] = (data >> 16) & 0xFF
            memory[p+2] = (data >>  8) & 0xFF
            memory[p+3] =  data        & 0xFF
        return
    # ページ境界をまたぐ場合の処理
    if num_bytes == 1:
        memory[get_paddr(laddr)] = data & 0xFF
    elif num_bytes == 2:
        memory[get_paddr(laddr    )] = (data >> 8) & 0xFF
        memory[get_paddr(laddr + 1)] =  data       & 0xFF
    elif num_bytes == 4:
        memory[get_paddr(laddr    )] = (data >> 24) & 0xFF
        memory[get_paddr(laddr + 1)] = (data >> 16) & 0xFF
        memory[get_paddr(laddr + 2)] = (data >>  8) & 0xFF
        memory[get_paddr(laddr + 3)] =  data        & 0xFF

def push(data):
    registers['SP'] -= 4
    if registers['SP'] < 0:
        registers['SP'] = 0
    write_lmem(registers['SP'], data, 4)

def pop():
    data = read_lmem(registers['SP'], 4)
    registers['SP'] += 4
    return data

# 追加：ページフォルトを伝える内部例外
class PageFault(Exception):
    pass

# 追加：指定番号の割り込みへ即時遷移（同期例外用）
def _enter_interrupt(num):
    # 直ちにコンテキストを保存して遷移（割り込みフラグに関わらず実行）
    push(registers['PC'])
    push(registers['CR'])
    # 割り込み禁止に
    mode = ~(0b0100 << 28) & 0xFFFFFFFF
    registers['CR'] &= mode

    if (num < 0) or (num > 3):
        vc_write("Invalid int num.\n")
        sys.exit()

    addr = (registers['VT'] &0xFFFFF) + num * 4
    registers['PC'] = read_lmem(addr, 4)

def setflags(data):
    flag = 0
    if data == 0:
        flag = 0b0100  # Zero
    elif data < 0:
        flag = 0b0001  # Underflow
    elif data > 0xFFFFFFFF:
        flag = 0b0010  # Overflow
    mode = registers['CR'] & 0xF0000000
    registers['CR'] = mode + flag
    return (data & 0xFFFFFFFF)

def _read_c_string(laddr):
    s = []
    laddr &= 0xFFFFF
    while True:
        off = laddr & 0xFFFF
        chunk = min(0x10000 - off, 256)  # 適度なチャンク（例: 256B）
        p = get_paddr(laddr)
        # 0 終端までローカルで探索
        block = memory[p:p+chunk]
        z = block.find(0)
        if z == -1:
            s.extend(chr(b & 0x7F) for b in block)
            laddr += chunk
        else:
            s.extend(chr(b & 0x7F) for b in block[:z])
            break
    return ''.join(s)

def hexdump(data, start_addr, width=16):
    if not isinstance(data, (bytes, bytearray)):
        data = bytes(data)
    group_w = 23
    for offset in range(0, len(data), width):
        chunk = data[offset:offset + width]
        left_hex  = " ".join(f"{b:02X}" for b in chunk[:8])
        right_hex = " ".join(f"{b:02X}" for b in chunk[8:])
        hex_cols = f"{left_hex:<{group_w}}  {right_hex:<{group_w}}"
        ascii_cols = "".join(chr(b) if 0x20 <= b <= 0x7E else "." for b in chunk)
        ascii_cols = f"{ascii_cols:<{width}}".replace('\\', '\\\\')
        offset += start_addr
        vc_write(f"{offset:05X}  {hex_cols}  |{ascii_cols}|\n")

def do_syscall(syscall_num):
    global current_task_id
    value1 = registers['R8']
    value2 = registers['R9']

    # ページテーブルの同期
    if mmu_flag:
        pt = registers['PT'] & 0xFFFFF
        pagetable[:] = memory[pt : pt+16]
        for i in range(16):
            page_bases[i] = (pagetable[i] & 0xFF) << 16

    if syscall_num == 0:   # print char
        vc_write(chr(value1 & 0xFF))

    elif syscall_num == 1: # print string
        s = _read_c_string(value1)
        vc_write(s)

    elif syscall_num == 2: # print int with format string
        fmt = _read_c_string(value2)
        vc_write(format(value1, fmt))

    elif syscall_num == 3:  # get char (per-VC)
        while True:
            # まず VC切替要求を即処理（すぐ描画）
            try:
                while True:
                    idx = vc_switch_queue.get_nowait()
                    switch_vc(idx)
            except Empty:
                pass

            # 自タスクに対応するVCを決定（なければ表示中VCを使う）
            vc_idx = _task_to_vc(current_task_id)
            if vc_idx is None:
                vc_idx = active_vc_shared.value

            # そのVCの入力キューから読み込む
            try:
                ch = key_queues[vc_idx].get(timeout=0.005)
            except Empty:
                ch = '\0'
            registers['R8'] = ord(ch) & 0x7F
            break

    elif syscall_num == 10:  # get time data
        timedata = int(time.time())
        registers['R8'] = (timedata & 0xFFFFFFFF)

    elif syscall_num == 11:  # print date
        timedata = value1 + int(registers['TP'] / 10)
        dt = datetime.fromtimestamp(timedata).replace(tzinfo=timezone.utc)
        vc_write(dt.strftime('%Y-%m-%d %H:%M:%S') + "\n")

    elif syscall_num == 20: # print registers
        print_registers()

    elif syscall_num == 21:   # ls dir
        try:
            for f in Path("dir").iterdir():
                if f.is_file():
                    vc_write(f.name + "\n")
        except:
            vc_write("ls error.\n")

    elif syscall_num == 22: # exec file program
        pfile = _read_c_string(value1)
        try:
            with open("dir/" + pfile, "rb") as file:
                prog = file.read()
                memory[0:len(prog)] = prog
        except:
            vc_write("File open error.\n")
        else:
            push(registers['PC'])
            registers['PC'] = 0

    elif syscall_num == 23: # taskexec loader
        paddr = memory[task_pt_addr[value1 & 0xFF]] * 0x10000
        pfile = _read_c_string(value2)
        try:
            with open("dir/" + pfile, "rb") as file:
                prog = file.read()
                if len(prog) > 0x10000:
                    raise Exception
                memory[paddr : paddr + len(prog)] = prog
        except:
            vc_write("File open error.\n")

    elif syscall_num == 30:  # set_current_task_id
        current_task_id = value1 & 0xFF

    elif syscall_num == 40:
        start_addr = value1 & 0xFFFFF
        flag_logical = value2 & 1
        memdata = []
        if flag_logical:
            for i in range(256):
                memdata +=  read_lmem(value1 + i, 1).to_bytes()
        else:
            memdata = memory[value1:value1+256]
        hexdump(memdata, start_addr)

    elif syscall_num == 41:
        registers['R8'] = pagefault_laddr & 0xFFFFF

    else:
        vc_write(f"Syscall {syscall_num} not implement yet.\n")

def jump_op(op, addr):
    if op == 8:     # JP addr
        registers['PC'] = addr
    elif op == 9:   # CALL addr
        push(registers['PC'])
        registers['PC'] = addr
    elif op == 10:  # JPZ addr
        if registers['CR'] & 0b0100:
            registers['PC'] = addr
    elif op == 11:  # JPNZ addr
        if not (registers['CR'] & 0b0100):
            registers['PC'] = addr
    elif op == 12:  # JPO addr
        if registers['CR'] & 0b0010:
            registers['PC'] = addr
    elif op == 13:   # JPNO addr
        if not (registers['CR'] & 0b0010):
            registers['PC'] = addr
    elif op == 14:   # JPU addr
        if registers['CR'] & 0b0001:
            registers['PC'] = addr
    elif op == 15:   # JPNU addr
        if not (registers['CR'] & 0b0001):
            registers['PC'] = addr
    else:
        vc_write(f"Unknown opcode. jump_op {op}  Halting.\n")
        sys.exit()

def bin_op(op, d1, d2):
    if op == 0:
        return None
    elif op == 1:    # ADD d1, d2
        return setflags(d1 + d2)
    elif op == 2:    # SUB d1, d2
        return setflags(d1 - d2)
    elif op == 3:    # ADT d1, d2
        setflags(d1 + d2)
        return None
    elif op == 4:    # SBT d1, d2
        setflags(d1 - d2)
        return None
    elif op == 5:    # MUL d1, d2
        return setflags(d1 * d2)
    elif op == 6:    # DIV d1, d2
        if d2 == 0:
            vc_write("Error, division by zero.\n")
            sys.exit()
        return setflags(int(d1 / d2))
    elif op == 7:    # MOD d1, d2
        if d2 == 0:
            vc_write("Error, division by zero.\n")
            sys.exit()
        return setflags(d1 % d2)
    elif op == 8:    # AND d1, d2
        return (d1 & d2)
    elif op == 9:    # OR d1, d2
        return (d1 | d2)
    elif op == 10:    # XOR d1, d2
        return (d1 ^ d2)
    else:
        vc_write(f"Unknown opcode. bin_op {op} Halting.\n")
        sys.exit()

def mem_op(op, rd, addr):
    if op == 0:      # LDB rd, [addr]
        registers[registers_name[rd]] = read_lmem(addr, 1)
    elif op == 1:    # STB rd, [addr]
        data = registers[registers_name[rd]]
        write_lmem(addr, data, 1)
    elif op == 2:    # LDW rd, [addr]
        registers[registers_name[rd]] = read_lmem(addr, 2)
    elif op == 3:    # STW rd, [addr]
        data = registers[registers_name[rd]]
        write_lmem(addr, data, 2)
    elif op == 4:    # LDD rd, [addr]
        registers[registers_name[rd]] = read_lmem(addr, 4)
    elif op == 5:    # STD rd, [addr]
        data = registers[registers_name[rd]]
        write_lmem(addr, data, 4)
    else:
        vc_write(f"Unknown opcode. mem_op {op} Halting.\n")
        sys.exit()

def run():
    global mmu_flag
    regs = registers
    regn = registers_name
    """CPUの実行をシミュレート"""
    while True:
        # VC切替処理
        try:
            while True:
                idx = vc_switch_queue.get_nowait()
                switch_vc(idx)
        except Empty:
            pass

        # 割り込み処理
        if regs['CR'] & (0b0100 << 28):
            int_flag.value = 1
            try:
                int_num = int_queue.get_nowait()
            except Empty:
                pass
            else:
                push(regs['PC'])
                push(regs['CR'])
                mode = ~(0b0100 << 28) & 0xFFFFFFFF
                regs['CR'] &= mode
                int_flag.value = 0
                if (int_num < 0) or (int_num > 3):
                    vc_write("Invalid int num.\n")
                    break
                addr = (regs['VT'] & 0xFFFFF) + int_num * 4
                regs['PC'] = read_lmem(addr, 4)
                continue
        else:
            int_flag.value = 0

        try:
            # MMUのフラグ設定
            if regs['CR'] & (0b1000 << 28):
                mmu_flag = 1
            else:
                mmu_flag = 0

            # MMU有効時はpagetable更新
            if mmu_flag:
                pt = regs['PT'] & 0xFFFFF
                pagetable[:] = memory[pt : pt+16]
                for i in range(16):
                    page_bases[i] = (pagetable[i] & 0xFF) << 16

            # 命令のフェッチ
            inst = read_lmem(registers['PC'], 4)
            registers['PC'] += 4

            # 命令のデコード
            b0 = (inst >> 24) & 0xFF
            b1 = (inst >> 16) & 0xFF
            b2 = (inst >> 8)  & 0xFF
            b3 =  inst        & 0xFF

            op_type = b0 >> 4
            op      = b0 & 0x0F

            if op_type in (1, 2, 3):
                rd = b1 >> 4
                rs = b1 & 0x0F
            elif op_type in (4, 5, 6):
                rd  = b1 >> 4
                imm = ((b1 & 0x0F) << 16) | (b2 << 8) | b3

            # 命令の実行
            if op_type == 0:
                if   op == 0:    # NOP
                    pass
                elif op == 1:    # HALT
                    vc_write("CPU halted.\n")
                    print_registers()
                    break
                elif op == 2:    # RET
                    regs['PC'] = pop()
                elif op == 3:    # IRET
                    regs['CR'] = pop()
                    regs['PC'] = pop()
                elif op == 4:    # EI
                    mode = 0b0100 << 28
                    regs['CR'] |= mode
                elif op == 5:    # DI
                    mode = ~(0b0100 << 28) & 0xFFFFFFFF
                    regs['CR'] &= mode
                else:
                    vc_write(f"Unknown opcode. type0 {op} Halting.\n")
                    print_registers()
                    break

            elif op_type == 1:
                if   op == 0:    # PUSH r
                    push(regs[regn[rd]])
                elif op == 1:    # POP r
                    regs[regn[rd]] = pop()
                elif op == 2:    # INC r
                    data = regs[regn[rd]]
                    regs[regn[rd]] = setflags(data + 1)
                elif op == 3:    # DEC r
                    data = regs[regn[rd]]
                    regs[regn[rd]] = setflags(data - 1)
                elif op == 4:    # NOT r
                    data = regs[regn[rd]]
                    regs[regn[rd]] = ~data & 0xFFFFFFFF
                else:
                    jump_op(op, regs[regn[rd]])

            elif op_type == 2:
                if   op == 0:    # MOV rd, rs
                    regs[regn[rd]] = regs[regn[rs]]
                else:
                    d1 = regs[regn[rd]]
                    d2 = regs[regn[rs]]
                    data = bin_op(op, d1, d2)
                    if data != None:
                        regs[regn[rd]] = data

            elif op_type == 3:
                mem_op(op, rd, regs[regn[rs]])

            elif op_type == 4:
                if   op == 0:    # MOVI rd, imm
                    regs[regn[rd]] = imm
                else:
                    d1 = regs[regn[rd]]
                    data = bin_op(op, d1, imm)
                    if data != None:
                        regs[regn[rd]] = data

            elif op_type == 5:
                mem_op(op, rd, imm)

            elif op_type == 6:
                if op == 0:   # SYSCALL imm
                    do_syscall(imm)
                else:
                    jump_op(op, imm)

            else:
                vc_write(f"Unknown opcode. type6 {op} Halting.\n")
                break

        except PageFault:
            _enter_interrupt(3)
            continue

# Helper Processes
def timer_interrupt(int_flag, int_queue):
    while True:
        time.sleep(0.1)  # 0.1秒待機
        if int_flag.value:
            int_queue.put(0)

def keyboard_listener(fd, key_queues, vc_switch_queue, active_vc_shared):
    termios.tcflush(fd, termios.TCIFLUSH)
    tty.setcbreak(fd)

    awaiting_digit = False  # 直前に Ctrl-] を受けたか？
    while True:
        chb = os.read(fd, 1)
        if not chb:
            continue
        ch = chb.decode(errors='ignore')
        if awaiting_digit:
            awaiting_digit = False
            if ch in ('0', '1', '2', '3'):
                vc_idx = ord(ch) - ord('0')
                vc_switch_queue.put(vc_idx)
                active_vc_shared.value = vc_idx
                # 切り替えキーはOSに渡さない
                continue
            else:
                # 切り替えキー以外は無視
                continue
        if ch == '\x1d':  # Ctrl-]が押された
            awaiting_digit = True
            continue
        # 通常キーはそのままOSに
        key_queues[active_vc_shared.value].put(ch)

if __name__ == '__main__':

    # プログラムをロード
    try:
        with open("os.bin", "rb") as file:
            prog = file.read()
            memory[0:len(prog)] = prog
    except:
        vc_write("OSを読み込めませんでした。\n")
        sys.exit()

    try:
        mp.set_start_method('fork')
    except RuntimeError:
        pass  # 既に設定済みなら無視

    fd = sys.stdin.fileno()
    old_attr = termios.tcgetattr(fd)

    # --- Ctrl+\ (SIGQUIT) を無効化する：VQUIT を「未設定」に ---
    attrs = old_attr
    posix_vdisable = getattr(termios, '_POSIX_VDISABLE', 0)
    try:
        attrs[6][termios.VQUIT] = posix_vdisable  # c_cc[VQUIT] を無効化
    except AttributeError:
        # 環境によっては VQUIT が無い場合もあるので無視
        pass
    termios.tcsetattr(fd, termios.TCSANOW, attrs)

    timer_proc = mp.Process(target=timer_interrupt, args=(int_flag, int_queue,))
    timer_proc.start()

    key_proc = mp.Process(target=keyboard_listener, args=(fd, key_queues, vc_switch_queue, active_vc_shared))
    key_proc.start()

    # CPUを実行
    try:
        run()
    finally:
        timer_proc.terminate()
        key_proc.terminate()
        timer_proc.join()
        key_proc.join()
        termios.tcsetattr(fd, termios.TCSADRAIN, old_attr)
