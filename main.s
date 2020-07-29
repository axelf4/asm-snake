.intel_syntax noprefix

.section .rodata
Hello: .ascii "Hello world!\n"
Hello.len = . - Hello

.global _start

F_SETFL = 4 /* Set file status flags. */
O_RDONLY = 00
O_NONBLOCK = 04000
STDIN = 0
STDOUT = 1

SC_READ = 0x00
SC_IOCTL = 16

TCGETS = 0x00005401
TCSETS = 0x00005402

# termios.h
ICANON = 0000002 # Canonical input (erase and kill processing)
ECHO = 0000010 # Enable echo
NCCS = 32 # Number of control characters
VTIME = 5
VMIN = 6
/*
struct termios {
	tcflag_t c_iflag; // 4 bytes
	tcflag_t c_oflag; // 4 bytes
	tcflag_t c_cflag; // 4 bytes
	tcflag_t c_lflag; // 4 bytes => 16 bytes
	cc_t c_cc[NCCS]; // 32 bytes => 48
	speed_t c_ispeed; // 4 bytes
	speed_t c_ospeed; // 4 bytes => 56 + 4 bytes padding = 60
};
*/
TERMIOS_SIZE = 60

.macro set_stdin_nonblock
movq rax, 72 # Use the fcntl syscall
movq rdi, STDIN
movq rsi, F_SETFL
movq rdx, O_RDONLY | O_NONBLOCK
syscall
.endm

.text
_start:
	# set_stdin_nonblock
	# Setup terminal
	sub rsp, TERMIOS_SIZE
	movq rax, SC_IOCTL
	movq rdi, STDIN
	movq rsi, TCGETS
	leaq rdx, [rsp]
	syscall

	and dword ptr [rsp+12], ~(ICANON | ECHO) # Set local modes

	# Write new
	movq rax, SC_IOCTL
	movq rdi, STDIN
	movq rsi, TCSETS
	leaq rdx, [rsp]
	syscall

	# Read from stdin
	sub rsp, 1 # Allocate 1 byte on stack
	movq rax, SC_READ # Use the read syscall
	movq rdi, STDIN # Read
	leaq rsi, [rsp] # Read to stack
	movq rdx, 1 # Read single byte
	syscall

	xor ebx, ebx # zero edx

	loop_start:

	# write(1, Hello, 13)
	movq rax, 1 # use the write syscall
	movq rdi, STDOUT
	leaq rsi, Hello # use string Hello
	# movq rsi, OFFSET FLAT: Hello
	movq rdx, Hello.len # specify nr of characters
	# Clobbers %rcx and %r11, and return value %rax
	syscall

	add ebx, 1
	cmp ebx, 3
	jl loop_start

	# xor eax, eax

	movq rax, 60 # _exit syscall
	movq rdi, 0
	syscall
