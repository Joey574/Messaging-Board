.intel_syntax noprefix
.global _start

.section .rodata
http_ok:
    .string "hello there\n"
http_read_buf:
    .zero 2048
auth_token:
    .string "auth="
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
    mov rsi, offset http_read_buf   # second param, ptr to read buffer into http_read
    mov rdx, 1024                   # third param, max bytes to read, this case 1024
    syscall                         # call read

    # ===== check for auth cookie =====
    xor rcx, rcx
    xor rdx, rdx

    .L1:
    cmp rcx, 1024                           # if len > http_response_size -> exit
    je .EXIT_FAILURE
    mov al, BYTE PTR [auth_token+rdx]       # mov into al auth token to compare against
    mov bl, BYTE PTR [http_read_buf+rcx]    # mov into bl http response to compare
    cmp al, bl
    jne .L2
        # if token = response inc values to check against
        inc rdx
        inc rcx
        cmp rdx, 4
        jg .L3
        # if next value to check >= len('auth=') -> exit
        jmp .L1
    .L2:
        # if token != response, reset auth token we're checking againt
        inc rcx
        xor rdx, rdx
        jmp .L1
    .L3:

    # ===== read auth data =====
    xor rdx, rdx
    .L4:
    mov al, BYTE PTR [http_read_buf+rcx]
    cmp al, '|'
    je .L5
        mov BYTE PTR [auth_username+rdx], al
        inc rcx
        inc rdx
        jmp .L4
    .L5:
    xor rdx, rdx
    .L6:
    mov al, BYTE PTR [http_read_buf+rcx]
    cmp al, ' '
    je .L7
        xor al, BYTE PTR [auth_key+rdx]
        mov BYTE PTR [auth_password+rdx], al

    .L7:


    # ===== write http response =====
    mov rax, 1                          # syscode for write
    mov rdi, r13                        # first param, FD, r13 = accepted connection FD
    mov rsi, offset auth_username       # second param, addr to string data
    mov rdx, 64                         # third param, length of string
    syscall                             # call write

    jmp .EXIT_SUCCESS

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
