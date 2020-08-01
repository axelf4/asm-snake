.intel_syntax noprefix

.section .rodata
Hello: .ascii "\x1B[0010;10HHello world!\n"
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
	# mov rsi, offset flat: \str
	lea rsi, \str
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

# Note: n has to be positive
.macro itoa n=3
	# First count the number of digits
	mov r8w, \n
	lzcnt r9w, r8w
	mov ax, 16 + 1
	sub ax, r9w
	mov r9, 1233
	mul r9
	shr rax, 12
	# Now ax=#digits-1, r8=original number. Let's write the digits:

	mov r9d, eax # Write #digits-1 to r9
	mov eax, r8d # Write number to eax

	mov ecx, r9d # Count down the digits with ecx
	0:
	xor edx, edx
	mov r10, 10
	div r10d # TODO Optimize away slow div
	# Quotient is stored in eax, and remainder in edx

	add dl, '0'
	mov byte ptr [rdi+rcx], dl
	# Decrement counter, and loop again if ecx ≥ 1
	sub ecx, 1; jae 0b

	add rdi, r9
	add rdi, 1
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

	write clearScreen, clearScreen.len
	write Hello, Hello.len

	sub rsp, 32
	mov rdi, rsp
	mov byte ptr [rdi], 0x1B
	mov byte ptr [rdi+1], '['
	add rdi, 2
	itoa 42
	mov byte ptr [rdi], '\;'
	add rdi, 1
	itoa 15
	mov byte ptr [rdi], 'H'
	add rdi, 1
	mov byte ptr [rdi], '#'
	add rdi, 1
	mov r8, rdi; sub r8, rsp
	write [rsp], r8
	add rsp, 32 # Dealloc stack

	sleep 1

	jmp loop

	movq rax, SYS_exit # _exit syscall
	movq rdi, 0 # Exit code
	syscall
