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
    # At this point username and password have already been parsed, password has also been xor-ed, and user_buffer contains user with matching username

    xor rcx, rcx
    .PARSE_LOGIN_L1:
    cmp rcx, 8
        je .PARSE_LOGIN_L2
    mov rbx, QWORD PTR [password+(rcx*8)]               # the password given by user
    cmp rbx, QWORD PTR [user_buffer+64+(rcx*8)]         # cmp against password stored for the user
        jne .INVALID_NAME_O_PASS                        # if != exit with error
    inc rcx
    jmp .PARSE_LOGIN_L1
    .PARSE_LOGIN_L2:

    # xor-ed password matches input, return auth token
    call COMPUTE_AUTH_KEY

    # ===== write http response =====
    mov rax, 1                          # syscode for write
    mov rdi, r13                        # r13 = accepted connection FD
    mov rsi, offset auth_token          # addr to string data
    mov rdx, 64                         # length of string
    syscall

    jmp .EXIT_SUCCESS

.PARSE_SIGNUP: # Sign the user up for this wonderful messaging board :)
    xor rcx, rcx

    # Parse username
    .PARSE_SIGNUP_L1:
        cmp rcx, r14                            # if next byte to read is outside passed data, error
            jge .INVALID_ACTION
        cmp rcx, 64                             # if next byte exceeds 64 byte limit, error
            jge .INVALID_ACTION
        mov al, BYTE PTR [read_buffer+rcx+1]    # load the passed byte into al, offset 1 for action byte
        cmp al, ';'                             # if end of data, cont.
            je .PARSE_SIGNUP_L2
        mov BYTE PTR [username+rcx], al         # store the passed byte in username
        inc rcx                                 
        jmp .PARSE_SIGNUP_L1                    

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

    # xor the password so it's not just plaintext
    call COMPUTE_PASSWORD_HASH


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


    .PARSE_SIGNUP_L6: 
    # User doesn't exist, so append to users.txt
    
    cmp BYTE PTR [read_buffer], 'l'     # check if original action was to login
        je .INVALID_NAME_O_PASS         # in this case, we didn't find matching username

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

    # compute the auth key and return it
    call COMPUTE_AUTH_KEY

    # ===== write http response =====
    mov rax, 1                          # syscode for write
    mov rdi, r13                        # r13 = accepted connection FD
    mov rsi, offset auth_token          # addr to string data
    mov rdx, 64                         # length of string
    syscall

    jmp .EXIT_SUCCESS

.PARSE_READ: # If valid auth key is given, return posts.txt

    cmp r14, 65                     # 65 bytes minimum for action + auth, if not present, exit w error
        jl .INVALID_AUTH_TOKEN

    
    call IS_AUTHED

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
    cmp rax, 1                      # if we didn't read any bytes, finish
        jl .PARSE_READ_L5

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

COMPUTE_AUTH_KEY: # Computes the auth key
    # expects data to compute to be in username and password
    # stores results in auth_token

    # xor xor-ed password with username
    xor rcx, rcx

    .COMPUTE_AUTH_KEY_L1:
    cmp rcx, 8
        jge .COMPUTE_AUTH_KEY_L2
    mov rbx, QWORD PTR [username+(rcx*8)]       # load 8 bytes from the username
    xor rbx, QWORD PTR [password+(rcx*8)]       # xor username with the xor-ed password
    mov QWORD PTR [auth_token+(rcx*8)], rbx     # store in the auth_token
    inc rcx
    jmp .COMPUTE_AUTH_KEY_L1
    .COMPUTE_AUTH_KEY_L2:

    # remove any unprintable characters (adjust range to 33-126)
    xor rcx, rcx
    .COMPUTE_AUTH_KEY_L3:
    cmp rcx, 64                         # we have to go byte by byte for this, until simd gets involved that is
        jge .COMPUTE_AUTH_KEY_L6        # if we've parsed all 64 bytes, exit
    mov bl, BYTE PTR [auth_token+rcx]   # load next byte from the auth token
    cmp bl, 0x21                        # check against 0x21
        jge .COMPUTE_AUTH_KEY_L4
    add bl, 0x21                        # if less then 0x21 we add 0x21
    .COMPUTE_AUTH_KEY_L4:
    cmp bl, 0x7e                        # 7f, 128, is the del character, def don't want that one
        jle .COMPUTE_AUTH_KEY_L5        # if we're less or equal to the max value, exit
    sub bl, 0x5f                        # 5f is used here as 127 - 0x5f leaves us with 32, making sure we don't go under minimum value
    .COMPUTE_AUTH_KEY_L5:
    mov BYTE PTR [auth_token+rcx], bl   # move data back to auth token
    inc rcx
    jmp .COMPUTE_AUTH_KEY_L3
    .COMPUTE_AUTH_KEY_L6:

    ret

