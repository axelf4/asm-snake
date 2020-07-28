all: main

main: main.s Makefile
	gcc -o $@ -m64 -nostdlib -no-pie -O0 -g $<

.PHONY: all
