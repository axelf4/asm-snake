.intel_syntax noprefix

.section .rodata
Hello: .ascii "Hello world!\n"
Hello.len = . - Hello

clearScreen: .ascii "\033[2J"
clearScreen.len = . - clearScreen

.global _start

F_SETFL = 4 /* Set file status flags. */
O_RDONLY = 00
O_NONBLOCK = 04000
STDIN = 0
STDOUT = 1

SYS_read = 0x00
SYS_write = 1
SYS_ioctl = 16
SYS_exit = 60
SYS_nanosleep = 0x23

TCGETS = 0x00005401
TCSETS = 0x00005402

# termios.h
ICANON = 0000002 # Canonical input (erase and kill processing)
ECHO = 0000010 # Enable echo
NCCS = 32 # Number of control characters
VTIME = 5 # (0.1 second granularity)
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

MILLI_TO_NANO = 1000000

# write(stdout, str, len)
.macro write str, len
	mov eax, SYS_write # use the write syscall
	mov edi, STDOUT
	mov rsi, offset flat: \str
	mov rdx, \len # specify nr of characters
	# Clobbers %rcx and %r11, and return value %rax
	syscall
.endm

.macro sleep duration=1
	pushq MILLI_TO_NANO * 0 # Nanoseconds
	pushq \duration # Seconds
	mov eax, SYS_nanosleep # use the nanosleep syscall
	mov rdi, rsp
	xor esi, esi # rem=NULL (writing 32-bit register zeros upper 32 bits)
	syscall
	add rsp, 2 * 8 # Pop two qwords from stack
.endm

.macro set_stdin_nonblock
mov eax, 72 # Use the fcntl syscall
mov rdi, STDIN
mov rsi, F_SETFL
mov rdx, O_RDONLY | O_NONBLOCK
syscall
.endm

.text
_start:
	# set_stdin_nonblock
	# Setup terminal
	sub rsp, TERMIOS_SIZE
	movq rax, SYS_ioctl
	movq rdi, STDIN
	movq rsi, TCGETS
	leaq rdx, [rsp]
	syscall

	and dword ptr [rsp+12], ~(ICANON | ECHO) # Set local modes
	mov byte ptr [rsp+17+VMIN], 0
	mov byte ptr [rsp+17+VTIME], 0

	# Write new
	movq rax, SYS_ioctl
	movq rdi, STDIN
	movq rsi, TCSETS
	leaq rdx, [rsp]
	syscall

	loop:

	# Read from stdin
	# sub rsp, 4 # Allocate 1 byte on stack
	push 0
	read_loop: # Loop while still has type-ahead
	mov eax, SYS_read # Use the read syscall
	mov edi, STDIN # Read from stdin
	mov rsi, rsp # Read to stack
	mov rdx, 1 # Read single byte
	syscall
	# If actually read a byte: Repeat
	cmp eax, 0 # Cmp return value of read()
	jne read_loop
	pop rax

	sleep 1

	write Hello, Hello.len

	jmp loop

	xor ebx, ebx # zero edx

	loop_start:

	write clearScreen, clearScreen.len
	write Hello, Hello.len

	add ebx, 1
	cmp ebx, 3
	jl loop_start

	movq rax, SYS_exit # _exit syscall
	movq rdi, 0 # Exit code
	syscall
