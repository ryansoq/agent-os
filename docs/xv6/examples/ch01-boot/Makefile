all: boot.bin

boot.bin: boot.S
	as --32 -o boot.o boot.S
	ld -m elf_i386 -Ttext 0x7c00 --oformat binary -o boot.bin boot.o

run: boot.bin
	qemu-system-i386 -drive format=raw,file=boot.bin -nographic

clean:
	rm -f boot.o boot.bin
