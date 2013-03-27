; =============================================================================
; BareMetal -- a 64-bit OS written in Assembly for x86-64 systems
; Copyright (C) 2008-2013 Return Infinity -- see LICENSE.TXT
;
; COMMAND LINE INTERFACE
; =============================================================================

align 16
db 'DEBUG: CLI      '
align 16


os_command_line:
	mov rsi, prompt			; Prompt for input
	mov bl, 0x09			; Black background, Light Red text
	call os_output_with_color

	mov rdi, cli_temp_string
	mov rcx, 250			; Limit the input to 250 characters
	call os_input
	call os_print_newline		; The user hit enter so print a new line
	jrcxz os_command_line		; os_input_string stores the number of charaters received in RCX

	mov rsi, rdi
	call os_string_parse		; Remove extra spaces
	jrcxz os_command_line		; os_string_parse stores the number of words in RCX
	mov byte [cli_args], cl		; Store the number of words in the string

; Copy the first word in the string to a new string. This is the command/application to run
	xor rcx, rcx
	mov rsi, cli_temp_string
	mov rdi, cli_command_string
	push rdi			; Push the command string
nextbyte1:
	add rcx, 1
	lodsb
	cmp al, ' '			; End of the word
	je endofcommand
	cmp al, 0x00			; End of the string
	je endofcommand
	cmp rcx, 13			; More than 12 bytes
	je endofcommand
	stosb
	jmp nextbyte1
endofcommand:
	mov al, 0x00
	stosb				; Terminate the string

; At this point cli_command_string holds at least "a" and at most "abcdefgh.ijk"

	; Break the contents of cli_temp_string into individual strings
	mov rsi, cli_temp_string
	mov al, 0x20
	mov bl, 0x00
	call os_string_change_char

	pop rsi				; Pop the command string
	call os_string_uppercase	; Convert to uppercase for comparison

	mov rdi, cls_string		; 'CLS' entered?
	call os_string_compare
	jc near clear_screen

	mov rdi, dir_string		; 'DIR' entered?
	call os_string_compare
	jc near dir

	mov rdi, ver_string		; 'VER' entered?
	call os_string_compare
	jc near print_ver

	mov rdi, exit_string		; 'EXIT' entered?
	call os_string_compare
	jc near exit

	mov rdi, help_string		; 'HELP' entered?
	call os_string_compare
	jc near print_help

	mov rdi, debug_string		; 'DEBUG' entered?
	call os_string_compare
	jc near debug

	mov rdi, reboot_string		; 'REBOOT' entered?
	call os_string_compare
	jc reboot

	mov rdi, testzone_string	; 'TESTZONE' entered?
	call os_string_compare
	jc near testzone

;; At this point it is not one of the built-in CLI functions. Prepare to check the filesystem.
;	mov al, '.'
;	call os_string_find_char	; Check for a '.' in the string
;	cmp rax, 0
;	jne full_name			; If there was a '.' then a suffix is present
;
; No suffix was present so we add the default application suffix of ".APP"
;add_suffix:
;	call os_string_length
;	cmp rcx, 8
;	jg fail				; If the string is longer than 8 chars we can't add a suffix
;
;	mov rdi, cli_command_string
;	mov rsi, appextension		; '.APP'
;	call os_string_append		; Append the extension to the command string
;
;; cli_command_string now contains a full filename
;full_name:
;	mov rsi, cli_command_string
;	mov rdi, programlocation	; We load the program to this location in memory (currently 0x00100000 : at the 2MB mark)
;	call os_file_read		; Read the file into memory
;	jc fail				; If carry is set then the file was not found
;
;	mov rax, programlocation	; 0x00100000 : at the 2MB mark
;	xor rbx, rbx			; No arguements required (The app can get them with os_get_argc and os_get_argv)
;	call os_smp_enqueue		; Queue the application to run on the next available core
;	jmp exit			; The CLI can quit now. IRQ 8 will restart it when the program is finished

fail:					; We didn't get a valid command or program name
	mov rsi, not_found_msg
	call os_output
	jmp os_command_line

print_help:
	mov rsi, help_text
	call os_output
	jmp os_command_line

clear_screen:
	call os_screen_clear
	mov ax, 0x0018
	call os_move_cursor
	jmp os_command_line

print_ver:
	mov rsi, version_msg
	call os_output
	jmp os_command_line

dir:
	mov rdi, cli_temp_string
	mov rsi, rdi
	call os_file_list
	call os_output
	jmp os_command_line


align 16
testzone:
	xchg bx, bx			; Bochs Magic Breakpoint

