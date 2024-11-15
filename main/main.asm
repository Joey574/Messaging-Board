.intel_syntax noprefix
.global _start

.section .rodata
success_code:
    .string "Action completed succesfully\n"
error_code_no_action:
    .string "Action not supported\n"
read_buffer:
    .zero 2048
auth_key:
    .string "9UTAxhU0Qh1ZDwTzK9hqXXaXSjcAWwjAeZbqqt0PvUpSrrbWxiLJ6YAmJFbH4ray"

.section .data
auth_username:
    .zero 64
auth_password:
    .zero 64

.section .text
_start:
# Main
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
    #test rax, rax       # check return value for error
    js .EXIT_FAILURE


    # ===== listen =====
    mov rax, 50         # syscode for listen
    mov rdi, r12        # first param, socket FD
    mov rsi, 0          # second param, backlog, max length queue of requests can grow
    syscall             # call listen
    test rax, rax       # check return value for error
    js .EXIT_FAILURE
    

# Accept Connections
    .ACCEPT:
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

.CHILD_PROCESS:
# Parse Request
    # ===== close connection =====
    mov rax, 3          # syscode for close
    mov rdi, r12        # first param, FD to close, r13 = accepted connection FD
    syscall             # call close

    # ===== read from request =====
    mov rax, 0                      # syscode for read
    mov rdi, r13                    # first param, FD, r13 = accepted request FD
    mov rsi, offset read_buffer     # second param, ptr to read buffer into http_read
    mov rdx, 2048                   # third param, max bytes to read, this case 2048
    syscall                         # call read
    push rax                        # store number of bytes read
    

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

    # ===== write http response =====
    mov rax, 1                          # syscode for write
    mov rdi, r13                        # first param, FD, r13 = accepted connection FD
    mov rsi, offset success_code        # second param, addr to string data
    mov rdx, 29                         # third param, length of string
    syscall                             # call write

    jmp .EXIT_SUCCESS

.PARSE_LOGIN:

.PARSE_SIGNUP:

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

.INDEX_OF:
# Index_of(src_str, str, src_bytes, str_bytes)
# rdi = src_string
# rsi = str
# rdx = src_bytes
# rcx = str_bytes

# uses r10 : r11 : rbx : rax

    xor rax, rax        # src_text counter
    xor rbx, rbx        # string counter

    .INDEX_OF_L1:
    cmp rax, rdx
    jge .INDEX_OF_L4
    mov r10b, BYTE PTR [rdi+rax]
    cmp r10b, BYTE PTR [rsi+rbx]
    jne .INDEX_OF_L2
        inc rax
        inc rbx
        cmp rcx, rbx
        jge .INDEX_OF_L3
        jmp .INDEX_OF_L1
    .INDEX_OF_L2:
        mov r11, rbx
        xor rbx, rbx
        cmp r11, 0
        jne .INDEX_OF_L1
        inc rax
        jmp .INDEX_OF_L1
    .INDEX_OF_L3:
    ret
    .INDEX_OF_L4:
    mov rax, -1
    ret

.NO_ACTION:
# Action not found
    mov rax, 1                              # syscode for write
    mov rdi, r13                            # first param, FD, r13 = accepted connection FD
    mov rsi, offset error_code_no_action    # second param, addr to string data
    mov rdx, 21                             # third param, length of string
    syscall                                 # call write

    jmp .EXIT_FAILURE

.EXIT_SUCCESS:
# exit with status code 0
    mov rsp, rbp        # return stack ptr

    # ===== exit =====
    mov rax, 60         # syscode for exit
    mov rdi, 0          # exit code
    syscall             # call exit

.EXIT_FAILURE:
# exit with error status code
    mov rsp, rbp        # return stack ptr

    # ===== exit =====
    mov rdi, rax        # exit code
    mov rax, 60         # syscode for exit
    syscall             # call exit
