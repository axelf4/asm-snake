# Snake game in x86-64 assembly for Linux
# Copyright (C) 2022  Axel Forsman
.intel_syntax noprefix

SYS_read = 0x00
SYS_write = 1
SYS_ioctl = 16
SYS_exit = 60
SYS_nanosleep = 0x23
SYS_getrandom = 0x13e

STDIN = 0
STDOUT = 1

TCGETS = 0x00005401
TCSETS = 0x00005402
# termios.h
ICANON = 0000002 # Canonical input (erase and kill processing)
ECHO = 0000010 # Enable echo
VTIME = 5 # (0.1 second granularity)
VMIN = 6
/*
struct termios {
	tcflag_t c_iflag; // 4 bytes
	tcflag_t c_oflag; // 4 bytes
	tcflag_t c_cflag; // 4 bytes
	tcflag_t c_lflag; // 4 bytes
	cc_t c_cc[NCCS]; // 32 bytes
	speed_t c_ispeed; // 4 bytes
	speed_t c_ospeed; // 4 bytes => 56 + 4 bytes padding = 60
};
*/
TERMIOS_SIZE = 60

MILLI_TO_NANO = 1000000

.macro const_itoa n
	.if \n / 10
	const_itoa "(\n / 10)"
	.endif
	.byte '0' + \n % 10
.endm

# write(stdout, str, len)
.macro write str, len
	mov eax, SYS_write # use the write syscall
	mov edi, STDOUT
	lea rsi, \str
	mov rdx, \len # specify nr of characters
	# Clobbers %rcx and %r11, and return value %rax
	syscall
.endm

.macro sleep nanoseconds=0, seconds=0
	pushq \nanoseconds
	pushq \seconds
	mov eax, SYS_nanosleep
	mov rdi, rsp
	xor esi, esi # rem=NULL
	syscall
	add rsp, 2 * 8 # Pop two qwords from stack
.endm

# Writes the digits of the given positive integer.
#
# Clobbers ax, cx, dx, si and r11.
.macro itoa n=0 l=0
	# First count the number of digits
	mov ecx, \n
	lzcnt edx, ecx
	mov eax, 32 + 1; sub eax, edx
	mov edx, 1233; mul edx
	shr eax, 12; inc eax

	xchg eax, ecx # Write n to ax and count down digits with cx
	mov r11d, ecx # Store #digits in r11
	\l :
	mov edx, eax
	mov esi, 0xCCCCCCCD; imul rax, rsi; shr rax, 35 # Div10
	lea esi, [rax+rax*4-'0'/2] ; add esi, esi # Set esi to 10*eax - '0'
	sub edx, esi # Calc remainder
	# Quotient is stored in eax, and digit in edx

	mov byte ptr [rdi+rcx-1], dl
	dec ecx; jnz \l\()b

	add rdi, r11
.endm

WIDTH = 32
HEIGHT = 16
INITIAL_X = 20
INITIAL_Y = 10

SEED_SIZE = 4
DRAW_BUF_SIZE = 48
NUM_SEGMENTS = 128 # The maximum number of segments
SEGMENT_BYTES = 8
SNAKE_OFFSET = TERMIOS_SIZE + SEED_SIZE + DRAW_BUF_SIZE
APPLE_DATA_SIZE = 8
APPLE_OFFSET = SNAKE_OFFSET + NUM_SEGMENTS * SEGMENT_BYTES

# Generates a random number.
#
# Output in ax. Clobbers cx.
.macro rand
	mov eax, [rsp+TERMIOS_SIZE] # Store current seed in ax
	mov ecx, 0x8088405; mul ecx; inc eax
	mov [rsp+TERMIOS_SIZE], eax
.endm

.macro rand_apple_pos
	rand
	and eax, 0x0F001F; add eax, 2 | 2 << 16 # Put in ranges
	mov [rsp+APPLE_OFFSET], ax
	shr eax, 16; mov [rsp+APPLE_OFFSET+4], eax
.endm

.section .rodata
initialOutput:
	# Clear and hide cursor
	.ascii "\033[?25l\033[2J\033[;H╔Score: "
	.rept WIDTH-7
	.ascii "═" 
	.endr
	.ascii "╗"
	.rept HEIGHT
	.ascii "\033[B\033[D║"
	.endr
	.ascii "\033[2;H"
	.rept HEIGHT
	.ascii "║\n"
	.endr
	.ascii "╚"
	.rept WIDTH
	.ascii "═"
	.endr
	.ascii "╝"
