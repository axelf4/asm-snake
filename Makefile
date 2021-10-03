all: main

main: main.s Makefile
	# gcc -Wa,-Os -o $@ -m64 -nostdlib -no-pie -g -s $<
	gcc -m64 -nostdlib -static -s -Wa,-Os -o $@ \
		-Wl,--nmagic,--build-id=none $<

.PHONY: all
