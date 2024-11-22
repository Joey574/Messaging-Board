import socket
import time
import sys
import string
import random
from concurrent.futures import ThreadPoolExecutor

def get_string(length):
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))

def generate_signup_message():
    username = get_string(63)
    password = get_string(63)
    users.append({'username': username, 'password': password, 'auth': None})
    return f"s{username};{password}\n"

def generage_login_message(i):
    return f"l{users[i]['username']};{users[i]['password']}\n"

def generate_post_message(i):
    return f"p{users[i]['auth']}this is a post :)\n"

def generate_inbox_message(i):
    return f"i{users[i]['auth']}\n"

def make_request(host, port, message, req_type, i=0):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.connect((host, port))
        start_time = time.time()
        s.sendall(message.encode('ascii'))
        response = s.recv(128)
        elapsed_time = time.time() - start_time
        response_str = response.decode('ascii', errors='ignore')

        if req_type == 1:
            users[i]['auth'] = response_str.strip('\n')

    return response_str, elapsed_time

def request_manager(host, port, num_requests, num_threads, req_type):
    response_times = []

    with ThreadPoolExecutor(max_workers=num_threads) as executor:
        if req_type == 0:
            futures = [executor.submit(make_request, host, port, generate_signup_message(), req_type=0) for _ in range(num_requests)]
        elif req_type == 1:
            futures = [executor.submit(make_request, host, port, generage_login_message(i), req_type=1, i=i) for i in range(num_requests)]
        elif req_type == 2:
            futures = [executor.submit(make_request, host, port, generate_post_message(i), req_type=2) for i in range(num_requests)]
        elif req_type == 3:
            futures = [executor.submit(make_request, host, port, generate_inbox_message(i), req_type=3) for i in range(num_requests)]


        for future in futures:
            response, elapsed_time = future.result()
            response_times.append(elapsed_time)

            with open('log.txt', 'a') as log:
                if len(response) > 0:
                    if response[-1] == '\n':
                        log.write(f"request type: {req_type} response: {response}")
                    else:
                        log.write(f"request type: {req_type} response: {response}\n")
                else:
                    log.write(f"request type: {req_type} response:\n")
                log.close()

    return response_times

# execution starts here
users = []

requests = [
    "signup",
    "login",
    "post",
    "inbox"
]

host = "localhost"
port = int(sys.argv[1])
num_requests = 100
num_threads = 10

for i in range(len(requests)):
    response_times = request_manager(host, port, num_requests, num_threads, i)
    rmin = min(response_times)
    rmax = max(response_times)
    ravg = sum(response_times) / num_requests
    print(f"Times ({requests[i]}):\nAvg: {ravg}\nMin: {rmin}\nMax: {rmax}\n")
