QEMU = qemu-system-i386

.PHONY: run clean

boot.img: boot.S
	gcc -m32 -nostdinc -c -o boot.o boot.S
	ld -m elf_i386 -Ttext 0x7C00 --oformat binary -o $@ boot.o

# 跑起來！按 Ctrl-A X 離開
run: boot.img
	$(QEMU) -nographic -drive file=boot.img,format=raw

clean:
	rm -f *.o *.img