;	ud2

;	xor rax, rax
;	xor rbx, rcx
;	xor rcx, rcx
;	xor rdx, rdx
;	div rax

	jmp os_command_line

debug:
	call os_get_argc		; Check the argument number
	cmp al, 1
	je debug_dump_reg		; If it is only one then do a register dump
	mov rcx, 16	
	cmp al, 3			; Did we get at least 3?
	jl noamount			; If not no amount was specified
	mov al, 2
	call os_get_argv		; Get the amount of bytes to display
	call os_string_to_int		; Convert to an integer
	mov rcx, rax
noamount:
	mov al, 1
	call os_get_argv		; Get the starting memory address
	call os_hex_string_to_int
	mov rsi, rax
debug_default:
	call os_debug_dump_mem
	call os_print_newline

	jmp os_command_line

debug_dump_reg:
	call os_debug_dump_reg
	jmp os_command_line

exit:
	ret

; Strings
	help_text		db 'Built-in commands: CLS, DEBUG, DIR, HELP, REBOOT, VER', 13, 0
	not_found_msg		db 'Command or program not found', 13, 0
	version_msg		db 'BareMetal OS ', BAREMETALOS_VER, 13, 0

	cls_string		db 'CLS', 0
	dir_string		db 'DIR', 0
	ver_string		db 'VER', 0
	exit_string		db 'EXIT', 0
	help_string		db 'HELP', 0
	debug_string		db 'DEBUG', 0
	reboot_string		db 'REBOOT', 0
	testzone_string		db 'TESTZONE', 0


; -----------------------------------------------------------------------------
; os_string_find_char -- Find first location of character in a string
;  IN:	RSI = string location
;	AL  = character to find
; OUT:	RAX = location in string, or 0 if char not present
;	All other registers preserved
os_string_find_char:
	push rsi
	push rcx

	mov rcx, 1		; Counter -- start at first char
os_string_find_char_more:
	cmp byte [rsi], al
	je os_string_find_char_done
	cmp byte [rsi], 0
	je os_string_find_char_not_found
	inc rsi
	inc rcx
	jmp os_string_find_char_more

os_string_find_char_done:
	mov rax, rcx

	pop rcx
	pop rsi
	ret

os_string_find_char_not_found:
	pop rcx
	pop rsi
	xor eax, eax	; not found, set RAX to 0
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; os_string_change_char -- Change all instances of a character in a string
;  IN:	RSI = string location
;	AL  = character to replace
;	BL  = replacement character
; OUT:	All registers preserved
os_string_change_char:
	push rsi
	push rcx
	push rbx
	push rax

	mov cl, al
os_string_change_char_loop:
	mov byte al, [rsi]
	cmp al, 0
	je os_string_change_char_done
	cmp al, cl
	jne os_string_change_char_no_change
	mov byte [rsi], bl

os_string_change_char_no_change:
	inc rsi
	jmp os_string_change_char_loop

os_string_change_char_done:
	pop rax
	pop rbx
	pop rcx
	pop rsi
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; os_string_chomp -- Strip leading and trailing spaces from a string
;  IN:	RSI = string location
; OUT:	All registers preserved
os_string_chomp:
	push rsi
	push rdi
	push rcx
	push rax

	call os_string_length		; Quick check to see if there are any characters in the string
	jrcxz os_string_chomp_done	; No need to work on it if there is no data

	mov rdi, rsi			; RDI will point to the start of the string...
	push rdi			; ...while RSI will point to the "actual" start (without the spaces)
	add rdi, rcx			; os_string_length stored the length in RCX

os_string_chomp_findend:		; we start at the end of the string and move backwards until we don't find a space
	dec rdi
	cmp rsi, rdi			; Check to make sure we are not reading backward past the string start
	jg os_string_chomp_fail		; If so then fail (string only contained spaces)
	cmp byte [rdi], ' '
	je os_string_chomp_findend

	inc rdi				; we found the real end of the string so null terminate it
	mov byte [rdi], 0x00
	pop rdi

os_string_chomp_start_count:		; read through string until we find a non-space character
	cmp byte [rsi], ' '
	jne os_string_chomp_copy
	inc rsi
	jmp os_string_chomp_start_count

os_string_chomp_fail:			; In this situataion the string is all spaces
	pop rdi				; We are about to bail out so make sure the stack is sane
	mov al, 0x00
	stosb
	jmp os_string_chomp_done

; At this point RSI points to the actual start of the string (minus the leading spaces, if any)
; And RDI point to the start of the string