COMPUTE_PASSWORD_HASH: # Xors value in password with auth_key, adjusts to printable char range
    # expects the password to be in password
    # xor-ed data will remain in password

    xor rcx, rcx
    .COMPUTE_PASSWORD_L1:
    cmp rcx, 8
        jge .COMPUTE_PASSWORD_L2
    mov rbx, QWORD PTR [password+(rcx*8)]
    xor rbx, QWORD PTR [auth_key+(rcx*8)]
    mov QWORD PTR [password+(rcx*8)], rbx
    inc rcx
    jmp .COMPUTE_PASSWORD_L1
    .COMPUTE_PASSWORD_L2:

   # remove any unprintable characters (adjust range to 33-126)
    xor rcx, rcx
    .COMPUTE_PASSWORD_L3:
    cmp rcx, 64                         # we have to go byte by byte for this, until simd gets involved that is
        jge .COMPUTE_PASSWORD_L6        # if we've parsed all 64 bytes, exit
    mov bl, BYTE PTR [password+rcx]     # load next byte from the auth token
    cmp bl, 0x21                        # check against 0x21
        jge .COMPUTE_PASSWORD_L4
    add bl, 0x21                        # if less then 0x21 we add 0x21
    .COMPUTE_PASSWORD_L4:
    cmp bl, 0x7e                        # 7f, 128, is the del character, def don't want that one
        jle .COMPUTE_PASSWORD_L5        # if we're less or equal to the max value, exit
    sub bl, 0x5f                        # 5f is used here as 127 - 0x5f leaves us with 32, making sure we don't go under minimum value
    .COMPUTE_PASSWORD_L5:
    mov BYTE PTR [password+rcx], bl     # move data back into its position
    inc rcx

    jmp .COMPUTE_PASSWORD_L3
    .COMPUTE_PASSWORD_L6:

    ret

IS_AUTHED: # Ret to cller is user is authed, else errors
    # expects the auth token to check against to be in read_buffer
    # if user is authed, we ret back to caller, else we exit with .INVALID_AUTH_TOKEN

    # ===== open users.txt =====
    mov rax, 2                      # syscode for open
    mov rdi, offset users_file      # file to open
    mov rsi, 0                      # flags for read
    mov rdx, 0                      # mode, nothing to specify here, file already exists
    syscall
    mov r12, rax                    # save FD

    # Loop until eof or we find matching user
    .IS_AUTHED_L1:
    mov rax, 0                      # syscode for read
    mov rsi, offset username        # buffer to read to, will read through username -> password -> newline
    mov rdi, r12                    # users.txt FD
    mov rdx, 129                    # max bytes to read
    syscall

    cmp rax, 129                    # each user takes up 129 bytes, 64 username | 64 password | 1 newline
        jne .INVALID_AUTH_TOKEN     # if out of users to cmp against, exit w failure


    call COMPUTE_AUTH_KEY
    # auth token now contains the computed auth token from the user we're checking against

    # cmp against provided auth key
    xor rcx, rcx
    .IS_AUTHED_L8:
    cmp rcx, 8
        jge .IS_AUTHED_L9
    mov rbx, QWORD PTR [auth_token+(rcx*8)]
    cmp rbx, QWORD PTR [read_buffer+(rcx*8)+1]
        jne .IS_AUTHED_L1
    inc rcx
    jmp .IS_AUTHED_L8
    .IS_AUTHED_L9:
    # user has been authed, return

    # ===== close users.txt =====
    mov rax, 3                  # syscode for close
    mov rdi, r12                # fd for users.txt
    syscall

    ret
