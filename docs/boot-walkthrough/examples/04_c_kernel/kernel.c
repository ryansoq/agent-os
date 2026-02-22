// === 04: C Kernel ===
// 🔑 這就是 Linux start_kernel() 的極簡版！
// 🔑 這個 kernel 同時寫 VGA 記憶體和 Serial Port 來顯示文字
// 🔑 不依賴任何標準函式庫（沒有 printf、沒有 malloc）
//
// 🔑 從 Assembly 跳到 C，就像從「用螺絲刀手工組裝」到「用工廠自動化生產」
//     Assembly: 你親手搬每個 byte、設每個暫存器
//     C 語言: 編譯器幫你處理暫存器分配、stack 管理、函數呼叫
//     但前提是：有人先幫你把 stack 設好（boot.asm 的工作）

// ============================================================
// 🔑 Serial Port (COM1) — 直接跟硬體溝通
// 🔑 比喻：printf 像是寫信給郵局幫你寄
//     outb 像是你自己走到對方門口遞信
// ============================================================

#define COM1 0x3F8

static inline void outb(unsigned short port, unsigned char val) {
    __asm__ volatile ("outb %0, %1" : : "a"(val), "Nd"(port));
}

static inline unsigned char inb(unsigned short port) {
    unsigned char ret;
    __asm__ volatile ("inb %1, %0" : "=a"(ret) : "Nd"(port));
    return ret;
}

static void serial_init(void) {
    outb(COM1 + 1, 0x00);  // 關中斷
    outb(COM1 + 3, 0x80);  // DLAB
    outb(COM1 + 0, 0x03);  // 38400 baud
    outb(COM1 + 1, 0x00);
    outb(COM1 + 3, 0x03);  // 8N1
}

static void serial_putchar(char c) {
    while (!(inb(COM1 + 5) & 0x20));  // 等 transmit ready
    outb(COM1, c);
}

static void serial_print(const char *s) {
    while (*s) serial_putchar(*s++);
}

// ============================================================
// 🔑 VGA 文字模式
// ============================================================

// 🔑 VGA 文字模式的顏色定義
// 🔑 每個字元佔 2 bytes: [ASCII 字元][屬性 byte]
// 🔑 屬性格式: [背景色 4bit | 前景色 4bit]
enum vga_color {
    VGA_BLACK   = 0,    // 🔑 黑色
    VGA_BLUE    = 1,    // 🔑 藍色
    VGA_GREEN   = 2,    // 🔑 綠色
    VGA_CYAN    = 3,    // 🔑 青色
    VGA_RED     = 4,    // 🔑 紅色
    VGA_MAGENTA = 5,    // 🔑 洋紅色
    VGA_BROWN   = 6,    // 🔑 棕色
    VGA_LGRAY   = 7,    // 🔑 淺灰
    VGA_DGRAY   = 8,    // 🔑 深灰
    VGA_LBLUE   = 9,    // 🔑 亮藍
    VGA_LGREEN  = 10,   // 🔑 亮綠
    VGA_LCYAN   = 11,   // 🔑 亮青
    VGA_LRED    = 12,   // 🔑 亮紅
    VGA_PINK    = 13,   // 🔑 粉紅
    VGA_YELLOW  = 14,   // 🔑 黃色
    VGA_WHITE   = 15    // 🔑 白色
};

// 🔑 VGA 文字模式的螢幕大小
#define VGA_WIDTH  80   // 🔑 每行 80 個字元
#define VGA_HEIGHT 25   // 🔑 共 25 行

// 🔑 VGA buffer 的起始位址（固定在 0xB8000）
static volatile unsigned short *const VGA_BUFFER = (volatile unsigned short *)0xB8000;

// 🔑 建立 VGA entry：把字元和顏色組合成 16-bit 值
static inline unsigned short vga_entry(char c, unsigned char color) {
    return (unsigned short)c | ((unsigned short)color << 8);
    // 🔑 低 8 bit = ASCII 字元，高 8 bit = 顏色屬性
}

// 🔑 建立顏色屬性：前景色 + 背景色
static inline unsigned char vga_color(enum vga_color fg, enum vga_color bg) {
    return fg | (bg << 4);
    // 🔑 低 4 bit = 前景色，高 4 bit = 背景色
}

// 🔑 清除螢幕：用空白字元填滿整個 VGA buffer
static void clear_screen(unsigned char color) {
    for (int i = 0; i < VGA_WIDTH * VGA_HEIGHT; i++) {
        VGA_BUFFER[i] = vga_entry(' ', color);  // 🔑 每個位置寫入空白 + 顏色
    }
}

// 🔑 在指定位置印一行字串
static void print_at(const char *str, int row, int col, unsigned char color) {
    int offset = row * VGA_WIDTH + col;  // 🔑 計算 VGA buffer 中的 offset
    for (int i = 0; str[i] != '\0'; i++) {
        VGA_BUFFER[offset + i] = vga_entry(str[i], color);  // 🔑 逐字寫入
    }
}

// ============================================================
// 🔑 Kernel 主函數 — 一切從這裡開始！
// 🔑 boot.asm 設好 stack 後呼叫這個函數
// ============================================================
void kernel_main(void) {
    // === Serial Port 輸出（terminal 可見）===
    serial_init();
    serial_print("\r\n=== Agent OS Example 04: C Kernel ===\r\n");
    serial_print("Hello from C kernel! kernel_main() is running.\r\n");
    serial_print("We jumped from assembly to C successfully!\r\n");
    serial_print("VGA text mode: 80x25, direct memory at 0xB8000\r\n");
    serial_print("No printf, no stdlib -- just raw hardware access.\r\n");
    serial_print("System halted. Your kernel is alive!\r\n");

    // === VGA 輸出（圖形視窗可見）===
    // 🔑 設定顏色
    unsigned char title_color = vga_color(VGA_LGREEN, VGA_BLACK);   // 🔑 亮綠色標題
    unsigned char text_color = vga_color(VGA_WHITE, VGA_BLACK);     // 🔑 白色文字
    unsigned char highlight = vga_color(VGA_YELLOW, VGA_BLACK);     // 🔑 黃色重點

    // 🔑 清除螢幕
    clear_screen(text_color);

    // 🔑 印歡迎訊息
    print_at("=== Agent OS Boot Example 04: C Kernel ===", 0, 0, title_color);
    print_at("Hello from C kernel! This is kernel_main() speaking.", 2, 0, text_color);
    print_at("We jumped from assembly to C successfully!", 3, 0, text_color);
    print_at("VGA text mode: 80x25, direct memory at 0xB8000", 5, 0, highlight);
    print_at("No printf, no stdlib -- just raw hardware access.", 6, 0, highlight);

    // 🔑 印一條彩色的分隔線
    for (int i = 0; i < VGA_WIDTH; i++) {
        unsigned char rainbow = vga_color(i % 16, VGA_BLACK);  // 🔑 每個字元不同顏色
        VGA_BUFFER[8 * VGA_WIDTH + i] = vga_entry('=', rainbow);
    }

    print_at("System halted. Your kernel is alive!", 10, 0, text_color);

    // 🔑 無限迴圈 — kernel 永遠不應該 return
    while (1) {
        __asm__ volatile ("hlt");   // 🔑 HLT 指令讓 CPU 進入低功耗等待
    }
}
