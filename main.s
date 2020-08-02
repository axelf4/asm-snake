.intel_syntax noprefix

.section .rodata
Hello: .ascii "\x1B[0010;10HHello world!\n"
Hello.len = . - Hello

hideCursor: .ascii "\033[?25l"
hideCursor.len = . - hideCursor
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

MILLI_TO_NANO = 1000000

.macro sleep nanoseconds=0, seconds=0
	pushq \nanoseconds
	pushq \seconds
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

# Clobbers: rax, rcx, rdx, r8, r11
# Note: n has to be positive
.macro itoa n=3
	# First count the number of digits
	mov r8d, \n
	lzcnt r11d, r8d
	mov ax, 32 + 1
	sub ax, r11w
	mov edx, 1233; mul edx
	shr rax, 12
	# Now ax=#digits-1, r8=original number. Let's write the digits:

	mov r11d, eax # Write #digits-1 to r11
	mov eax, r8d # Write number to eax

	mov ecx, r11d # Count down the digits with ecx
	0:
	xor edx, edx
	mov r8, 10
	div r8d # TODO Optimize away slow div
	# Quotient is stored in eax, and remainder in edx

	add dl, '0'
	mov byte ptr [rdi+rcx], dl
	# Decrement counter, and loop again if ecx ≥ 1
	sub ecx, 1; jae 0b

	add rdi, r11
	inc rdi
.endm

NUM_SEGMENTS = 16
SEGMENT_BYTES = 8

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

	# Write new terminal settings
	movq rax, SYS_ioctl
	movq rdi, STDIN
	movq rsi, TCSETS
	leaq rdx, [rsp]
	syscall

	# write hideCursor, hideCursor.len

	mov r12d, 0 # Store direction in r12
	# Allocate storage for snake on stack
	sub rsp, /* segmentCount */ 4 + NUM_SEGMENTS * SEGMENT_BYTES
	mov dword ptr [rsp], 3 # Start with single segment
	mov dword ptr [rsp+4], 2 # Current segment head

	mov dword ptr [rsp+8+0*SEGMENT_BYTES], 20 # x-coord of first segment
	mov dword ptr [rsp+8+0*SEGMENT_BYTES+4], 10 # y-coord of first segment
	mov dword ptr [rsp+8+1*SEGMENT_BYTES], 21 # x-coord of 2nd segment
	mov dword ptr [rsp+8+1*SEGMENT_BYTES+4], 10 # y-coord of 2nd segment
	mov dword ptr [rsp+8+2*SEGMENT_BYTES], 22 # x-coord of 3rd segment
	mov dword ptr [rsp+8+2*SEGMENT_BYTES+4], 10 # y-coord of 3rd segment

	main_loop:

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

	cmp rax, 'w'; jne 0f
	mov r12d, 0; jmp 1f
	0: cmp rax, 'a'; jne 0f
	mov r12d, 1; jmp 1f
	0: cmp rax, 's'; jne 0f
	mov r12d, 2; jmp 1f
	0: cmp rax, 'd'; jne 1f
	mov r12d, 3; jmp 1f
	1:

	mov r9d, [rsp+4] # Store current segment index in r9
	# Store pos of current head in r8/r10
	mov r8d, [rsp+8+SEGMENT_BYTES*r9]
	mov r10d, [rsp+8+SEGMENT_BYTES*r9+4]

	cmp r12d, 0; jne 0f
	dec r10d; jmp 1f
	0: cmp r12d, 1; jne 0f
	dec r8d; jmp 1f
	0: cmp r12d, 2; jne 0f
	inc r10d; jmp 1f
	0: cmp r12d, 3; jne 1f
	inc r8d; jmp 1f
	1:

	# Increment current head index, wrapping if necessary
	inc r9d
	cmp r9d, [rsp]; jb 0f
	xor r9d, r9d
	0:
	# Write current head index back to stack
	mov [rsp+4], r9d

	# Write new pos of snake head
	mov [rsp+8+SEGMENT_BYTES*r9], r8d
	mov [rsp+8+SEGMENT_BYTES*r9+4], r10d

	write clearScreen, clearScreen.len
	write Hello, Hello.len

	# Draw all segments
	draw_segment_loop:
	inc r9d
	cmp r9d, [rsp]; jb 0f
	xor r9d, r9d  # If i == #segment, set i to zero
	0:

	DRAW_BUF_SIZE = 32
	sub rsp, DRAW_BUF_SIZE
	mov rdi, rsp
	mov byte ptr [rdi], 0x1B
	mov byte ptr [rdi+1], '['
	add rdi, 2
	itoa "(dword ptr [rsp+DRAW_BUF_SIZE+8+SEGMENT_BYTES*r9+4])" # y-coord
	mov byte ptr [rdi], '\;'
	inc rdi
	itoa "(dword ptr [rsp+DRAW_BUF_SIZE+8+SEGMENT_BYTES*r9])" # x-coord
	mov byte ptr [rdi], 'H'
	add rdi, 1
	mov byte ptr [rdi], '#'
	add rdi, 1
	mov rdx, rdi; sub rdx, rsp
	write [rsp], rdx
	add rsp, DRAW_BUF_SIZE # Dealloc stack

	# If not drawn all segments already (i==segment_head): Loop again
	cmp r9d, [rsp+4]; jne draw_segment_loop

	# Move vertically at half speed (due to character aspect ratio)
	mov rax, MILLI_TO_NANO * 350 / 2
	bt r12, 0; jc 0f
	mov rax, MILLI_TO_NANO * 350
	0:

	sleep nanoseconds=rax

	jmp main_loop

	movq rax, SYS_exit # _exit syscall
	movq rdi, 0 # Exit code
	syscall
