# 最小 x86 bootloader：Real Mode → Protected Mode → 印 "Hi"

.code16
.globl _start
_start:
  cli
  xorw    %ax, %ax
  movw    %ax, %ds
  movw    %ax, %es
  movw    %ax, %ss
  lgdt    gdtdesc
  movl    %cr0, %eax
  orl     $0x1, %eax
  movl    %eax, %cr0
  ljmp    $0x08, $pm_start

.code32
pm_start:
  movw    $0x10, %ax
  movw    %ax, %ds
  movw    %ax, %es
  movw    %ax, %ss

  # VGA text buffer
  movb    $'H', 0xB8000
  movb    $0x0A, 0xB8001
  movb    $'i', 0xB8002
  movb    $0x0A, 0xB8003

  # Serial port (COM1)
  movw    $0x3F8, %dx
  movb    $'H', %al
  outb    %al, %dx
  movb    $'i', %al
  outb    %al, %dx
  movb    $'\r', %al
  outb    %al, %dx
  movb    $'\n', %al
  outb    %al, %dx

spin:
  hlt
  jmp     spin

.p2align 2
gdt:
  .quad 0
  .quad 0x00CF9A000000FFFF
  .quad 0x00CF92000000FFFF

gdtdesc:
  .word (gdtdesc - gdt - 1)
  .long gdt

.fill 510 - (. - _start), 1, 0
.word 0xAA55
