.intel_syntax noprefix
.global _start

.section .rodata
success_code:               .string "Action completed succesfully\n"

error_code_no_action:       .string "Action not supported\n"
error_code_invalid_data:    .string "Data missing from request\n"
error_code_user_exists:     .string "User already exists\n"

auth_key:                   .string "9UTAxhU0Qh1ZDwTzK9hqXXaXSjcAWwjAeZbqqt0PvUpSrrbWxiLJ6YAmJFbH4ray"
users_file:                 .asciiz "../users.txt"

.section .data
read_buffer:    .zero 2048
user_buffer:    .zero 129
username:       .zero 64
password:       .zero 64

.section .text
_start: # Main
    mov rbp, rsp        # save stack ptr

    # ===== socket =====
    mov rax, 41         # syscode for socket
    mov rdi, 2          # first param, domain, AF_INET = 2
    mov rsi, 1          # second param, type, SOCK_STREAM = 1
    mov rdx, 0          # third param, protocol, IPPROTO_IP = 0
    syscall             # call socket, rax now contains socket FD
    test rax, rax       # check return value for error
    js .EXIT_FAILURE
    mov r12, rax        # save socket FD


    # ===== set up sockaddr_in =====
    sub rsp, 16                             # make room for 16 bytes of data on the stack
    mov WORD PTR [rsp], 2                   # first value, sa_family, AF_INET = 2
    mov WORD PTR [rsp+2], 0x697a            # second value, port, big endian 31337
    mov DWORD PTR [rsp+4], 0x7F000001       # third value, ipv4 address, 127.0.0.1
    mov QWORD PTR [rsp+8], 0                # padding, make sure zeroed


    # ===== bind to socket =====
    mov rax, 49         # syscode for bind
    mov rdi, r12        # first param, socket FD
    mov rsi, rsp        # second param, pointer to sockaddr_in
    mov rdx, 16         # third param, size of sockaddr_in
    syscall             # call bind


    # ===== listen =====
    mov rax, 50         # syscode for listen
    mov rdi, r12        # first param, socket FD
    mov rsi, 0          # second param, backlog, max length queue of requests can grow
    syscall             # call listen
    test rax, rax       # check return value for error
    js .EXIT_FAILURE
    

.ACCEPT: # Accept incoming connection
    # ===== accept =====
    mov rax, 43         # syscode for accept
    mov rdi, r12        # first param, socket FD
    mov rsi, 0          # second param, sockaddr
    mov rdx, 0          # third param, sockaddr length
    syscall             # call accept, rax now contains new socket FD
    mov r13, rax        # save new socket FD


     # ===== fork process =====
    mov rax, 57         # syscode for fork
    syscall             # fork

    # ===== check if child =====
    cmp rax, 0
    je .CHILD_PROCESS

    # ==== close connection =====
    mov rax, 3          # syscode for close
    mov rdi, r13        # first param, FD to close, r13 = accepted connection FD
    syscall             # call close

    jmp .ACCEPT         # wait for new request

.CHILD_PROCESS: # Parse request
    # ===== close connection =====
    mov rax, 3          # syscode for close
    mov rdi, r12        # first param, FD to close, r12 = port FD
    syscall             # call close

    # ===== read from request =====
    mov rax, 0                      # syscode for read
    mov rdi, r13                    # first param, FD, r13 = accepted request FD
    mov rsi, offset read_buffer     # second param, ptr to read buffer into http_read
    mov rdx, 2048                   # third param, max bytes to read, this case 2048
    syscall                         # call read
    mov r14, rax

    # Handle user action
    mov al, BYTE PTR [read_buffer]
    cmp al, 'l'
        je .PARSE_LOGIN
    cmp al, 's'
        je .PARSE_SIGNUP
    cmp al, 'r'
        je .PARSE_READ
    cmp al, 'p'
        je .PARSE_POST
    cmp al, 'i'
        je .PARSE_INBOX
    cmp al, 'm'
        je .PARSE_MSG
    jmp .NO_ACTION

.PARSE_LOGIN:

