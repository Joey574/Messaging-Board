.intel_syntax noprefix
.global _start

.section .rodata
success_code:               .string "Action completed succesfully\n"

error_code_no_action:       .string "Action not supported\n"
error_code_invalid_data:    .string "Data missing from request\n"
error_code_user_exists:     .string "User already exists\n"
error_code_bad_auth:        .string "Username or password inccorect\n"
error_code_bad_token:       .string "Auth token incorrect\n"

users_file:                 .string "../users.txt"
posts_file:                 .string "../posts.txt"

auth_key:                   .string "9UTAxhU0Qh1ZDwTzK9hqXXaXSjcAWwjAeZbqqt0PvUpSrrbWxiLJ6YAmJFbH4ray"

.section .data
read_buffer:    .zero 2048
user_buffer:    .zero 129

# following 3 must be in order username : password : newline
username:       .zero 64
password:       .zero 64
newline:        .string "\n"

auth_token:     .zero 64

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
    mov r14, rax                    # r14 now contains bytes read

    # Handle user action
    mov al, BYTE PTR [read_buffer]
    cmp al, 'l'
        je .PARSE_SIGNUP            # use signup here for input parsing, jmp to .login later
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

.PARSE_LOGIN: # Log the user in if they exist
    # At this point username and password have already been parsed, and user_buffer contains user with matching username

    xor rcx, rcx

    .PARSE_LOGIN_L1:
    cmp rcx, 8
        je .PARSE_LOGIN_L2
    mov rbx, QWORD PTR [password+(rcx*8)]
    xor rbx, QWORD PTR [auth_key+(rcx*8)]
    mov QWORD PTR [password+(rcx*8)], rbx
    cmp rbx, QWORD PTR [user_buffer+64+(rcx*8)]
        jne .INVALID_NAME_O_PASS
    inc rcx
    jmp .PARSE_LOGIN_L1
    .PARSE_LOGIN_L2:

    # xor-ed password matches input, return auth token
    jmp .RETURN_AUTH_KEY

.PARSE_SIGNUP: # Sign the user up for this wonderful messaging board :)
    xor rcx, rcx

    # Parse username
    .PARSE_SIGNUP_L1:
        cmp rcx, r14                            # if next byte to read is outside passed data, error, jg is used here as data load is offset by 1
            jg .INVALID_ACTION
        cmp rcx, 64                             # if next byte exceeds 64 byte limit, error
            jge .INVALID_ACTION
        mov al, BYTE PTR [read_buffer+rcx+1]    # load the passed byte into al, offset 1 for action byte
        cmp al, ';'                             # if end of data, cont.
            je .PARSE_SIGNUP_L2
        mov BYTE PTR [username+rcx], al         # store the passed byte in username
        inc rcx                                 # inc counter
        jmp .PARSE_SIGNUP_L1                    # loop

    # Parse password
    .PARSE_SIGNUP_L2:
        xor rdx, rdx                            # counter for password position
        add rcx, 2                              # counter for buffer position, last pos is right before ; so add 2 to get to next relevent data
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
    mov rsi, 0x402                  # flags for read-write-append
    mov rdx, 0                      # mode, nothing to specify here, file already exists
    syscall
    mov r12, rax                    # save FD

    # Loop until eof or we find matching user
    .PARSE_SIGNUP_L5:
    mov rax, 0                      # syscode for read
    mov rsi, offset user_buffer     # buffer to read to
    mov rdi, r12                    # users.txt FD
    mov rdx, 129                    # max bytes to read
    syscall

    cmp rax, 129                    # each user takes up 129 bytes, 64 username | 64 password | 1 newline
        jne .PARSE_SIGNUP_L6        # if out of users to cmp against, append user

    xor rcx, rcx            # similarity counter
    xor rdx, rdx            # checks made counter

    .PARSE_SIGNUP_UE1:
    cmp rdx, 8                                  # username = 64 bytes, we compare 8 bytes at a time, we make 8 cmps
        je .PARSE_SIGNUP_UE3
    mov rbx, QWORD PTR [user_buffer+(rdx*8)]    # load the next part of username from users.txt 
    cmp rbx, QWORD PTR [username+(rdx*8)]       # cmp against requested username
        jne .PARSE_SIGNUP_UE2                   # if != -> skip similarity inc
    inc rcx
    .PARSE_SIGNUP_UE2:
    inc rdx                                     # move to next set of bytes
    jmp .PARSE_SIGNUP_UE1                       # loop back

    .PARSE_SIGNUP_UE3:
    cmp rdx, rcx                        # if every byte we checked = bytes that were the same, name already in use
        je .USER_ALREADY_EXISTS         # jmp to error


    .PARSE_SIGNUP_L6: # User doesn't exist, so append to users.txt
    cmp BYTE PTR [read_buffer], 'l'     # check if original action was to login
        je .INVALID_NAME_O_PASS         # in this case, we didn't find matching username

    # first, xor encode the password so it's not just plaintext
    xor rcx, rcx
    .PARSE_SIGNUP_L7:
    cmp rcx, 8
        jge .PARSE_SIGNUP_L8
    mov rbx, QWORD PTR [password+(rcx*8)]
    xor rbx, QWORD PTR [auth_key+(rcx*8)]
    mov QWORD PTR [password+(rcx*8)], rbx
    inc rcx
    jmp .PARSE_SIGNUP_L7
    .PARSE_SIGNUP_L8:


    # ===== write to file =====
    mov rax, 1                  # syscode for write
    mov rdi, r12                # fd for users.txt
    mov rsi, offset username    # start of data we want to write
    mov rdx, 129                # number of bytes to write  
    syscall

    # ===== close file =====
    mov rax, 3                  # syscode for close
    mov rdi, r12                # fd for users.txt
    syscall

    # compute the auth key and return
    jmp .RETURN_AUTH_KEY