os_string_chomp_copy:		; Copy a byte from RSI to RDI one byte at a time until we find a NULL
	lodsb
	stosb
	cmp al, 0x00
	jne os_string_chomp_copy

os_string_chomp_done:
	pop rax
	pop rcx
	pop rdi
	pop rsi
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; os_string_uppercase -- Convert zero-terminated string to uppercase
;  IN:	RSI = string location
; OUT:	All registers preserved
os_string_uppercase:
	push rsi

os_string_uppercase_more:
	cmp byte [rsi], 0x00		; Zero-termination of string?
	je os_string_uppercase_done	; If so, quit
	cmp byte [rsi], 97		; In the uppercase A to Z range?
	jl os_string_uppercase_noatoz
	cmp byte [rsi], 122
	jg os_string_uppercase_noatoz
	sub byte [rsi], 0x20		; If so, convert input char to uppercase
	inc rsi
	jmp os_string_uppercase_more

os_string_uppercase_noatoz:
	inc rsi
	jmp os_string_uppercase_more

os_string_uppercase_done:
	pop rsi
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; os_string_parse -- Parse a string into individual words
;  IN:	RSI = Address of string
; OUT:	RCX = word count
; Note:	This function will remove "extra" whitespace in the source string
;	"This is  a test. " will update to "This is a test."
os_string_parse:
	push rsi
	push rdi
	push rax

	xor ecx, ecx			; RCX is our word counter
	mov rdi, rsi

	call os_string_chomp		; Remove leading and trailing spaces
	
	cmp byte [rsi], 0x00		; Check the first byte
	je os_string_parse_done		; If it is a null then bail out
	inc rcx				; At this point we know we have at least one word

os_string_parse_next_char:
	lodsb
	stosb
	cmp al, 0x00			; Check if we are at the end
	je os_string_parse_done		; If so then bail out
	cmp al, ' '			; Is it a space?
	je os_string_parse_found_a_space
	jmp os_string_parse_next_char	; If not then grab the next char

os_string_parse_found_a_space:
	lodsb				; We found a space.. grab the next char
	cmp al, ' '			; Is it a space as well?
	jne os_string_parse_no_more_spaces
	jmp os_string_parse_found_a_space

os_string_parse_no_more_spaces:
	dec rsi				; Decrement so the next lodsb will read in the non-space
	inc rcx
	jmp os_string_parse_next_char

os_string_parse_done:
	pop rax
	pop rdi
	pop rsi
ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; os_string_compare -- See if two strings match
;  IN:	RSI = string one
;	RDI = string two
; OUT:	Carry flag set if same
os_string_compare:
	push rsi
	push rdi
	push rbx
	push rax

os_string_compare_more:
	mov al, [rsi]			; Store string contents
	mov bl, [rdi]
	cmp al, 0			; End of first string?
	je os_string_compare_terminated
	cmp al, bl
	jne os_string_compare_not_same
	inc rsi
	inc rdi
	jmp os_string_compare_more

os_string_compare_not_same:
	pop rax
	pop rbx
	pop rdi
	pop rsi
	clc
	ret

os_string_compare_terminated:
	cmp bl, 0			; End of second string?
	jne os_string_compare_not_same

	pop rax
	pop rbx
	pop rdi
	pop rsi
	stc
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; os_hex_string_to_int -- Convert up to 8 hexascii to bin
;  IN:	RSI = Location of hex asciiz string
; OUT:	RAX = binary value of hex string
;	All other registers preserved
os_hex_string_to_int:
	push rsi
	push rcx
	push rbx

	cld
	xor ebx, ebx
os_hex_string_to_int_loop:
	lodsb
	mov cl, 4
	cmp al, 'a'
	jb os_hex_string_to_int_ok
	sub al, 0x20				; convert to upper case if alpha
os_hex_string_to_int_ok:
	sub al, '0'				; check if legal
	jc os_hex_string_to_int_exit		; jmp if out of range
	cmp al, 9
	jle os_hex_string_to_int_got		; jmp if number is 0-9
	sub al, 7				; convert to number from A-F or 10-15
	cmp al, 15				; check if legal
	ja os_hex_string_to_int_exit		; jmp if illegal hex char
os_hex_string_to_int_got:
	shl rbx, cl
	or bl, al
	jmp os_hex_string_to_int_loop
os_hex_string_to_int_exit:
	mov rax, rbx				; int value stored in RBX, move to RAX

	pop rbx
	pop rcx
	pop rsi
	ret
; -----------------------------------------------------------------------------


; =============================================================================
; EOF