initialOutput.len = . - initialOutput
finalOutput:
	.ascii "\033["
	const_itoa (HEIGHT+2)
	# Show cursor
	.ascii ";2HGame over!\n\033[?25h"
finalOutput.len = . - finalOutput

.global _start
.text
_start:
	# Allocate space on stack
	sub rsp, TERMIOS_SIZE + SEED_SIZE + DRAW_BUF_SIZE + NUM_SEGMENTS * SEGMENT_BYTES + APPLE_DATA_SIZE

	# Setup terminal
	mov rax, SYS_ioctl
	mov rdi, STDIN
	mov rsi, TCGETS
	lea rdx, [rsp+TERMIOS_SIZE]
	syscall

	# Make copy of termios struct
	mov rax, [rsp+TERMIOS_SIZE+48]
	movdqu xmm0, [rsp+TERMIOS_SIZE]
	movdqu xmm1, [rsp+TERMIOS_SIZE+16]
	movdqu xmm2, [rsp+TERMIOS_SIZE+32]
	mov [rsp+48], rax
	mov eax, [rsp+TERMIOS_SIZE+56]
	movups [rsp], xmm0
	movups [rsp+16], xmm1
	movups [rsp+32], xmm2
	mov [rsp+56], eax

	and dword ptr [rsp+TERMIOS_SIZE+12], ~(ICANON | ECHO) # Set local modes
	.if VMIN != VTIME + 1
	.err
	.endif
	mov word ptr [rsp+TERMIOS_SIZE+17+VTIME], 0 # Set VMIN/VTIME to zero
	# Write new terminal settings (reusing old register values)
	mov rax, SYS_ioctl
	# mov rdi, STDIN
	.if TCSETS != TCGETS + 1
	.err
	.endif
	inc rsi
	# lea rdx, [rsp+TERMIOS_SIZE]
	syscall

	write initialOutput, initialOutput.len

	# Get RNG seed
	mov rax, SYS_getrandom
	lea rdi, [rsp+TERMIOS_SIZE]
	mov rsi, SEED_SIZE
	xor edx, edx # No flags
	syscall

	mov r14d, 1 # Store num segments in r14
	xor r9d, r9d # Store head segment index in r9
	xor r12d, r12d # Store direction in r12

	mov dword ptr [rsp+SNAKE_OFFSET+0*SEGMENT_BYTES], INITIAL_X # x-coord of initial segment
	mov dword ptr [rsp+SNAKE_OFFSET+0*SEGMENT_BYTES+4], INITIAL_Y # y-coord of initial segment
	# Place initial apple in front of snake to only have to randomize
	# apple positions below.
	mov dword ptr [rsp+APPLE_OFFSET], INITIAL_X
	mov dword ptr [rsp+APPLE_OFFSET+4], INITIAL_Y-1

	main_loop:
	# Read from stdin
	read_loop: # Loop while still has type-ahead
	mov rax, SYS_read # Use the read syscall
	mov rdi, STDIN # Read from stdin
	lea rsi, [rsp-1] # Read to stack
	mov rdx, 1 # Read single byte
	syscall
	# If actually read a byte: Repeat
	test eax, eax # Cmp return value of read()
	jnz read_loop
	mov al, [rsp-1]

	mov ecx, r12d
	cmp eax, 'w'; jne 0f
	mov ecx, 0; jmp 1f
	0: cmp eax, 'a'; jne 0f
	mov ecx, 1; jmp 1f
	0: cmp eax, 's'; jne 0f
	mov ecx, 2; jmp 1f
	0: cmp eax, 'd'; jne 1f
	mov ecx, 3
	1:
	mov eax, ecx
	xor eax, r12d; bt eax, 0; cmovc r12d, ecx

	# Store pos of old head in r8/r10
	mov r8d, [rsp+SNAKE_OFFSET+SEGMENT_BYTES*r9]
	mov r10d, [rsp+SNAKE_OFFSET+SEGMENT_BYTES*r9+4]
	# Increment current head index, wrapping if necessary
	inc r9d
	cmp r9d, r14d; jb 0f
	xor r9d, r9d
	0:

	# Delete char of last tail
	lea rdi, [rsp+TERMIOS_SIZE+SEED_SIZE]
	mov word ptr [rdi], 0x1B | '[' << 8
	add rdi, 2
	itoa "(dword ptr [rsp+SNAKE_OFFSET+SEGMENT_BYTES*r9+4])" # y-coord
	mov byte ptr [rdi], '\;'
	inc rdi
	itoa "(dword ptr [rsp+SNAKE_OFFSET+SEGMENT_BYTES*r9])" # x-coord
	mov word ptr [rdi], 'H' | ' ' << 8
	add rdi, 2

	# Compute new head position
	cmp r12d, 2; je 2f; ja 3f
	cmp r12d, 0; jne 1f
	dec r10d; jmp 0f
	1: dec r8d; jmp 0f
	2: inc r10d; jmp 0f
	3: inc r8d; jmp 0f
	0:
	# Write new pos of snake head
	mov [rsp+SNAKE_OFFSET+SEGMENT_BYTES*r9], r8d
	mov [rsp+SNAKE_OFFSET+SEGMENT_BYTES*r9+4], r10d

	# Check for collision against boundaries
	cmp r8d, 2; jb exit
	cmp r10d, 2; jb exit
	cmp r8d, WIDTH+1; ja exit
	cmp r10d, HEIGHT+1; ja exit
	# Check for collisions
	mov ecx, r9d
	check_collision_loop:
	inc ecx
	cmp ecx, r14d; jb 0f
	xor ecx, ecx # Wrap around index
	0:
	cmp ecx, r9d; je 0f # If checked againts all other segments already: Exit

	cmp [rsp+SNAKE_OFFSET+SEGMENT_BYTES*rcx], r8d; jne 1f
	cmp [rsp+SNAKE_OFFSET+SEGMENT_BYTES*rcx+4], r10d; jne 1f
	jmp exit # Collision!
	1:
	jmp check_collision_loop
	0:

	cmp r8d, [rsp+APPLE_OFFSET]; jne 0f
	cmp r10d, [rsp+APPLE_OFFSET+4]; jne 0f
	# Ate apple: Write position of next segment
	rand_apple_pos
	# "Old" cell of new segment will be cleared: Set it outside of screen
	mov qword ptr [rsp+SNAKE_OFFSET+SEGMENT_BYTES*r14], WIDTH+3

	# Write new score
	mov dword ptr [rdi], 0x1B | '[' << 8 | '\;' << 16 | '9' << 24
	mov byte ptr [rdi+4], 'H'
	add rdi, 5
	itoa r14d, l=1

	inc r14d # Increment segment count
	0:

	mov word ptr [rdi], 0x1B | '[' << 8
	add rdi, 2
	itoa [rsp+APPLE_OFFSET+4] # y-coord
	mov byte ptr [rdi], '\;'
	inc rdi
	itoa [rsp+APPLE_OFFSET] # x-coord
	# Note: This also begins printing the new head
	mov dword ptr [rdi], 'H' | 'o' << 8 | 0x1B << 16 | '[' << 24
	add rdi, 4

	# Draw new head position
	itoa "(dword ptr [rsp+SNAKE_OFFSET+SEGMENT_BYTES*r9+4])" # y-coord
	mov byte ptr [rdi], '\;'
	inc rdi
	itoa "(dword ptr [rsp+SNAKE_OFFSET+SEGMENT_BYTES*r9])" # x-coord
	mov word ptr [rdi], 'H' | '#' << 8
	add rdi, 2

	lea rdx, [rdi-TERMIOS_SIZE-SEED_SIZE]; sub rdx, rsp
	write [rsp+TERMIOS_SIZE+SEED_SIZE], rdx # Flush draw buffer

	# Move vertically at half speed (due to character aspect ratio)
	bt r12d, 0; sbb eax, eax # Make eax all 1/0:s depending on dir
	and eax, -MILLI_TO_NANO*300/2
	add eax, MILLI_TO_NANO*300
	sleep nanoseconds=rax
	jmp main_loop

	exit:
	write finalOutput, finalOutput.len
	# Restore previous terminal settings
	mov rax, SYS_ioctl
	mov rdi, STDIN
	mov rsi, TCSETS
	lea rdx, [rsp]
	syscall

	mov rax, SYS_exit
	xor edi, edi # Exit with code 0
	syscall
