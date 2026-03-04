# ============================================================
# 最小 x86 boot sector：印出 "Hello from x86!"
#
# BIOS 把這 512 bytes 載入到 0x7C00 執行
# CPU 處於 Real Mode，16-bit
# ============================================================

.code16
.globl start
start:
    cli                         # 關中斷

    # 清零段暫存器
    xorw    %ax, %ax
    movw    %ax, %ds
    movw    %ax, %es

    # 用 BIOS 中斷 INT 0x10 逐字印出訊息
    movw    $message, %si       # SI = 字串指標

print_loop:
    lodsb                       # AL = [SI], SI++
    orb     %al, %al           # AL == 0?
    jz      done                # 是 → 結束

    movb    $0x0e, %ah         # AH = 0x0E = teletype output
    int     $0x10              # BIOS 中斷：印一個字元
    jmp     print_loop

done:
    hlt                         # CPU 停機
    jmp     done

message:
    .asciz "Hello from x86 boot sector!\r\n"

# 填充到 510 bytes，加上 boot 簽名
.org 510
.word 0xAA55                    # BIOS 辨認的 boot 簽名（little-endian）