.PARSE_READ: # If valid auth key is given, return posts.txt

    cmp r14, 65                     # 65 bytes minimum for action + auth if not present, exit w error
        jl .INVALID_AUTH_TOKEN

    # ===== open users.txt =====
    mov rax, 2                      # syscode for open
    mov rdi, offset users_file      # file to open
    mov rsi, 0                      # flags for read
    mov rdx, 0                      # mode, nothing to specify here, file already exists
    syscall
    mov r12, rax                    # save FD

    # Loop until eof or we find matching user
    .PARSE_READ_L1:
    mov rax, 0                      # syscode for read
    mov rsi, offset user_buffer     # buffer to read to
    mov rdi, r12                    # users.txt FD
    mov rdx, 129                    # max bytes to read
    syscall

    cmp rax, 129                    # each user takes up 129 bytes, 64 username | 64 password | 1 newline
        jne .INVALID_AUTH_TOKEN     # if out of users to cmp against, exit w failure

    # compute auth token for the user and see if they match
    xor rcx, rcx
    .PARSE_READ_L2:
    cmp rcx, 8                                      # if auth tokens match, exit
        jge .PARSE_READ_L3
    mov rbx, QWORD PTR [user_buffer+(rcx*8)]        # load username from users.txt
    xor rbx, QWORD PTR [user_buffer+64+(rcx*8)]     # compute hash for given user
    cmp rbx, QWORD PTR [read_buffer+(rcx*8)+1]      # check given hash against user hash
        jne .PARSE_READ_L1                          # move onto next user to check against if hash !=
    inc rcx
    jmp .PARSE_READ_L2
    .PARSE_READ_L3:
    # user has been authed, write posts.txt back


    # ===== close users.txt =====
    mov rax, 3                  # syscode for close
    mov rdi, r12                # fd for users.txt
    syscall


    # ===== open posts.txt =====
    mov rax, 2                      # syscode for open
    mov rdi, offset posts_file      # file to open
    mov rsi, 0                      # flags for read
    mov rdx, 0                      # mode, nothing to specify here, file already exists
    syscall
    mov r12, rax                    # save FD for posts.txt


    .PARSE_READ_L4:
    # ===== read posts.txt =====
    mov rax, 0                      # syscode for read
    mov rsi, offset read_buffer     # buffer to read to
    mov rdi, r12                    # users.txt FD
    mov rdx, 2048                   # max bytes to read
    syscall
    cmp rax, 0                      # if we didn't read any bytes, finish
        jge .PARSE_READ_L5

    # ==== write data back =====
    mov rdx, rax                    # rdx now has bytes we just read
    mov rax, 1                      # syscode for write
    mov rdi, r13                    # r13 = FD for accepted connection
    mov rsi, offset read_buffer     # data we just read from file
    syscall
    jmp .PARSE_READ_L4              # loop back

    .PARSE_READ_L5:
    # ==== close posts.text =====
    mov rax, 3                  # syscode for close
    mov rdi, r12                # fd for posts.txt
    syscall

    jmp .EXIT_SUCCESS

.PARSE_POST:

.PARSE_INBOX:

.PARSE_MSG:

    # ===== write response =====
    mov rax, 1                          # syscode for write
    mov rdi, r13                        # first param, FD, r13 = accepted connection FD
    mov rsi, offset success_code        # second param, addr to string data
    mov rdx, 29                         # third param, length of string
    syscall                             # call write

    jmp .EXIT_SUCCESS

.RETURN_AUTH_KEY:

    # xor xor-ed password with username
    xor rcx, rcx

    .RETURN_AUTH_KEY_L1:
    cmp rcx, 8
        jge .RETURN_AUTH_KEY_L2
    mov rbx, QWORD PTR [username+(rcx*8)]
    xor rbx, QWORD PTR [password+(rcx*8)]
    mov QWORD PTR [auth_token+(rcx*8)], rbx
    inc rcx
    jmp .RETURN_AUTH_KEY_L1
    .RETURN_AUTH_KEY_L2:

    # ===== write http response =====
    mov rax, 1                          # syscode for write
    mov rdi, r13                        # r13 = accepted connection FD
    mov rsi, offset auth_token          # addr to string data
    mov rdx, 64                         # length of string
    syscall

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

    # check if original action was to login, in which case, good job, user was found
    cmp BYTE PTR [read_buffer], 'l'
        je .PARSE_LOGIN

    mov rax, 1                              # syscode for write
    mov rdi, r13                            # FD, r13 = accepted connection FD
    mov rsi, offset error_code_user_exists  # error code
    mov rdx, 20                             # bytes to write
    syscall

    mov rax, 4
    jmp .EXIT_FAILURE

.INVALID_NAME_O_PASS: # invalid username / password, or username not found: ec = 5
    mov rax, 1                              # syscode for write
    mov rdi, r13                            # r13 = accepted connection FD
    mov rsi, offset error_code_bad_auth     # addr to string data
    mov rdx, 31                             # bytes to write
    syscall

    mov rax, 5
    jmp .EXIT_FAILURE

.INVALID_AUTH_TOKEN: # auth token doesn't match any users, ec = 6
    mov rax, 1                              # syscode for write
    mov rdi, r13                            # r13 = accepted connection FD
    mov rsi, offset error_code_bad_token    # addr to string data
    mov rdx, 21                             # bytes to write
    syscall

    mov rax, 6
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