.PARSE_SIGNUP: # Sign the user up for this wonderful messaging board :)
    xor rcx, rcx
    inc rcx

    # Parse username
    .PARSE_SIGNUP_L1:
        cmp rcx, r14                            # if next byte to read is outside passed data, error
            jge .INVALID_ACTION
        cmp rcx, 64                             # if next byte exceeds 64 byte limit, error, jg is used here as rcx is offset from username length by 1
            jg .INVALID_ACTION
        mov al, BYTE PTR [read_buffer+rcx]      # load the passed byte into al
        cmp al, ';'                             # if end of data, cont.
            je .PARSE_SIGNUP_L2
        mov BYTE PTR [username+rcx], al         # store the passed byte in username
        inc rcx                                 # inc counter
        jmp .PARSE_SIGNUP_L1                    # loop

    # Parse password
    .PARSE_SIGNUP_L2:
        xor rdx, rdx                            # counter for password position
        inc rcx                                 # counter for buffer position
    .PARSE_SIGNUP_L3:
        cmp rcx, r14                            # check if next byte exceeds size of data
            jge .INVALID_ACTION
        cmp rdx, 64                             # check if next byte exceeds 64 byte size limit
            jge .INVALID_ACTION
        mov al, BYTE PTR [read_buffer+rcx]      # load byte into al
        cmp al, 0x0a                            # if end of data, cont.
            je .PARSE_SIGNUP_L4
        mov BYTE PTR [password+rdx], al         # store byte in password
        inc rcx
        inc rdx
        jmp .PARSE_SIGNUP_L3
    .PARSE_SIGNUP_L4:

    # Load users.txt and check if the user already exists

    # ===== open users.txt =====
    mov rax, 2                      # syscode for open
    mov rdi, offset users_file      # file to open
    mov rsi, 2                      # flags for read-write
    mov rdx, 0                      # mode, nothing to specify here
    syscall
    mov r12, rax                    # save FD

    # Loop until eof or we find matching user
    .PARSE_SIGNUP_L5:
    mov rax, 0                      # syscode for read
    mov rsi, offset user_buffer     # buffer to read to
    mov rdi, r12                    # users.txt FD
    mov rdx, 129                    # max bytes to read
    syscall

    cmp rax, 129
    jne .PARSE_SIGNUP_L6

    xor rcx, rcx                        # clear similarity counter

    mov rbx, QWORD PTR [buffer]         # load first set of 8 bytes
    cmp rbx, QWORD PTR [username]       # cmp against requested username
    jne PARSE_SIGNUP_NE1
        inc rcx                         # inc similarity counter
    .PARSE_SIGNUP_NE1:
    mov rbx, QWORD PTR [buffer+8]       # load second set of 8 bytes
    cmp rbx, QWORD PTR [username+8]     # cmp against requested username
    jne .PARSE_SIGNUP_NE2
        inc rcx
    .PARSE_SIGNUP_NE2:
    mov rbx, QWORD PTR [buffer+16]       # load third set of 8 bytes
    cmp rbx, QWORD PTR [username+16]     # cmp against requested username
    jne .PARSE_SIGNUP_NE3
        inc rcx
        .PARSE_SIGNUP_NE3:
    mov rbx, QWORD PTR [buffer+24]       # load fourth set of 8 bytes
    cmp rbx, QWORD PTR [username+24]     # cmp against requested username
    jne .PARSE_SIGNUP_NE4
        inc rcx
    .PARSE_SIGNUP_NE4:
    cmp rcx, 4
        je .USER_ALREADY_EXISTS         # if rcx = 4 then in all cases username was equal
    

    .PARSE_SIGNUP_L6:
    # User doesn't exist, so append to users.txt


.PARSE_READ:

.PARSE_POST:

.PARSE_INBOX:

.PARSE_MSG:

    # ===== write http response =====
    mov rax, 1                          # syscode for write
    mov rdi, r13                        # first param, FD, r13 = accepted connection FD
    mov rsi, offset success_code        # second param, addr to string data
    mov rdx, 29                         # third param, length of string
    syscall                             # call write

    jmp .EXIT_SUCCESS

.NO_ACTION: # Action not found: ec = 2
    mov rax, 1                              # syscode for write
    mov rdi, r13                            # first param, FD, r13 = accepted connection FD
    mov rsi, offset error_code_no_action    # second param, addr to string data
    mov rdx, 21                             # third param, length of string
    syscall                                 # call write

    mov rax, 2
    jmp .EXIT_FAILURE

.INVALID_ACTION: # data missing from request: ec = 3
    mov rax, 1                              # syscode for write
    mov rdi, r13                            # first param, FD, r13 = accepted connection FD
    mov rsi, offset error_code_invalid_data # second param, addr to string data
    mov rdx, 26                             # third param, length of string
    syscall                                 # call write

    mov rax, 3
    jmp .EXIT_FAILURE

.USER_ALREADY_EXISTS: # user already exists: ec = 4
    mov rax, 1                              # syscode for write
    mov rdi, r13                            # FD, r13 = accepted connection FD
    mov rsi, offset error_code_user_exists  # error code
    mov rdx, 20                             # bytes to write
    syscall

    mov rax, 4
    jmp .EXIT_FAILURE

.EXIT_SUCCESS: # Exit with status code 0
    mov rsp, rbp        # return stack ptr

    # ===== exit =====
    mov rax, 60         # syscode for exit
    mov rdi, 0          # exit code
    syscall             # call exit

.EXIT_FAILURE: # Exit with some error code
    mov rsp, rbp        # return stack ptr

    # ===== exit =====
    mov rdi, rax        # exit code
    mov rax, 60         # syscode for exit
    syscall             # call exit
