all: snake

snake: main.s Makefile
	gcc -m64 -nostdlib -s -o $@ \
		-Wa,-Os -Wl,--nmagic,--build-id=none $<

.PHONY: all
