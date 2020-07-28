.intel_syntax noprefix

.section .rodata
Hello: .ascii "Hello world!\n"

.global _start

.text
_start:
	xor ebx, ebx # zero edx

	loop_start:

	# write(1, Hello, 13)
	movq rax, 1 # use the write syscall
	movq rdi, 1 # write to stdout
	lea rsi, Hello # use string Hello
	# movq rsi, OFFSET FLAT: Hello
	movq rdx, 13 # write 14 characters
	# Clobbers %rcx and %r11, and return value %rax
	syscall

	add ebx, 1
	cmp ebx, 3
	jl loop_start

	# xor eax, eax

	movq rax, 60 # _exit syscall
	movq rdi, 0
	syscall
