.intel_syntax noprefix

.section .rodata
clearAndHideCursor: .ascii "\033[?25l\033[2J"
clearAndHideCursor.len = . - clearAndHideCursor

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
SYS_getrandom = 0x13e

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
.macro itoa n=0
	# First count the number of digits
	mov r8d, \n
	lzcnt edx, r8d
	mov ax, 32 + 1
	sub ax, dx
	mov edx, 1233; mul edx
	shr rax, 12
	# Now ax=#digits-1, r8=original number. Proceed to write digits:

	mov r11d, eax # Write #digits-1 to r11
	mov eax, r8d # Write number to eax

	mov ecx, r11d # Count down the digits with ecx
	0:
	mov edx, eax
	mov r8d, 0xCCCCCCCD; imul rax, r8; shr rax, 35 # Div10
	lea r8d, [rax + rax * 4 - '0'/2] ; add r8d, r8d # Set r8d to 10*eax - '0'
	sub edx, r8d # Calc remainder
	# Quotient is stored in eax, and digit in edx

	mov byte ptr [rdi+rcx], dl
	sub ecx, 1; jae 0b # Decrement counter, and loop again if ecx≥1

	add rdi, r11; inc rdi
.endm

SEED_SIZE = 4

NUM_SEGMENTS = 64 # The maximum number of segments
SEGMENT_BYTES = 8
SNAKE_OFFSET = TERMIOS_SIZE + SEED_SIZE
APPLE_DATA_SIZE = 8
APPLE_OFFSET = SNAKE_OFFSET + 4 + NUM_SEGMENTS * SEGMENT_BYTES

# Generates a random number.
#
# Output in eax. Clobbers rcx.
.macro rand
	mov eax, [rsp+TERMIOS_SIZE] # Store current seed in rax
	mov ecx, 0x8088405; mul ecx; inc eax
	mov [rsp+TERMIOS_SIZE], eax
	and eax, 0xF; inc eax # Put in range [1, 16]
.endm

.macro rand_apple_pos
	rand
	mov [rsp+APPLE_OFFSET], eax
	rand
	mov [rsp+APPLE_OFFSET+4], eax
.endm

.text
_start:
	# Allocate space on stack
	sub rsp, TERMIOS_SIZE + SEED_SIZE + /* segmentCount */ 4 + NUM_SEGMENTS * SEGMENT_BYTES + APPLE_DATA_SIZE

	# set_stdin_nonblock
	# Setup terminal
	mov rax, SYS_ioctl
	mov rdi, STDIN
	mov rsi, TCGETS
	lea rdx, [rsp]
	syscall

	and dword ptr [rsp+12], ~(ICANON | ECHO) # Set local modes
	mov byte ptr [rsp+17+VMIN], 0
	mov byte ptr [rsp+17+VTIME], 0

	# Write new terminal settings
	mov rax, SYS_ioctl
	mov rdi, STDIN
	mov rsi, TCSETS
	lea rdx, [rsp]
	syscall

	# Get RNG seed
	mov rax, SYS_getrandom
	lea rdi, [rsp+TERMIOS_SIZE]
	mov rsi, SEED_SIZE
	mov rdx, 0 # No flags
	syscall

	rand_apple_pos # Generate initial apple position

	write clearAndHideCursor, clearAndHideCursor.len

	mov r12d, 0 # Store direction in r12
	mov dword ptr [rsp+SNAKE_OFFSET], 1 # Start with single segment
	mov dword ptr [rsp+SNAKE_OFFSET+4], 0 # Current segment head

	mov dword ptr [rsp+SNAKE_OFFSET+8+0*SEGMENT_BYTES], 20 # x-coord of initial segment
	mov dword ptr [rsp+SNAKE_OFFSET+8+0*SEGMENT_BYTES+4], 10 # y-coord of initial segment

	main_loop:

	# Read from stdin
	push 0 # Allocate 1 byte on stack
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

	# TODO do not allow turning 180 degrees
	cmp rax, 'w'; jne 0f
	mov r12d, 0; jmp 1f
	0: cmp rax, 'a'; jne 0f
	mov r12d, 1; jmp 1f
	0: cmp rax, 's'; jne 0f
	mov r12d, 2; jmp 1f
	0: cmp rax, 'd'; jne 1f
	mov r12d, 3; jmp 1f
	1:

	mov r14d, [rsp+SNAKE_OFFSET] # Store current num segments in r14
	mov r13d, [rsp+SNAKE_OFFSET+4] # Store old head segment index in r13
	mov r9d, r13d # Store tail/new head segment index in r9
	# Increment current head index, wrapping if necessary
	inc r9d
	cmp r9d, [rsp+SNAKE_OFFSET]; jb 0f
	xor r9d, r9d
	0:
	# Write current head index back to stack
	mov [rsp+SNAKE_OFFSET+4], r9d

	# Delete char of last tail
	DRAW_BUF_SIZE = 32
	sub rsp, DRAW_BUF_SIZE
	mov rdi, rsp
	mov word ptr [rdi], 0x1B | '[' << 8
	add rdi, 2
	itoa "(dword ptr [rsp+DRAW_BUF_SIZE+SNAKE_OFFSET+8+SEGMENT_BYTES*r9+4])" # y-coord
	mov byte ptr [rdi], '\;'
	inc rdi
	itoa "(dword ptr [rsp+DRAW_BUF_SIZE+SNAKE_OFFSET+8+SEGMENT_BYTES*r9])" # x-coord
	mov word ptr [rdi], 'H' | ' ' << 8
	add rdi, 2
	mov rdx, rdi; sub rdx, rsp
	write [rsp], rdx
	add rsp, DRAW_BUF_SIZE # Dealloc stack

	# Store pos of old head in r8/r10
	mov r8d, [rsp+SNAKE_OFFSET+8+SEGMENT_BYTES*r13]
	mov r10d, [rsp+SNAKE_OFFSET+8+SEGMENT_BYTES*r13+4]
	# Compute new head position
	cmp r12d, 0; jne 0f
	dec r10d; jmp 1f
	0: cmp r12d, 1; jne 0f
	dec r8d; jmp 1f
	0: cmp r12d, 2; jne 0f
	inc r10d; jmp 1f
	0: cmp r12d, 3; jne 1f
	inc r8d; jmp 1f
	1:
	# Write new pos of snake head
	mov [rsp+SNAKE_OFFSET+8+SEGMENT_BYTES*r9], r8d
	mov [rsp+SNAKE_OFFSET+8+SEGMENT_BYTES*r9+4], r10d

	# Check for collision against boundaries
	test r8d, r8d; jz exit
	test r10d, r10d; jz exit
	# Check for collisions
	mov ecx, r9d
	check_collision_loop:
	inc ecx
	cmp ecx, [rsp+SNAKE_OFFSET]; jb 0f
	xor ecx, ecx  # If i == #segment, set i to zero
	0:

	# If checked againts all other segments already (i==segment_head): Exit
	cmp ecx, r9d; je 1f

	cmp [rsp+SNAKE_OFFSET+8+SEGMENT_BYTES*rcx], r8d; jne 0f
	cmp [rsp+SNAKE_OFFSET+8+SEGMENT_BYTES*rcx+4], r10d; jne 0f
	# Collision!
	jmp exit
	0:

	jmp check_collision_loop
	1:

	cmp ecx, r9d; jne check_collision_loop

	cmp r8d, [rsp+APPLE_OFFSET]; jne 0f
	cmp r10d, [rsp+APPLE_OFFSET+4]; jne 0f
	# Ate apple: Write position of next segment
	rand_apple_pos
	mov r8d, [rsp+APPLE_OFFSET]
	mov [rsp+SNAKE_OFFSET+8+SEGMENT_BYTES*r14], r8d
	mov r10d, [rsp+APPLE_OFFSET+4]
	mov [rsp+SNAKE_OFFSET+8+SEGMENT_BYTES*r14+4], r10d
	inc dword ptr [rsp+SNAKE_OFFSET] # Increment segment count
	0:

	DRAW_BUF_SIZE = 32
	sub rsp, DRAW_BUF_SIZE
	mov rdi, rsp

	mov word ptr [rdi], 0x1B | '[' << 8
	add rdi, 2
	itoa [rsp+DRAW_BUF_SIZE+APPLE_OFFSET+4] # y-coord
	mov byte ptr [rdi], '\;'
	inc rdi
	itoa [rsp+DRAW_BUF_SIZE+APPLE_OFFSET] # x-coord
	mov word ptr [rdi], 'H' | 'o' << 8
	add rdi, 2

	# Draw new head position
	mov word ptr [rdi], 0x1B | '[' << 8
	add rdi, 2
	itoa "(dword ptr [rsp+DRAW_BUF_SIZE+SNAKE_OFFSET+8+SEGMENT_BYTES*r9+4])" # y-coord
	mov byte ptr [rdi], '\;'
	inc rdi
	itoa "(dword ptr [rsp+DRAW_BUF_SIZE+SNAKE_OFFSET+8+SEGMENT_BYTES*r9])" # x-coord
	mov word ptr [rdi], 'H' | '#' << 8
	add rdi, 2

	mov rdx, rdi; sub rdx, rsp
	write [rsp], rdx
	add rsp, DRAW_BUF_SIZE # Dealloc stack

	# Move vertically at half speed (due to character aspect ratio)
	mov rax, MILLI_TO_NANO * 150
	bt r12, 0; jc 0f
	sal rax, 1
	0:
	sleep nanoseconds=rax

	jmp main_loop

	exit:
	mov rax, SYS_exit
	mov rdi, 0 # Exit code
	syscall
